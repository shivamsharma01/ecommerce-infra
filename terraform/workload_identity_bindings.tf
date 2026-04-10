locals {
  workload_pool = "${var.project_id}.svc.id.goog"
  workload_ns   = "mcart"
}

# Allow Kubernetes service accounts to impersonate the corresponding GCP service accounts.
# Required for Workload Identity (without this, pods get PERMISSION_DENIED to GCP APIs).

resource "google_service_account_iam_member" "wi_auth" {
  count = local.auth_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.auth_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/auth]"
}

resource "google_service_account_iam_member" "wi_user" {
  count = local.user_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.user_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/user]"
}

resource "google_service_account_iam_member" "wi_product" {
  count = local.product_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.product_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/product]"
}

resource "google_service_account_iam_member" "wi_product_indexer" {
  count = local.product_indexer_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.product_indexer_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/product-indexer]"
}

resource "google_service_account_iam_member" "wi_email" {
  count = local.email_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.email_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/email]"
}

resource "google_service_account_iam_member" "wi_inventory" {
  count = local.inventory_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.inventory_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/inventory]"
}

resource "google_service_account_iam_member" "wi_order" {
  count = local.order_sa != "" && var.enable_workload_identity ? 1 : 0

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.order_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${local.workload_ns}/order]"
}

