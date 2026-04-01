# Preserve state when upgrading from count-based resources (optional flags removed).
moved {
  from = google_compute_global_address.mcart_public[0]
  to   = google_compute_global_address.mcart_public
}

# Catalog bucket was previously always a data source (no count); it is now count = 1 when Terraform does not manage the bucket.
moved {
  from = data.google_storage_bucket.catalog_images
  to   = data.google_storage_bucket.catalog_images[0]
}
