/**
 * Firestore composite indexes needed by application queries.
 *
 * Notes:
 * - These are NOT created by the apps at runtime.
 * - `firestore.indexes.json` is for Firebase/Firestore CLI deploy workflows, not Spring Boot startup.
 * - Index creation can take a few minutes after `terraform apply`.
 */

resource "google_firestore_index" "product_outbox_events_status_created_at" {
  project     = var.project_id
  database    = "(default)"
  collection  = "outbox_events"
  query_scope = "COLLECTION"

  fields {
    field_path = "status"
    order      = "ASCENDING"
  }

  fields {
    field_path = "createdAt"
    order      = "ASCENDING"
  }
}

