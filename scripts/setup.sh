#!/usr/bin/env bash
# Setup (run once at the start, ~5 minutes).
# Prepares everything that is NOT part of the learning goals: APIs, bucket, sample data, app image.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "1/4 Enabling APIs (1–2 min)..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  storage.googleapis.com compute.googleapis.com secretmanager.googleapis.com cloudkms.googleapis.com \
  dlp.googleapis.com logging.googleapis.com monitoring.googleapis.com iam.googleapis.com

echo "2/4 Allowing Cloud Build to build the app..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/run.builder" --condition=None --quiet >/dev/null

echo "3/4 Creating the bucket with some files..."
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$BUCKET" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention
gcloud storage cp "$ROOT/sample_data/sales_by_city.csv" "gs://$BUCKET/reports/sales_by_city.csv"

echo "4/4 Building the app image (2–3 min)..."
gcloud artifacts repositories describe lab-images --location="$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create lab-images --repository-format=docker --location="$REGION"
gcloud builds submit "$ROOT/app" --tag="$IMAGE" --region="$REGION" --quiet

echo; echo "Setup done. You can start Activity 1."
