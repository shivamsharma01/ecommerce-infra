#!/usr/bin/env bash
# Tear down Terraform-managed infra but keep Firestore composite indexes in GCP.
#
# Indexes have lifecycle.prevent_destroy; this script removes them from state first so
# "terraform destroy" completes without trying to delete them (avoids long index rebuilds
# on the next apply).
#
# Usage (from terraform/):
#   ./scripts/destroy-preserve-firestore-indexes.sh
#   ./scripts/destroy-preserve-firestore-indexes.sh -auto-approve
#
# Before running: delete GKE workloads / gateway namespaces and wait for LBs to drain.
# See README.md "Teardown" and deploy/k8s/gateway/README.md.
#
# After destroy + later "terraform apply": if apply wants to create indexes that still exist,
# import them (IDs from Firestore console → Indexes):
#   terraform import google_firestore_index.cart_items_user_updated_at \
#     'projects/PROJECT/databases/(default)/collectionGroups/cart_items/indexes/INDEX_ID'
#   terraform import google_firestore_index.product_outbox_events_status_created_at \
#     'projects/PROJECT/databases/(default)/collectionGroups/outbox_events/indexes/INDEX_ID'
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

INDEXES=(
  'google_firestore_index.cart_items_user_updated_at'
  'google_firestore_index.product_outbox_events_status_created_at'
)

for addr in "${INDEXES[@]}"; do
  if terraform state show "$addr" &>/dev/null; then
    echo "Removing from state (index stays in GCP): $addr"
    terraform state rm "$addr"
  else
    echo "Not in state (skip): $addr"
  fi
done

echo "Running terraform destroy..."
terraform destroy "$@"
