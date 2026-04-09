variable "enable_destroy_cleanup" {
  description = <<-EOT
    If true, on terraform destroy runs scripts/gke_lb_firewall_cleanup.sh to remove stuck k8s-fw-*
    firewall rules that can block VPC deletion after Kubernetes LoadBalancers / Gateway LBs are deleted.

    Before destroy: delete external Services / Gateways in the cluster and wait for GCP to drop forwarding rules.
  EOT
  type        = bool
  default     = true
}

resource "null_resource" "destroy_cleanup_k8s_lb_firewalls" {
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
    when    = destroy
    command = "bash -euo pipefail \"${path.module}/scripts/gke_lb_firewall_cleanup.sh\""
    environment = {
      PROJECT_ID   = self.triggers.project_id
      NETWORK_NAME = self.triggers.network_name
    }
  }
}
