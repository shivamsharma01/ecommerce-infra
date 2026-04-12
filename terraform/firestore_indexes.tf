/**
 * Firestore composite indexes needed by application queries.
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

