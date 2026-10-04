#!/usr/bin/env bash
# Deletes everything created in the lab. Safe to run more than once.
set -uo pipefail
source "$(dirname "$0")/00-env.sh"

gcloud run services delete "$SERVICE" --region="$REGION" --quiet 2>/dev/null
gcloud storage rm -r "gs://$BUCKET" 2>/dev/null
gcloud secrets delete "$SECRET" --quiet 2>/dev/null
gcloud logging metrics delete dlp_findings --quiet 2>/dev/null
for d in $(gcloud monitoring dashboards list --filter='displayName:"File Service"' --format='value(name)' 2>/dev/null); do
  gcloud monitoring dashboards delete "$d" --quiet
done
for sa in "$RUN_SA" "$INGEST_SA" "$AUDITOR_SA"; do
  gcloud iam service-accounts delete "$sa" --quiet 2>/dev/null
done
gcloud artifacts repositories delete lab-images --location="$REGION" --quiet 2>/dev/null

# KMS keys and key rings cannot be deleted: destroy every key version so it stops costing money.
for v in $(gcloud kms keys versions list --key="$KEY" --keyring="$KEYRING" --location="$REGION" \
             --filter='state=ENABLED OR state=DISABLED' --format='value(name.basename())' 2>/dev/null); do
  gcloud kms keys versions destroy "$v" --key="$KEY" --keyring="$KEYRING" --location="$REGION" --quiet
done
echo "Done. Delete by hand any dashboard you created with another name (Monitoring → Dashboards)."
