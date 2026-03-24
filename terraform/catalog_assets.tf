locals {
  catalog_images_bucket_name_effective = coalesce(var.catalog_images_bucket_name, "${var.project_id}-mcart-catalog-images")
}

resource "google_storage_bucket" "catalog_images" {
  name                        = local.catalog_images_bucket_name_effective
  location                    = var.catalog_images_bucket_location
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "catalog_images_public" {
  count  = var.catalog_images_bucket_public ? 1 : 0
  bucket = google_storage_bucket.catalog_images.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
