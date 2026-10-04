#!/usr/bin/env bash
# SOLUTION — Activity 2 (IAM: a VM reads BigQuery). Use it only if you get stuck.
set -euo pipefail
source "$(dirname "$0")/../00-env.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

gcloud iam service-accounts create vm-sa --display-name="bq-reader-vm" || true

gcloud compute instances create "$VM" --zone="$ZONE" --machine-type=e2-micro \
  --service-account="$VM_SA" --scopes=cloud-platform \
  --image-family=debian-12 --image-project=debian-cloud

bq query --nouse_legacy_sql --location="$REGION" \
  "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`${PROJECT_ID}.${DATASET}\` TO \"serviceAccount:${VM_SA}\""

sleep 30
gcloud compute ssh "$VM" --zone="$ZONE" --tunnel-through-iap --quiet \
  --command="bq --project_id=$PROJECT_ID head -n 3 $DATASET.customers"
