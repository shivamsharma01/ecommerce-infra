variable "enable_destroy_cleanup" {
  description = <<-EOT
    If true, on terraform destroy Terraform runs scripts/gke_ingress_destroy_cleanup.sh to remove
    GKE/Ingress-managed firewall rules and related LB resources that can block VPC deletion.

    Before terraform destroy, delete Kubernetes Ingress resources (or whole namespaces) and wait until
    external HTTP(S) load balancers finish tearing down in GCP so controllers remove as much as possible first.
  EOT
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
    when    = destroy
    command = "bash -euo pipefail \"${path.module}/scripts/gke_ingress_destroy_cleanup.sh\""
    environment = {
      PROJECT_ID   = self.triggers.project_id
      NETWORK_NAME = self.triggers.network_name
    }
  }
}
