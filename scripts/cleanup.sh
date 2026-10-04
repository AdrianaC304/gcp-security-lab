#!/usr/bin/env bash
# Deletes everything created in the lab. Safe to run more than once.
set -uo pipefail
source "$(dirname "$0")/00-env.sh"

gcloud run services delete "$SERVICE" --region="$REGION" --quiet 2>/dev/null
gcloud compute instances delete "$VM" --zone="$ZONE" --quiet 2>/dev/null
gcloud compute firewall-rules delete lab-allow-iap-ssh --quiet 2>/dev/null
gcloud storage rm -r "gs://$BUCKET" 2>/dev/null
bq rm -r -f -d "${PROJECT_ID}:${DATASET}" 2>/dev/null
gcloud logging metrics delete dlp_findings --quiet 2>/dev/null
for d in $(gcloud monitoring dashboards list --filter='displayName:"File Service"' --format='value(name)' 2>/dev/null); do
  gcloud monitoring dashboards delete "$d" --quiet
done
gcloud iam service-accounts delete "$RUN_SA" --quiet 2>/dev/null
gcloud iam service-accounts delete "$VM_SA" --quiet 2>/dev/null
gcloud artifacts repositories delete cloud-run-source-deploy --location="$REGION" --quiet 2>/dev/null
echo "Done. Delete by hand any dashboard you created with another name (Monitoring → Dashboards)."
