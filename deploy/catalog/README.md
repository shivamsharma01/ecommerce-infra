# Demo catalog (optional)

Seed **Firestore** + **GCS** images from [`products.json`](products.json) and [`assets/`](assets/).

- Each product needs `gallery`: `[{ "thumbPath", "hdPath", "alt" }]` with paths under `assets/`.
- Do not commit images you cannot redistribute.

**Once per project:** create bucket → [`scripts/create_catalog_bucket.sh`](../scripts/create_catalog_bucket.sh) (with `catalog/bootstrap.env`).

**Firestore + IAM** (if DB missing or 403): [`scripts/create_firestore_database.sh`](../scripts/create_firestore_database.sh).

**Upload:** from `deploy/`, set `catalog/bootstrap.env`, then `./scripts/upload_catalog.sh`.  
Optional: `FORCE_UPLOAD=true`, `MCART_BEARER_TOKEN` + `REINDEX_URL` for indexer.

Terraform grants the **product** workload SA write access to the catalog bucket (`catalog_images_bucket_name`).
