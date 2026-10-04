# GCP Security — IAM · DLP · Logging · Monitoring

Four short activities that put into practice the **Google Security and Logging** session:

| # | Activity | Topic | Time |
|---|---|---|---|
| — | [Setup](#setup-5-min): prepare the project (one script) | — | 5 min |
| **1** | [Cloud Run reads Cloud Storage](#activity-1--cloud-run-reads-cloud-storage-15-min) | IAM | 10 min |
| **2** | [A Compute Engine VM reads BigQuery](#activity-2--a-compute-engine-vm-reads-bigquery-15-min) | IAM | 15 min |
| **3** | [Scan files with DLP and review the findings in Logging](#activity-3--scan-files-with-dlp-and-review-them-in-logging-20-min) | DLP · Logging | 20 min |
| **4** | [Build and present a dashboard](#activity-4--build-and-present-a-dashboard-20-min) | Monitoring | 20 min + 3 min per team |

Each activity builds on the previous one, so do them in order.

---

## Before you start

- A Google Cloud project with billing enabled, where you are **Owner**.
- **Cloud Shell** (the `>_` icon at the top right of the console).
- Work in **pairs** if you can: some optional steps ask you to grant a role to your partner and check what they can (and cannot) do.

> [!WARNING]
> **Cost:** a few cents, as long as you run the [clean-up](#clean-up) at the end.

> [!IMPORTANT]
> The files in `sample_data/` contain **made-up** personal data: test card numbers, fictitious DNIs and emails on `example.com`. Never upload real data to a lab.


---

## Setup (5 min)

```bash
git clone https://github.com/<your-user>/gcp-security-activities.git
cd gcp-security-activities
gcloud config set project <YOUR_PROJECT_ID>
source scripts/00-env.sh
bash scripts/setup.sh
```

The script enables the APIs and creates what is *not* part of the exercise:

- a bucket `gs://<project>-lab-files` with a file `reports/sales_by_city.csv`;
- a BigQuery table `lab_data.customers` with 5 fake customers;
- an SSH-via-IAP rule so you can connect to the VM.

> [!TIP]
> **Instructor:** if you ask students to run `setup.sh` before class, Activity 1 starts straight away.

---

## Activity 1 · Cloud Run reads Cloud Storage (15 min)

![Activity 1](images/activity-1.svg)

**Key idea:** in IAM, a policy is **principal + role, attached to a resource**. In Activities 1 and 2 there are **two different principals**:

- **you** (a person), who needs to *call* or *see* the service;
- **a service account** (the app's identity), which needs to *read the data*.

Each one gets **only its role**, and **on the specific resource**.

**Goal:** a user can invoke the Cloud Run service, and the service can read the files in the bucket.

**1. Give the app its own identity**

```bash
gcloud iam service-accounts create run-sa --display-name="file-service (Cloud Run)"
```

**2. Deploy the private service**

```bash
gcloud run deploy $SERVICE --source=app --region=$REGION \
  --service-account=$RUN_SA \
  --no-allow-unauthenticated \
  --set-env-vars=BUCKET_NAME=$BUCKET
```

If it asks to create an Artifact Registry repository, answer **Y**. While it builds, read [`app/main.py`](app/main.py): the code **has no credentials**. It can only do what IAM allows `run-sa` to do.

```bash
source scripts/00-env.sh      # loads $URL
```

**3. Who can call it? → `roles/run.invoker`**

```bash
# Without identifying yourself
curl -s -o /dev/null -w "%{http_code}\n" $URL/files
# 403  ← Cloud Run's IAM stops it before it reaches the code

# Identifying yourself (as Owner you already have run.invoker)
curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" $URL/files
```

The second call does reach the app, but it returns **a different error**:

```json
{"action": "storage.objects.list", "error": "permission denied",
 "hint": "the Cloud Run service account is missing an IAM role on the bucket", ...}
```

You have permission to call the service, but **the service has no permission on the bucket**. They are two separate grants.

**4. What can the app read? → `roles/storage.objectViewer` on the bucket**

```bash
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$RUN_SA" \
  --role="roles/storage.objectViewer"
```

Wait about 30 s and try again:

```bash
export TOKEN=$(gcloud auth print-identity-token)
curl -s -H "Authorization: Bearer $TOKEN" $URL/files
# {"bucket": "...", "files": ["reports/sales_by_city.csv"]}

curl -s -H "Authorization: Bearer $TOKEN" $URL/files/reports/sales_by_city.csv
# {"file": "reports/sales_by_city.csv", "first_lines": ["city,orders,revenue_eur", ...]}
```

✅ **Check:** `/files` returns the list and you can read the CSV.

**5. (Pairs, optional) Give your partner `run.invoker`**

```bash
gcloud run services add-iam-policy-binding $SERVICE --region=$REGION \
  --member="user:<partner-email>" --role="roles/run.invoker"
```

Your partner runs `curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" <your-URL>/files` and gets the list. **They have no other permission in your project**: they cannot see the bucket in the console.

<details>
<summary>Activity 1 questions</summary>

1. *The call without a token returned 403 and the one with a token returned "permission denied" from the app. Which principal was missing a role in each case?*
   Without a token: **you** (the caller), missing `run.invoker`; Cloud Run's IAM stops it. With a token: **`run-sa`** (the app), missing `storage.objectViewer` on the bucket.
2. *Why did we grant `objectViewer` on the bucket and not on the project?*
   So the app can read **only that bucket**, not every bucket in the project (least privilege, smaller *blast radius*).
</details>

---

## Activity 2 · A Compute Engine VM reads BigQuery (15 min)

![Activity 2](images/activity-2.svg)

**Goal:** an app running on a VM can read the BigQuery table, and a user can *see* the VM without being able to touch it.

**1. Identity for the VM and the VM itself**

```bash
gcloud iam service-accounts create vm-sa --display-name="bq-reader-vm"

gcloud compute instances create $VM --zone=$ZONE --machine-type=e2-micro \
  --service-account=$VM_SA --scopes=cloud-platform \
  --image-family=debian-12 --image-project=debian-cloud
```

> [!NOTE]
> `--scopes=cloud-platform` leaves access control entirely to **IAM**. Old *access scopes* are a legacy mechanism; today you control access with roles.

**2. Try to read the table from the VM**

```bash
gcloud compute ssh $VM --zone=$ZONE --tunnel-through-iap \
  --command="bq --project_id=$PROJECT_ID head -n 3 $DATASET.customers"
```

The first time, it asks you to create an SSH key (press Enter). Result: **Access Denied**. `vm-sa` has no permission on the dataset.

**3. Grant `roles/bigquery.dataViewer` only on the dataset**

In BigQuery you can grant roles with SQL:

```bash
bq query --nouse_legacy_sql --location=$REGION \
  "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`${PROJECT_ID}.${DATASET}\` TO \"serviceAccount:${VM_SA}\""
```

You can also do it in the console: **BigQuery → lab_data → Sharing → Permissions → Add principal**.

Repeat the command from step 2:

```text
+-------------+---------------+---------------------------+ ...
| customer_id |   full_name   |           email           |
+-------------+---------------+---------------------------+
|        1001 | Laura Gómez   | laura.gomez@example.com   |
```

✅ **Check:** the VM reads the table.

**4. Read vs query: an extra trap**

Now try running SQL from the VM:

```bash
gcloud compute ssh $VM --zone=$ZONE --tunnel-through-iap \
  --command="bq --project_id=$PROJECT_ID query --nouse_legacy_sql 'SELECT city, COUNT(*) n FROM $DATASET.customers GROUP BY city'"
```

It fails with `bigquery.jobs.create permission`. `dataViewer` lets you **read the data**, but a query is a **job**, and running jobs needs another role: `roles/bigquery.jobUser` **on the project**.

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$VM_SA" --role="roles/bigquery.jobUser"
```

Wait 30 s and try again: it works now. **Least privilege means giving exactly the roles needed, sometimes more than one.**

**5. `roles/compute.viewer`: see without touching**

```bash
gcloud iam roles describe roles/compute.viewer --format="value(includedPermissions)" \
  | tr ';' '\n' | grep -E "instances\.(get|list|start|stop|delete)$"
```

It contains `compute.instances.get` and `list`, but **not** `start`, `stop` or `delete`.
**Pairs, optional:** grant it to your partner (`gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:<email>" --role="roles/compute.viewer"`). Your partner can list your VMs with `gcloud compute instances list --project=<your-project>`, but gets a 403 if they try `gcloud compute instances stop`.

<details>
<summary>Activity 2 questions</summary>

1. *Why was `dataViewer` enough for `bq head` but not for `bq query`?*
   `bq head` reads table rows directly (`tables.getData`). `bq query` creates a **job** (`bigquery.jobs.create`), which needs `roles/bigquery.jobUser` on the project.
2. *Which principal got which role in this activity?*
   `vm-sa` → `bigquery.dataViewer` (on the dataset) and `bigquery.jobUser` (on the project); your partner → `compute.viewer`.
</details>

---

## Activity 3 · Scan files with DLP and review them in Logging (20 min)

![Activity 3](images/activity-3.svg)

The service from Activity 1 now also lets you **upload files**. Users will upload customer lists and support tickets full of personal data. Your job: **find it with DLP and record it in Logging** (in Activity 4 you will watch it all on a dashboard).

**1. The app needs to write: `roles/storage.objectCreator`**

Try to upload a file:

```bash
export TOKEN=$(gcloud auth print-identity-token)
curl -s -X POST $URL/upload -H "Authorization: Bearer $TOKEN" -F "file=@sample_data/customers.csv"
# {"action": "storage.objects.create", "error": "permission denied", ...}
```

`objectViewer` (from Activity 1) only allows reading. Add the role that allows **creating** objects:

```bash
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$RUN_SA" --role="roles/storage.objectCreator"
```

Wait 30 s and upload the two files:

```bash
curl -s -X POST $URL/upload -H "Authorization: Bearer $TOKEN" -F "file=@sample_data/customers.csv"
curl -s -X POST $URL/upload -H "Authorization: Bearer $TOKEN" -F "file=@sample_data/support_tickets.txt"
# {"stored": "gs://.../uploads/3f9a1c2b-customers.csv"}
```

> [!NOTE]
> `objectCreator` creates but **cannot overwrite or delete**. That is why the app adds a random prefix to each name.

**2. Prepare the metric before scanning**

The DLP script writes **one log entry per finding**. To chart them later in Activity 4, create now a **log-based metric** that counts them by InfoType. It only counts entries that arrive *after* it is created.

```bash
gcloud logging metrics create dlp_findings --config-from-file=monitoring/dlp_findings_metric.yaml
```

**3. Scan with DLP → `roles/dlp.user`**

The person running the scan needs `roles/dlp.user` (as Owner you already have it):

```bash
pip install --quiet -r dlp/requirements.txt
python dlp/scan_and_log.py $BUCKET
```

```text
uploads/3f9a1c2b-customers.csv                 27 findings  → masked copy: masked/3f9a1c2b-customers.csv
uploads/8d2e4b10-support_tickets.txt           10 findings  → masked copy: masked/8d2e4b10-support_tickets.txt

Total by InfoType:
  EMAIL_ADDRESS          8
  PHONE_NUMBER           7
  ...
```

The exact numbers may vary slightly, because DLP uses statistical models. Compare an original file with its masked copy:

```bash
gcloud storage cat "gs://$BUCKET/masked/*customers.csv" | head -3
```

**4. Review the findings in Cloud Logging → `roles/logging.viewer`**

Open **Logging → Logs Explorer** and run these queries. Read each result before going to the next.

```text
logName:"dlp-findings" AND jsonPayload.event="dlp_finding"
```
→ One entry per finding. Use **Fields → jsonPayload.info_type** in the left panel to see the count by type.

```text
logName:"dlp-findings" AND jsonPayload.event="dlp_finding" AND severity>=WARNING
```
→ Only findings with high likelihood (`LIKELY` or `VERY_LIKELY`).

```text
resource.type="cloud_run_revision" AND jsonPayload.event="permission_denied"
```
→ The errors from Activities 1 and 3: **the app logged every time IAM said no**, and which permission was missing.

The same thing from the terminal:

```bash
gcloud logging read 'logName:"dlp-findings" AND jsonPayload.event="dlp_finding"' --freshness=1h --limit=10 \
  --format='table(timestamp.date("%H:%M:%S"), severity, jsonPayload.info_type, jsonPayload.likelihood, jsonPayload.object)'
```

> [!IMPORTANT]
> Look at a log entry: it records the **type** of data (`CREDIT_CARD_NUMBER`) and the file, but **never the number itself**. If you logged the sensitive value, you would be copying personal data into another place: the logs.

**Pairs, optional:** grant your partner `roles/logging.viewer` on your project. They can read your logs, but they cannot see the files in the bucket.

✅ **Check:** you see the findings in Logs Explorer, and a masked copy of each file exists under `masked/`.

<details>
<summary>Activity 3 questions</summary>

1. *Which 4 roles take part in this activity, and who has each one?*
   `storage.objectViewer` + `storage.objectCreator` → `run-sa`; `dlp.user` and `logging.viewer` → you.
2. *Why doesn't `run-sa` need `dlp.user`?* Because the app does not call DLP: the scan is run by a person (or another process with its own identity).
3. *Which file has more findings and why?* `customers.csv`: it is a table with personal data in every column. The tickets mix free text with only a few data points.
</details>

---

## Activity 4 · Build and present a dashboard (20 min)

![Activity 4](images/activity-4.svg)

**Goal:** build a dashboard in **Cloud Monitoring** (`roles/monitoring.editor`) that would let a security team see, at a glance, how the service is doing and how much sensitive data is coming in. **Afterwards you present it.**

**1. Generate traffic in a second Cloud Shell tab**

Open another tab (`+`), then:

```bash
cd gcp-security-activities && source scripts/00-env.sh
bash scripts/generate-traffic.sh 10
```

It simulates 10 minutes of real use: listings, reads, uploads, **404s** (files that do not exist) and **403s** (calls without a token). While it runs, go on to the next step.

**2. Run the scan again so the metric has data**

```bash
python dlp/scan_and_log.py $BUCKET
```

**3. Build the dashboard in the console**

**Monitoring → Dashboards → Create dashboard**. Give it a name with your team: `File Service — Team <name>`.

Add these widgets with **+ Add widget → Line / Stacked bar** and pick the metric with the selector:

| # | Widget | Metric to search for | Configuration |
|---|---|---|---|
| 1 | **Requests by response class** | `Cloud Run Revision › Request Count` | Filter `service_name = file-service` · Group by `response_code_class` |
| 2 | **Latency p95** | `Cloud Run Revision › Request Latencies` | Filter `service_name = file-service` · Aggregation **95th percentile** |
| 3 | **DLP findings by type** | `logging/user/dlp_findings` | Group by `info_type` · Stacked bar |
| 4 | **Your choice** | any metric you like | e.g. instances (`Container Instance Count`), 4xx errors only, a *scorecard*… |

> [!TIP]
> If you get stuck, you can import the solution with `gcloud monitoring dashboards create --config-from-file=monitoring/dashboard-solution.json`. **But the one you present must be yours**, with at least widget 4 chosen by you.

**4. Prepare the presentation**

Take a screenshot of the dashboard and prepare the presentation (step 5).

✅ **Check:** the 4 widgets show data. If one is empty, wait 2 minutes: metrics arrive with a delay.

**5. Present your dashboard**

Each team has **3 minutes** and answers these four points, with the dashboard on screen:

1. **What it shows.** One sentence per widget: what it measures and why it matters for security.
2. **What you saw.** At least **one real observation** from your data. For example: *"10% of the requests are 403: calls without a token"*, or *"most findings are EMAIL_ADDRESS"*.
3. **Your widget.** Why you chose widget 4 and what question it answers.
4. **Which alert would you create?** Name one alerting policy that would be built on this dashboard. For example: *"notify if `dlp_findings` of type CREDIT_CARD_NUMBER goes above 0 in 5 minutes"*.

**Evaluation guide (for the instructor):**

| Criterion | 0 | 1 | 2 |
|---|---|---|---|
| The 4 widgets work and are understandable | — | some empty or no title | all with data and a clear title |
| They explain what each widget measures | no | partly | yes, linked to security |
| Real observation from their data | none | generic | specific, with numbers |
| Proposed alert | none | vague | metric + threshold + window |

---

## Clean up

```bash
source scripts/00-env.sh
bash scripts/cleanup.sh
```

This deletes the service, VM, bucket, dataset, metric, solution dashboard, service accounts and images. **Delete your team dashboard by hand** in Monitoring → Dashboards, and remove any roles you granted to your partner.

---

## References

[IAM roles for Cloud Run](https://cloud.google.com/run/docs/reference/iam/roles) ·
[Cloud Storage IAM roles](https://cloud.google.com/storage/docs/access-control/iam-roles) ·
[BigQuery GRANT statement](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-control-language) ·
[Sensitive Data Protection InfoTypes](https://cloud.google.com/sensitive-data-protection/docs/infotypes-reference) ·
[Log-based metrics with labels](https://cloud.google.com/logging/docs/logs-based-metrics/labels) ·
[Cloud Monitoring dashboards](https://cloud.google.com/monitoring/dashboards)
