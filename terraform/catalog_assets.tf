locals {
  catalog_images_bucket_name_effective = coalesce(var.catalog_images_bucket_name, "${var.project_id}-mcart-catalog-images")
}

data "google_storage_bucket" "catalog_images" {
  name = local.catalog_images_bucket_name_effective
}
