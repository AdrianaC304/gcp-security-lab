#!/usr/bin/env bash
# SOLUTION — Activity 2 (Cloud KMS + IAM). Use it only if you get stuck.
set -euo pipefail
source "$(dirname "$0")/../00-env.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ME="user:$(gcloud config get-value account 2>/dev/null)"
KMS=(--key="$KEY" --keyring="$KEYRING" --location="$REGION")

gcloud kms keyrings create "$KEYRING" --location="$REGION" || true
gcloud kms keys create "$KEY" --keyring="$KEYRING" --location="$REGION" --purpose=encryption || true

# Two identities with opposite powers, and permission for you to act as them
for sa in ingest-sa auditor-sa; do
  gcloud iam service-accounts create "$sa" || true
  gcloud iam service-accounts add-iam-policy-binding "$sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --member="$ME" --role="roles/iam.serviceAccountTokenCreator"
done
gcloud kms keys add-iam-policy-binding "${KMS[@]}" --member="serviceAccount:$INGEST_SA"  --role="roles/cloudkms.cryptoKeyEncrypter"
gcloud kms keys add-iam-policy-binding "${KMS[@]}" --member="serviceAccount:$AUDITOR_SA" --role="roles/cloudkms.cryptoKeyDecrypter"
sleep 60

gcloud kms encrypt "${KMS[@]}" --plaintext-file="$ROOT/sample_data/customers.csv" \
  --ciphertext-file=/tmp/customers.csv.enc --impersonate-service-account="$INGEST_SA"
gcloud kms decrypt "${KMS[@]}" --ciphertext-file=/tmp/customers.csv.enc \
  --plaintext-file=/tmp/customers.decrypted.csv --impersonate-service-account="$AUDITOR_SA"
diff -q "$ROOT/sample_data/customers.csv" /tmp/customers.decrypted.csv && echo "Round trip OK"

# Rotation: new primary version; old ciphertext still decrypts
gcloud kms keys versions create "${KMS[@]}" --primary

# CMEK: the Cloud Storage service agent (not you, not run-sa) uses the key
GCS_SA=$(gcloud storage service-agent --project="$PROJECT_ID")
gcloud kms keys add-iam-policy-binding "${KMS[@]}" --member="serviceAccount:$GCS_SA" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
gcloud storage buckets update "gs://$BUCKET" --default-encryption-key="$KEY_NAME"
