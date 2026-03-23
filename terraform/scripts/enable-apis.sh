#!/usr/bin/env bash
# Enable all APIs this Terraform stack needs. Run ONCE per project as a user or SA with
# permission to enable services (e.g. Project Owner or roles/serviceusage.serviceUsageAdmin).
#
#   ./scripts/enable-apis.sh YOUR_PROJECT_ID
#   # or
#   gcloud config set project YOUR_PROJECT_ID && ./scripts/enable-apis.sh
#
# Why not only Terraform? google_project_service requires the same Service Usage permissions;
# many CI / workload identities cannot list or enable APIs. This script uses your gcloud user.

set -euo pipefail

PROJECT_ID="${1:-}"
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "Usage: $0 <PROJECT_ID>"
  echo "   or: gcloud config set project <PROJECT_ID> && $0"
  exit 1
fi

# Keep in sync with former terraform/apis.tf list.
SERVICES=(
  serviceusage.googleapis.com
  container.googleapis.com
  compute.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  logging.googleapis.com
  monitoring.googleapis.com
  artifactregistry.googleapis.com
  firestore.googleapis.com
  pubsub.googleapis.com
  apigateway.googleapis.com
  servicemanagement.googleapis.com
  servicecontrol.googleapis.com
  dns.googleapis.com
)

echo "Enabling ${#SERVICES[@]} APIs on project ${PROJECT_ID} (may take a few minutes)..."
gcloud services enable "${SERVICES[@]}" --project="${PROJECT_ID}"
echo "Done. Wait 1–2 minutes if the next terraform apply still errors, then retry."
