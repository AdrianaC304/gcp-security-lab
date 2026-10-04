#!/usr/bin/env bash
# SOLUTION — Activity 1 (Secret Manager + IAM). Use it only if you get stuck.
set -euo pipefail
source "$(dirname "$0")/../00-env.sh"

gcloud iam service-accounts create run-sa --display-name="file-service (Cloud Run)" || true

# The API key lives in Secret Manager, never in the code or the deploy command
gcloud secrets describe "$SECRET" >/dev/null 2>&1 || \
  openssl rand -hex 16 | tr -d '\n' | gcloud secrets create "$SECRET" --replication-policy=automatic --data-file=-

# run-sa may read THIS secret only
gcloud secrets add-iam-policy-binding "$SECRET" \
  --member="serviceAccount:$RUN_SA" --role="roles/secretmanager.secretAccessor"

gcloud run deploy "$SERVICE" --image="$IMAGE" --region="$REGION" \
  --service-account="$RUN_SA" --no-allow-unauthenticated \
  --set-env-vars="BUCKET_NAME=$BUCKET" --set-secrets="API_KEY=$SECRET:latest" --max-instances=3 --quiet
URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$RUN_SA" --role="roles/storage.objectViewer"

sleep 30
API_KEY=$(gcloud secrets versions access latest --secret="$SECRET")
curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" -H "X-API-Key: $API_KEY" "$URL/files"; echo

# Rotation: new version, then pin the service to it (env-var secrets are read when an instance starts)
openssl rand -hex 16 | tr -d '\n' | gcloud secrets versions add "$SECRET" --data-file=-
NEW=$(gcloud secrets versions list "$SECRET" --filter=state=enabled --sort-by=~createTime --limit=1 --format='value(name.basename())')
gcloud run services update "$SERVICE" --region="$REGION" --update-secrets="API_KEY=$SECRET:$NEW"
gcloud secrets versions disable 1 --secret="$SECRET"
