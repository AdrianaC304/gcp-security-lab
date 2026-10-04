#!/usr/bin/env bash
# Shared variables. Load them in every new Cloud Shell tab:   source scripts/00-env.sh

export PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)"
export REGION="europe-west1"

export BUCKET="${PROJECT_ID}-lab-files"

# Activity 1 — Cloud Run + Secret Manager
export SERVICE="file-service"
export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/lab-images/file-service"
export RUN_SA="run-sa@${PROJECT_ID}.iam.gserviceaccount.com"
export SECRET="file-service-api-key"

# Activity 2 — Cloud KMS
export KEYRING="lab-keyring"
export KEY="files-key"
export KEY_NAME="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING}/cryptoKeys/${KEY}"
export INGEST_SA="ingest-sa@${PROJECT_ID}.iam.gserviceaccount.com"
export AUDITOR_SA="auditor-sa@${PROJECT_ID}.iam.gserviceaccount.com"

export URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null)"
export API_KEY="$(gcloud secrets versions access latest --secret="$SECRET" 2>/dev/null)"

echo "Project: $PROJECT_ID | Region: $REGION | Bucket: gs://$BUCKET"
[ -n "$URL" ] && echo "Service: $URL"
[ -n "$API_KEY" ] && echo "API key: loaded from Secret Manager (\$API_KEY)"
true
