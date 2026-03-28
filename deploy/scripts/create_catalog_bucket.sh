#!/usr/bin/env bash
# Create a GCS bucket for catalog images and optionally allow public read (browser/UI).
#
# Product service write access for uploads is granted by Terraform when you set
# workload_service_accounts.product to your product GCP service account.
#
# Usage (from deploy/):
#   cp catalog/bootstrap.env.example catalog/bootstrap.env   # edit PROJECT_ID, BUCKET, BUCKET_LOCATION
#   ./scripts/create_catalog_bucket.sh
#
# Or one-off:
#   PROJECT_ID=my-proj BUCKET=my-bucket BUCKET_LOCATION=ASIA-SOUTH2 ./scripts/create_catalog_bucket.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${DEPLOY_DIR}/catalog/bootstrap.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${PROJECT_ID:?Set PROJECT_ID (e.g. in catalog/bootstrap.env)}"
: "${BUCKET:?Set BUCKET (bucket name only, no gs://)}"
: "${BUCKET_LOCATION:?Set BUCKET_LOCATION (e.g. ASIA-SOUTH2)}"

PUBLIC_READ="${CATALOG_BUCKET_PUBLIC_READ:-false}"
if [[ "${PUBLIC_READ,,}" =~ ^(1|true|yes)$ ]]; then
  PUBLIC_READ=true
else
  PUBLIC_READ=false
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Install Google Cloud SDK."
  exit 1
fi

gs_uri="gs://${BUCKET}"

if gcloud storage buckets describe "$gs_uri" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Bucket already exists: $gs_uri"
else
  echo "Creating bucket $gs_uri (location=$BUCKET_LOCATION)..."
  gcloud storage buckets create "$gs_uri" \
    --project="$PROJECT_ID" \
    --location="$BUCKET_LOCATION" \
    --uniform-bucket-level-access
fi

if [[ "$PUBLIC_READ" == true ]]; then
  echo "Granting public object read (allUsers -> roles/storage.objectViewer)..."
  gcloud storage buckets add-iam-policy-binding "$gs_uri" \
    --project="$PROJECT_ID" \
    --member="allUsers" \
    --role="roles/storage.objectViewer"
else
  echo "Skipping public read (set CATALOG_BUCKET_PUBLIC_READ=true in bootstrap.env to enable)."
fi

echo "Done. Next: terraform apply (IAM for product SA) then ./scripts/upload_catalog.sh"
