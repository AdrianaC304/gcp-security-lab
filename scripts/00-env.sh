#!/usr/bin/env bash
# Shared variables. Load them in every new Cloud Shell tab:   source scripts/00-env.sh

export PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)"
export REGION="europe-west1"
export ZONE="europe-west1-b"

export BUCKET="${PROJECT_ID}-lab-files"
export DATASET="lab_data"

export SERVICE="file-service"
export RUN_SA="run-sa@${PROJECT_ID}.iam.gserviceaccount.com"
export VM="bq-reader-vm"
export VM_SA="vm-sa@${PROJECT_ID}.iam.gserviceaccount.com"

export URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null)"

echo "Project: $PROJECT_ID | Region: $REGION | Bucket: gs://$BUCKET"
[ -n "$URL" ] && echo "Service: $URL"
true
