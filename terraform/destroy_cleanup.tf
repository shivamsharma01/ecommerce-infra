variable "enable_destroy_cleanup" {
  description = "If true, Terraform will attempt to delete GKE/Ingress-managed firewall rules that can block VPC deletion during terraform destroy."
  type        = bool
  default     = true
}

resource "null_resource" "destroy_cleanup_gce_ingress_firewalls" {
  count = var.enable_destroy_cleanup ? 1 : 0

  # Use only variables to avoid dependency cycles.
  triggers = {
    project_id   = var.project_id
    network_name = var.network_name
  }

  # Ensure this resource is destroyed (and runs its destroy provisioner)
  # before the VPC network is destroyed.
  depends_on = [
    google_compute_network.main,
  ]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-ceu"]
    environment = {
      PROJECT_ID   = self.triggers.project_id
      NETWORK_NAME = self.triggers.network_name
    }
    command = <<-BASH

if [[ -z "$${PROJECT_ID}" || -z "$${NETWORK_NAME}" ]]; then
  echo "destroy-cleanup: missing PROJECT_ID/NETWORK_NAME; skipping"
  exit 0
fi

echo "destroy-cleanup: removing GCE Ingress firewall rules on network=$${NETWORK_NAME}"

NETWORK="projects/$${PROJECT_ID}/global/networks/$${NETWORK_NAME}"

RULES=$(gcloud compute firewall-rules list \
  --project "$${PROJECT_ID}" \
  --filter="network:$${NETWORK} AND name~'^k8s-fw-l7--'" \
  --format="value(name)" || true)

if [[ -z "$${RULES}" ]]; then
  echo "destroy-cleanup: no k8s-fw-l7-- firewall rules found"
else
  echo "$${RULES}" | while read -r RULE; do
    [[ -z "$${RULE}" ]] && continue
    echo "destroy-cleanup: deleting firewall rule $${RULE}"
    gcloud compute firewall-rules delete "$${RULE}" --project "$${PROJECT_ID}" --quiet || true
  done
fi

echo "destroy-cleanup: removing GCE Ingress NEGs (this can take a while)"
NEGS=$(gcloud compute network-endpoint-groups list \
  --project "$${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name,zone)" || true)

if [[ -n "$${NEGS}" ]]; then
  echo "$${NEGS}" | while read -r NEG ZONE_URL; do
    [[ -z "$${NEG}" ]] && continue
    ZONE="$${ZONE_URL##*/}"
    echo "destroy-cleanup: deleting NEG $${NEG} in zone $${ZONE}"
    gcloud compute network-endpoint-groups delete "$${NEG}" \
      --zone "$${ZONE}" \
      --project "$${PROJECT_ID}" \
      --quiet || true
  done
else
  echo "destroy-cleanup: no k8s* NEGs found"
fi

echo "destroy-cleanup: removing GCE Ingress backend services + related resources"

BS=$(gcloud compute backend-services list \
  --global \
  --project "$${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name)" || true)

if [[ -n "$${BS}" ]]; then
  # Detach backend services from URL maps by deleting URL maps and proxies first.
  UM=$(gcloud compute url-maps list \
    --project "$${PROJECT_ID}" \
    --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
    --format="value(name)" || true)
  if [[ -n "$${UM}" ]]; then
    echo "$${UM}" | while read -r MAP; do
      [[ -z "$${MAP}" ]] && continue
      echo "destroy-cleanup: deleting url-map $${MAP}"
      gcloud compute url-maps delete "$${MAP}" --project "$${PROJECT_ID}" --quiet || true
    done
  fi

  TP=$(gcloud compute target-http-proxies list \
    --project "$${PROJECT_ID}" \
    --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
    --format="value(name)" || true)
  if [[ -n "$${TP}" ]]; then
    echo "$${TP}" | while read -r P; do
      [[ -z "$${P}" ]] && continue
      echo "destroy-cleanup: deleting target-http-proxy $${P}"
      gcloud compute target-http-proxies delete "$${P}" --project "$${PROJECT_ID}" --quiet || true
    done
  fi

  TSP=$(gcloud compute target-https-proxies list \
    --project "$${PROJECT_ID}" \
    --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
    --format="value(name)" || true)
  if [[ -n "$${TSP}" ]]; then
    echo "$${TSP}" | while read -r P; do
      [[ -z "$${P}" ]] && continue
      echo "destroy-cleanup: deleting target-https-proxy $${P}"
      gcloud compute target-https-proxies delete "$${P}" --project "$${PROJECT_ID}" --quiet || true
    done
  fi

  FR=$(gcloud compute forwarding-rules list \
    --global \
    --project "$${PROJECT_ID}" \
    --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
    --format="value(name)" || true)
  if [[ -n "$${FR}" ]]; then
    echo "$${FR}" | while read -r R; do
      [[ -z "$${R}" ]] && continue
      echo "destroy-cleanup: deleting forwarding-rule $${R}"
      gcloud compute forwarding-rules delete "$${R}" --global --project "$${PROJECT_ID}" --quiet || true
    done
  fi

  echo "$${BS}" | while read -r SVC; do
    [[ -z "$${SVC}" ]] && continue
    echo "destroy-cleanup: deleting backend-service $${SVC}"
    gcloud compute backend-services delete "$${SVC}" --global --project "$${PROJECT_ID}" --quiet || true
  done

  # Health checks are referenced by backend services; remove dangling ones.
  HC=$(gcloud compute health-checks list \
    --project "$${PROJECT_ID}" \
    --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
    --format="value(name)" || true)
  if [[ -n "$${HC}" ]]; then
    echo "$${HC}" | while read -r H; do
      [[ -z "$${H}" ]] && continue
      echo "destroy-cleanup: deleting health-check $${H}"
      gcloud compute health-checks delete "$${H}" --global --project "$${PROJECT_ID}" --quiet || true
    done
  fi
else
  echo "destroy-cleanup: no backend services found"
fi

echo "destroy-cleanup: retrying NEG deletions after backend cleanup"
NEGS2=$(gcloud compute network-endpoint-groups list \
  --project "$${PROJECT_ID}" \
  --filter="name~'^k8s[0-9]+-.*(mcart|kube-system-default-http-backend)'" \
  --format="value(name,zone)" || true)
if [[ -n "$${NEGS2}" ]]; then
  echo "$${NEGS2}" | while read -r NEG ZONE_URL; do
    [[ -z "$${NEG}" ]] && continue
    ZONE="$${ZONE_URL##*/}"
    echo "destroy-cleanup: deleting NEG $${NEG} in zone $${ZONE}"
    gcloud compute network-endpoint-groups delete "$${NEG}" \
      --zone "$${ZONE}" \
      --project "$${PROJECT_ID}" \
      --quiet || true
  done
fi

echo "destroy-cleanup: done"
BASH
  }
}

