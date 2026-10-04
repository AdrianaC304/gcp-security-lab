#!/usr/bin/env bash
# SOLUTION — Activity 1 (IAM: Cloud Run reads Cloud Storage). Use it only if you get stuck.
set -euo pipefail
source "$(dirname "$0")/../00-env.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

gcloud iam service-accounts create run-sa --display-name="file-service (Cloud Run)" || true

gcloud run deploy "$SERVICE" --source="$ROOT/app" --region="$REGION" \
  --service-account="$RUN_SA" --no-allow-unauthenticated \
  --set-env-vars="BUCKET_NAME=$BUCKET" --max-instances=3 --quiet
URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$RUN_SA" --role="roles/storage.objectViewer"

sleep 30
curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$URL/files"; echo
