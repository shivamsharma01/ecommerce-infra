#!/usr/bin/env bash
# Create the default Firestore (Native) database for a GCP project if it does not exist, and
# optionally grant IAM so the catalog bootstrap identity can write Firestore + GCS objects.
#
# Prerequisites:
#   - gcloud installed; caller must have permission to create Firestore and to set IAM (e.g. Owner,
#     roles/resourcemanager.projectIamAdmin + Firestore admin, or security admin).
#
# Bootstrap principal resolution (first match wins):
#   1. CATALOG_BOOTSTRAP_MEMBER — full member, e.g. serviceAccount:svc@proj.iam.gserviceaccount.com
#   2. CATALOG_BOOTSTRAP_SA_EMAIL — service account email only (script prefixes serviceAccount:)
#   3. GOOGLE_APPLICATION_CREDENTIALS — JSON key file; uses client_email as serviceAccount:
#   4. gcloud config get-value account — grants user:your@email
#
# Set SKIP_CATALOG_IAM=true to only create/verify Firestore and skip IAM bindings.
#
# Usage (from deploy/):
#   cp catalog/bootstrap.env.example catalog/bootstrap.env   # PROJECT_ID, BUCKET, optional vars
#   chmod +x scripts/create_firestore_database.sh
#   ./scripts/create_firestore_database.sh
#
# Or one-off:
#   PROJECT_ID=ecommerce-491019 FIRESTORE_LOCATION=asia-south2 \
#   CATALOG_BOOTSTRAP_SA_EMAIL=my-sa@ecommerce-491019.iam.gserviceaccount.com \
#   ./scripts/create_firestore_database.sh
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

# Firestore region (lowercase multi-region or single region).
LOC_RAW="${FIRESTORE_LOCATION:-${BUCKET_LOCATION:-asia-south2}}"
FIRESTORE_LOCATION="${LOC_RAW,,}"

SKIP_IAM="${SKIP_CATALOG_IAM:-false}"
if [[ "${SKIP_IAM,,}" =~ ^(1|true|yes)$ ]]; then
  SKIP_IAM=true
else
  SKIP_IAM=false
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Install Google Cloud SDK."
  exit 1
fi

echo "Project: $PROJECT_ID"
echo "Firestore location: $FIRESTORE_LOCATION (Native mode, database '(default)')"

echo "Ensuring firestore.googleapis.com is enabled..."
gcloud services enable firestore.googleapis.com --project="$PROJECT_ID" --quiet

if gcloud firestore databases describe --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firestore default database already exists for project $PROJECT_ID."
  gcloud firestore databases describe --project="$PROJECT_ID" --format='table(name,type,locationId,uid)' || true
else
  echo "Creating Firestore Native database (default) — one-time per project..."
  gcloud firestore databases create \
    --project="$PROJECT_ID" \
    --location="$FIRESTORE_LOCATION" \
    --type=firestore-native \
    --quiet
  echo "Firestore database created."
fi

# --- IAM for upload_catalog.sh (ADC / SA key user) ---
if [[ "$SKIP_IAM" == true ]]; then
  echo "SKIP_CATALOG_IAM=true — skipping IAM bindings."
  exit 0
fi

resolve_bootstrap_member() {
  if [[ -n "${CATALOG_BOOTSTRAP_MEMBER:-}" ]]; then
    echo "${CATALOG_BOOTSTRAP_MEMBER}"
    return 0
  fi
  if [[ -n "${CATALOG_BOOTSTRAP_SA_EMAIL:-}" ]]; then
    echo "serviceAccount:${CATALOG_BOOTSTRAP_SA_EMAIL}"
    return 0
  fi
  if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    local email
    if email=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['client_email'])" "${GOOGLE_APPLICATION_CREDENTIALS}" 2>/dev/null); then
      if [[ -n "$email" ]]; then
        echo "serviceAccount:${email}"
        return 0
      fi
    fi
  fi
  local acct
  acct=$(gcloud config get-value account 2>/dev/null || true)
  if [[ -n "$acct" && "$acct" != "(unset)" ]]; then
    echo "user:${acct}"
    return 0
  fi
  return 1
}

MEMBER=""
if ! MEMBER=$(resolve_bootstrap_member); then
  echo ""
  echo "Could not resolve a bootstrap principal for IAM. Set one of:"
  echo "  CATALOG_BOOTSTRAP_MEMBER=serviceAccount:... or user:..."
  echo "  CATALOG_BOOTSTRAP_SA_EMAIL=...@....iam.gserviceaccount.com"
  echo "  GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json"
  echo "Or run gcloud auth login and use your user account."
  echo "To skip IAM: SKIP_CATALOG_IAM=true ./scripts/create_firestore_database.sh"
  exit 1
fi

echo ""
echo "Granting catalog bootstrap IAM to: $MEMBER"

echo "  • roles/datastore.user on project $PROJECT_ID (Firestore read/write)..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="$MEMBER" \
  --role="roles/datastore.user" \
  --condition=None \
  --quiet

BUCKET_NAME="${BUCKET:-}"
BUCKET_PROJECT="${BUCKET_PROJECT:-$PROJECT_ID}"
if [[ -n "$BUCKET_NAME" ]]; then
  echo "Ensuring storage.googleapis.com is enabled..."
  gcloud services enable storage.googleapis.com --project="$BUCKET_PROJECT" --quiet

  gs_uri="gs://${BUCKET_NAME}"
  if gcloud storage buckets describe "$gs_uri" --project="$BUCKET_PROJECT" >/dev/null 2>&1; then
    echo "  • roles/storage.objectAdmin on $gs_uri (create/overwrite/delete objects)..."
    gcloud storage buckets add-iam-policy-binding "$gs_uri" \
      --project="$BUCKET_PROJECT" \
      --member="$MEMBER" \
      --role="roles/storage.objectAdmin" \
      --quiet
  else
    echo "  • Bucket $gs_uri not found (project $BUCKET_PROJECT) — skipping storage IAM."
    echo "    Create it with ./scripts/create_catalog_bucket.sh or set BUCKET_PROJECT if the bucket lives in another project."
  fi
else
  echo "  • BUCKET not set in bootstrap.env — skipping GCS IAM. Set BUCKET and re-run to grant storage access."
fi

echo ""
echo "Done. If upload_catalog.sh still gets 403, confirm the same identity is used (see bootstrap_catalog.py credential hint)."
echo ""
