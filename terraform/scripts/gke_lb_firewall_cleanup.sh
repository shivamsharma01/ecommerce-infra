#!/usr/bin/env bash
# Best-effort: delete GKE-created k8s-fw-* firewall rules that can remain after LoadBalancer /
# Gateway teardown and block VPC deletion. Invoked from terraform destroy (destroy_cleanup.tf).
#
# Before destroy: remove Kubernetes Services / Gateways that own external LBs; wait until
# forwarding rules disappear in GCP (often several minutes).
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID is required}"
: "${NETWORK_NAME:?NETWORK_NAME is required}"

echo "gke_lb_firewall_cleanup: project=${PROJECT_ID} network=${NETWORK_NAME}"

while IFS= read -r rule; do
  [[ -z "${rule}" ]] && continue
  echo "Deleting firewall rule: ${rule}"
  gcloud compute firewall-rules delete "${rule}" \
    --project="${PROJECT_ID}" \
    --quiet
done < <(gcloud compute firewall-rules list \
  --project="${PROJECT_ID}" \
  --filter="network~${NETWORK_NAME} AND name~^k8s-fw-" \
  --format="value(name)" 2>/dev/null || true)

echo "gke_lb_firewall_cleanup: done."
