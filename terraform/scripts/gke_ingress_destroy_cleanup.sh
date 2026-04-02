#!/usr/bin/env bash
# Removes GKE GCE Ingress (L7) leftovers in GCP: k8s-fw-l7--* firewalls, NEGs, and related
# global load balancer resources. These are created by the in-cluster controller, not Terraform,
# and can block VPC deletion.
#
# Pre-destroy (recommended): delete Kubernetes Ingresses or namespaces and wait until external
# HTTP(S) load balancers disappear in GCP before running terraform destroy.
#
# Recovery when terraform destroy fails on the VPC with k8s-fw-l7--* still attached, or the
# null_resource cleanup already left state:
#   export PROJECT_ID="your-gcp-project"
#   export NETWORK_NAME="your-vpc-name"   # same as var.network_name
#   bash ecomm-infra/terraform/scripts/gke_ingress_destroy_cleanup.sh
#   cd ecomm-infra/terraform && terraform destroy
#
# Requires: gcloud authenticated with permission to delete these resources.

set -euo pipefail

if [[ -z "${PROJECT_ID:-}" || -z "${NETWORK_NAME:-}" ]]; then
  echo "destroy-cleanup: missing PROJECT_ID or NETWORK_NAME; skipping"
  exit 0
fi

echo "destroy-cleanup: removing GCE Ingress firewall rules on network=${NETWORK_NAME}"

# List by name prefix only (reliable); filter to this VPC in shell — avoids gcloud network filter quirks.
while IFS=$'\t' read -r rule_name network_url; do
  [[ -z "${rule_name:-}" ]] && continue
  [[ "${network_url}" == *"/networks/${NETWORK_NAME}" ]] || continue
  echo "destroy-cleanup: deleting firewall rule ${rule_name}"
  gcloud compute firewall-rules delete "${rule_name}" --project "${PROJECT_ID}" --quiet
done < <(gcloud compute firewall-rules list \
  --project "${PROJECT_ID}" \
  --filter='name~^k8s-fw-l7--' \
  --format='value(name,network)')

echo "destroy-cleanup: finished k8s-fw-l7-- firewall cleanup for VPC ${NETWORK_NAME}"

echo "destroy-cleanup: removing GCE Ingress NEGs (this can take a while)"
neg_seen=
while IFS=$'\t' read -r neg zone_url; do
  [[ -z "${neg:-}" ]] && continue
  neg_seen=1
  zone="${zone_url##*/}"
  echo "destroy-cleanup: deleting NEG ${neg} in zone ${zone}"
  gcloud compute network-endpoint-groups delete "${neg}" \
    --zone "${zone}" \
    --project "${PROJECT_ID}" \
    --quiet || true
done < <(gcloud compute network-endpoint-groups list \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name,zone)" 2>/dev/null || true)
[[ -n "${neg_seen}" ]] || echo "destroy-cleanup: no k8s* NEGs found"

echo "destroy-cleanup: removing GCE Ingress backend services + related resources"

readarray -t _bs < <(gcloud compute backend-services list \
  --global \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)
if ((${#_bs[@]} == 0)); then
  echo "destroy-cleanup: no backend services found"
fi

while IFS= read -r map_name; do
  [[ -z "${map_name:-}" ]] && continue
  echo "destroy-cleanup: deleting url-map ${map_name}"
  gcloud compute url-maps delete "${map_name}" --project "${PROJECT_ID}" --quiet || true
done < <(gcloud compute url-maps list \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)

while IFS= read -r p; do
  [[ -z "${p:-}" ]] && continue
  echo "destroy-cleanup: deleting target-http-proxy ${p}"
  gcloud compute target-http-proxies delete "${p}" --project "${PROJECT_ID}" --quiet || true
done < <(gcloud compute target-http-proxies list \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)

while IFS= read -r p; do
  [[ -z "${p:-}" ]] && continue
  echo "destroy-cleanup: deleting target-https-proxy ${p}"
  gcloud compute target-https-proxies delete "${p}" --project "${PROJECT_ID}" --quiet || true
done < <(gcloud compute target-https-proxies list \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)

while IFS= read -r r; do
  [[ -z "${r:-}" ]] && continue
  echo "destroy-cleanup: deleting forwarding-rule ${r}"
  gcloud compute forwarding-rules delete "${r}" --global --project "${PROJECT_ID}" --quiet || true
done < <(gcloud compute forwarding-rules list \
  --global \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)

while IFS= read -r svc; do
  [[ -z "${svc:-}" ]] && continue
  echo "destroy-cleanup: deleting backend-service ${svc}"
  gcloud compute backend-services delete "${svc}" --global --project "${PROJECT_ID}" --quiet || true
done < <(gcloud compute backend-services list \
  --global \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)

while IFS= read -r h; do
  [[ -z "${h:-}" ]] && continue
  echo "destroy-cleanup: deleting health-check ${h}"
  gcloud compute health-checks delete "${h}" --global --project "${PROJECT_ID}" --quiet || true
done < <(gcloud compute health-checks list \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" 2>/dev/null || true)

echo "destroy-cleanup: retrying NEG deletions after backend cleanup"
while IFS=$'\t' read -r neg zone_url; do
  [[ -z "${neg:-}" ]] && continue
  zone="${zone_url##*/}"
  echo "destroy-cleanup: deleting NEG ${neg} in zone ${zone}"
  gcloud compute network-endpoint-groups delete "${neg}" \
    --zone "${zone}" \
    --project "${PROJECT_ID}" \
    --quiet || true
done < <(gcloud compute network-endpoint-groups list \
  --project "${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name,zone)" 2>/dev/null || true)

echo "destroy-cleanup: done"
