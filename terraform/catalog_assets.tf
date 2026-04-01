locals {
  catalog_images_bucket_name_effective = coalesce(
    var.catalog_images_bucket_name,
    "${var.project_id}-mcart-catalog-images"
  )
}

# Bucket must already exist (create with deploy/scripts/create_catalog_bucket.sh or console).
# Terraform only references it for outputs and bucket-level IAM (e.g. product workload objectAdmin).
data "google_storage_bucket" "catalog_images" {
  name = local.catalog_images_bucket_name_effective
}
