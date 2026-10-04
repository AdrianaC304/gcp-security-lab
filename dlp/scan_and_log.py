"""
Scan every file under gs://<bucket>/uploads/ with DLP (Sensitive Data Protection).

For each file it:
  1. inspects the content looking for personal data (InfoTypes),
  2. writes ONE log entry per finding to Cloud Logging, in the log "dlp-findings"
     (type, likelihood and file — never the sensitive value itself),
  3. saves a de-identified copy under masked/.

Usage (Cloud Shell, from the repo root):
    pip install -r dlp/requirements.txt
    python dlp/scan_and_log.py <bucket-name>

Needs roles/dlp.user, permission to read/write the bucket and to write logs.
"""
import argparse
import os
import subprocess
from collections import Counter

from google.cloud import dlp_v2, storage
from google.cloud import logging as cloud_logging

INFO_TYPES = ["PERSON_NAME", "EMAIL_ADDRESS", "PHONE_NUMBER", "CREDIT_CARD_NUMBER", "SPAIN_DNI_NUMBER"]
LOG_NAME = "dlp-findings"


def current_project():
    return os.environ.get("GOOGLE_CLOUD_PROJECT") or subprocess.check_output(
        ["gcloud", "config", "get-value", "project"], text=True).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bucket", help="bucket name, without gs://")
    ap.add_argument("--prefix", default="uploads/")
    args = ap.parse_args()

    project = current_project()
    parent = f"projects/{project}/locations/global"
    gcs = storage.Client(project=project)
    dlp = dlp_v2.DlpServiceClient(client_options={"quota_project_id": project})
    logger = cloud_logging.Client(project=project).logger(LOG_NAME)

    inspect_config = {
        "info_types": [{"name": n} for n in INFO_TYPES],
        "min_likelihood": dlp_v2.Likelihood.POSSIBLE,
    }
    deidentify_config = {"info_type_transformations": {"transformations": [
        {"info_types": [{"name": "CREDIT_CARD_NUMBER"}],
         "primitive_transformation": {"character_mask_config": {"masking_character": "#", "number_to_mask": 12}}},
        {"info_types": [{"name": n} for n in INFO_TYPES if n != "CREDIT_CARD_NUMBER"],
         "primitive_transformation": {"replace_with_info_type_config": {}}},
    ]}}

    blobs = [b for b in gcs.list_blobs(args.bucket, prefix=args.prefix) if not b.name.endswith("/")]
    if not blobs:
        raise SystemExit(f"No files under gs://{args.bucket}/{args.prefix} — upload something first.")

    grand_total = Counter()
    for blob in blobs:
        text = blob.download_as_text()
        result = dlp.inspect_content(request={
            "parent": parent, "inspect_config": inspect_config, "item": {"value": text}}).result

        # One log entry per finding. Note: we log the TYPE of data, never the value.
        batch = logger.batch()
        counts = Counter()
        for f in result.findings:
            counts[f.info_type.name] += 1
            batch.log_struct(
                {"event": "dlp_finding", "object": f"gs://{args.bucket}/{blob.name}",
                 "info_type": f.info_type.name, "likelihood": f.likelihood.name},
                severity="WARNING" if f.likelihood >= dlp_v2.Likelihood.LIKELY else "NOTICE",
            )
        batch.log_struct({"event": "dlp_scan_summary", "object": f"gs://{args.bucket}/{blob.name}",
                          "total_findings": len(result.findings), "by_info_type": dict(counts)}, severity="INFO")
        batch.commit()
        grand_total.update(counts)

        masked = dlp.deidentify_content(request={
            "parent": parent, "deidentify_config": deidentify_config,
            "inspect_config": inspect_config, "item": {"value": text}}).item.value
        masked_name = "masked/" + blob.name.split("/")[-1]
        gcs.bucket(args.bucket).blob(masked_name).upload_from_string(masked)

        print(f"{blob.name:<45} {len(result.findings):>3} findings  → masked copy: {masked_name}")

    print("\nTotal by InfoType:")
    for name, n in grand_total.most_common():
        print(f"  {name:<22} {n}")
    print(f'\nFindings written to Cloud Logging → log name "{LOG_NAME}".')


if __name__ == "__main__":
    main()
