locals {
  catalog_images_bucket_name_effective = coalesce(
    var.catalog_images_bucket_name,
    "${var.project_id}-mcart-catalog-images"
  )

  catalog_images_bucket_name = var.create_catalog_images_bucket ? google_storage_bucket.catalog_images_managed[0].name : data.google_storage_bucket.catalog_images[0].name
}

resource "google_storage_bucket" "catalog_images_managed" {
  count = var.create_catalog_images_bucket ? 1 : 0

  name                        = local.catalog_images_bucket_name_effective
  location                    = coalesce(var.catalog_images_bucket_location, upper(var.region))
  uniform_bucket_level_access = true
  force_destroy               = var.catalog_images_bucket_force_destroy

  public_access_prevention = "enforced"
}

data "google_storage_bucket" "catalog_images" {
  count = var.create_catalog_images_bucket ? 0 : 1
  name  = local.catalog_images_bucket_name_effective
}
