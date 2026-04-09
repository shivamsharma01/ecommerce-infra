# Revert: catalog bucket is a plain data source again (no count).
moved {
  from = data.google_storage_bucket.catalog_images[0]
  to   = data.google_storage_bucket.catalog_images
}
