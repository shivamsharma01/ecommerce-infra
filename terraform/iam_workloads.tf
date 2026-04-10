locals {
  wsa = var.workload_service_accounts

  # When Terraform manages the SAs, bind IAM to the created emails; else use explicit tfvars emails.
  auth_sa = var.create_workload_service_accounts ? google_service_account.workload_auth[0].email : (
    local.wsa.auth == null ? "" : trimspace(local.wsa.auth)
  )
  user_sa = var.create_workload_service_accounts ? google_service_account.workload_user[0].email : (
    local.wsa.user == null ? "" : trimspace(local.wsa.user)
  )
  product_sa = var.create_workload_service_accounts ? google_service_account.workload_product[0].email : (
    local.wsa.product == null ? "" : trimspace(local.wsa.product)
  )
  product_indexer_sa = var.create_workload_service_accounts ? google_service_account.workload_product_indexer[0].email : (
    local.wsa.product_indexer == null ? "" : trimspace(local.wsa.product_indexer)
  )
  email_sa = var.create_workload_service_accounts ? google_service_account.workload_email[0].email : (
    local.wsa.email == null ? "" : trimspace(local.wsa.email)
  )

  extra_iam_bindings = flatten([
    for role, members in var.extra_project_iam_members : [
      for m in members : { role = role, member = m }
    ]
  ])
}

resource "google_pubsub_topic_iam_member" "auth_user_signup_publisher" {
  count = local.auth_sa != "" ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.user_signup_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.auth_sa}"
}

resource "google_pubsub_topic_iam_member" "auth_email_verification_publisher" {
  count = local.auth_sa != "" ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.email_verification_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.auth_sa}"
}

resource "google_pubsub_subscription_iam_member" "user_signup_subscriber" {
  count = local.user_sa != "" ? 1 : 0

  project      = var.project_id
  subscription = google_pubsub_subscription.user_signup_events_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.user_sa}"
}

resource "google_pubsub_subscription_iam_member" "email_verification_subscriber" {
  count = local.email_sa != "" ? 1 : 0

  project      = var.project_id
  subscription = google_pubsub_subscription.email_verification_events_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.email_sa}"
}

resource "google_pubsub_topic_iam_member" "product_events_publisher" {
  count = local.product_sa != "" ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.product_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.product_sa}"
}

resource "google_pubsub_subscription_iam_member" "product_events_indexer_subscriber" {
  count = local.product_indexer_sa != "" ? 1 : 0

  project      = var.project_id
  subscription = google_pubsub_subscription.product_events_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.product_indexer_sa}"
}

resource "google_pubsub_subscription_iam_member" "product_pubsub_health_subscriber" {
  count = var.enable_product_pubsub_health_resources && local.product_sa != "" ? 1 : 0

  project      = var.project_id
  subscription = google_pubsub_subscription.product_pubsub_health[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.product_sa}"
}

resource "google_project_iam_member" "product_firestore_user" {
  count = local.product_sa != "" ? 1 : 0

  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${local.product_sa}"
}

resource "google_storage_bucket_iam_member" "product_catalog_object_admin" {
  count = local.product_sa != "" ? 1 : 0

  bucket = data.google_storage_bucket.catalog_images.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.product_sa}"
}

resource "google_project_iam_member" "product_indexer_firestore_user" {
  count = local.product_indexer_sa != "" ? 1 : 0

  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${local.product_indexer_sa}"
}

resource "google_project_iam_member" "extra" {
  for_each = {
    for b in local.extra_iam_bindings : "${b.role} ${b.member}" => b
  }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
