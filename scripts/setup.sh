#!/usr/bin/env bash
# Setup (run once at the start, ~3 minutes).
# Prepares everything that is NOT part of the learning goals: APIs, bucket, sample data, BigQuery table.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "1/5 Enabling APIs (1–2 min)..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  storage.googleapis.com compute.googleapis.com bigquery.googleapis.com iap.googleapis.com \
  dlp.googleapis.com logging.googleapis.com monitoring.googleapis.com iam.googleapis.com

echo "2/5 Allowing Cloud Build to deploy from source..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/run.builder" --condition=None --quiet >/dev/null

echo "3/5 Creating the bucket with some files..."
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$BUCKET" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention
gcloud storage cp "$ROOT/sample_data/sales_by_city.csv" "gs://$BUCKET/reports/sales_by_city.csv"

echo "4/5 Creating the BigQuery table $DATASET.customers..."
bq --location="$REGION" show "$DATASET" >/dev/null 2>&1 || bq --location="$REGION" mk -d "$DATASET"
bq --location="$REGION" load --replace --autodetect --source_format=CSV \
  "$DATASET.customers" "$ROOT/sample_data/customers.csv"

echo "5/5 Checking the network for the VM..."
if ! gcloud compute networks describe default >/dev/null 2>&1; then
  gcloud compute networks create default --subnet-mode=auto
fi
gcloud compute firewall-rules describe lab-allow-iap-ssh >/dev/null 2>&1 || \
  gcloud compute firewall-rules create lab-allow-iap-ssh --network=default \
    --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges=35.235.240.0/20

echo; echo "Setup done. You can start Activity 1."
