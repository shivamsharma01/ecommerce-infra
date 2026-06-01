# Cart service Firestore: composite index, infra bootstrap document, destroy-time data cleanup.

variable "enable_cart_firestore_destroy_cleanup" {
  description = <<-EOT
    If true, on terraform destroy runs scripts/cart_firestore_destroy_cleanup.py to delete all documents
    in the cart_items collection. Requires Python 3 and google-cloud-firestore on the machine running destroy.
    Uses Application Default Credentials (same identity as terraform).
  EOT
  type        = bool
  default     = true
}

resource "google_firestore_index" "cart_items_user_updated_at" {
  project     = var.project_id
  database    = "(default)"
  collection  = "cart_items"
  query_scope = "COLLECTION"

  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }

  fields {
    field_path = "updatedAt"
    order      = "DESCENDING"
  }

  # Kept across infra teardown; use scripts/destroy-preserve-firestore-indexes.sh before destroy.
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_firestore_document" "cart_bootstrap" {
  project     = var.project_id
  database    = "(default)"
  collection  = "mcart_infra"
  document_id = "cart_bootstrap"

  fields = jsonencode({
    purpose = {
      stringValue = "mcart-cart-infra-bootstrap"
    }
    schemaVersion = {
      stringValue = "1"
    }
  })
}

resource "null_resource" "destroy_cleanup_cart_firestore" {
  count = var.enable_cart_firestore_destroy_cleanup ? 1 : 0

  triggers = {
    project_id = var.project_id
  }

  depends_on = [
    google_firestore_index.cart_items_user_updated_at,
    google_firestore_document.cart_bootstrap,
  ]

  provisioner "local-exec" {
    when    = destroy
    command = "python3 \"${path.module}/scripts/cart_firestore_destroy_cleanup.py\""
    environment = {
      PROJECT_ID = self.triggers.project_id
    }
  }
}
