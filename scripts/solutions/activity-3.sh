#!/usr/bin/env bash
# SOLUTION — Activity 3 (DLP and Logging). Use it only if you get stuck.
set -euo pipefail
source "$(dirname "$0")/../00-env.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TOKEN=$(gcloud auth print-identity-token)

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$RUN_SA" --role="roles/storage.objectCreator"
sleep 30

# Create the metric BEFORE scanning: log-based metrics only count new entries
gcloud logging metrics create dlp_findings --config-from-file="$ROOT/monitoring/dlp_findings_metric.yaml" || true

for f in customers.csv support_tickets.txt; do
  curl -s -X POST "$URL/upload" -H "Authorization: Bearer $TOKEN" -H "X-API-Key: $API_KEY" -F "file=@$ROOT/sample_data/$f"; echo
done

pip install --quiet -r "$ROOT/dlp/requirements.txt"
python "$ROOT/dlp/scan_and_log.py" "$BUCKET"

gcloud logging read 'logName:"dlp-findings" AND jsonPayload.event="dlp_finding"' --freshness=1h --limit=10 \
  --format='table(timestamp.date("%H:%M:%S"), severity, jsonPayload.info_type, jsonPayload.likelihood, jsonPayload.object)'
