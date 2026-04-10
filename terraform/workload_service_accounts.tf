# Microservice GCP service accounts (Workload Identity principals). IAM bindings in
# iam_workloads.tf reference these emails; without this resource block, bindings fail with
# "Service account ... does not exist".

resource "google_service_account" "workload_auth" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-auth"
  display_name = "MCart auth service (Pub/Sub user-signup publisher)"
}

resource "google_service_account" "workload_user" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-user"
  display_name = "MCart user service (Pub/Sub user-signup subscriber)"
}

resource "google_service_account" "workload_product" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-product"
  display_name = "MCart product service (Pub/Sub + Firestore + catalog bucket)"
}

resource "google_service_account" "workload_product_indexer" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-product-indexer"
  display_name = "MCart product-indexer (Pub/Sub + OpenSearch pipeline)"
}

resource "google_service_account" "workload_email" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-email"
  display_name = "MCart email service (Pub/Sub verification-email subscriber + SMTP)"
}

resource "google_service_account" "workload_inventory" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-inventory"
  display_name = "MCart inventory (Pub/Sub product-events subscriber)"
}

resource "google_service_account" "workload_order" {
  count = var.create_workload_service_accounts ? 1 : 0

  project      = var.project_id
  account_id   = "mcart-order"
  display_name = "MCart order service (Pub/Sub order-paid publisher)"
}
