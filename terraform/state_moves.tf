# Preserve state when upgrading from count-based resources (optional flags removed).
moved {
  from = google_compute_global_address.mcart_public[0]
  to   = google_compute_global_address.mcart_public
}

# Revert: catalog bucket is a plain data source again (no count).
moved {
  from = data.google_storage_bucket.catalog_images[0]
  to   = data.google_storage_bucket.catalog_images
}
