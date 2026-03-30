# Demo catalog seed

`products.json` is the source of truth for demo catalog bootstrap.

- Put real product photos in `assets/`.
- Required schema per product:
  - `gallery`: ordered list of `{ "thumbPath": "...", "hdPath": "...", "alt": "..." }`
  - paths are relative to `assets/`.
- Do not commit proprietary images unless you own redistribution rights.

Example:

```json
{
  "sku": "W-KS-001",
  "name": "Women Kurta Suit Set",
  "price": 1999,
  "stockQuantity": 25,
  "categories": ["Women", "Indian & Western Wear", "Kurtas & Suits"],
  "gallery": [
    { "thumbPath": "women/kurtas/1.jpg", "hdPath": "women/kurtas/1.1.jpg", "alt": "Front view" },
    { "thumbPath": "women/kurtas/2.jpg", "hdPath": "women/kurtas/2.1.jpg", "alt": "Back view" }
  ]
}
```

Create the bucket (once per project / demo env):

```bash
cd deploy
cp catalog/bootstrap.env.example catalog/bootstrap.env
# edit PROJECT_ID, BUCKET, BUCKET_LOCATION; set CATALOG_BUCKET_PUBLIC_READ=true for public image URLs
./scripts/create_catalog_bucket.sh
```

**Firestore + bootstrap IAM (required before `upload_catalog.sh` works end-to-end):** if you see `The database (default) does not exist`, or GCS/Firestore 403 from the wrong principal, run:

```bash
# Optional in bootstrap.env: FIRESTORE_LOCATION, CATALOG_BOOTSTRAP_SA_EMAIL, SKIP_CATALOG_IAM
chmod +x scripts/create_firestore_database.sh
./scripts/create_firestore_database.sh
```

The script creates the default **Firestore Native** database if missing, then grants **`roles/datastore.user`** on `PROJECT_ID` and **`roles/storage.objectAdmin`** on `gs://$BUCKET` (when the bucket exists) to the resolved principal: `CATALOG_BOOTSTRAP_MEMBER` / `CATALOG_BOOTSTRAP_SA_EMAIL` / `GOOGLE_APPLICATION_CREDENTIALS` client_email / `gcloud` active user.

Location cannot be changed later; pick the same region as your bucket when possible.

Product workload write access is applied by Terraform (`workload_service_accounts.product` → `roles/storage.objectAdmin` on this bucket).

Bootstrap images + Firestore (from `deploy/`):

```bash
cp catalog/bootstrap.env.example catalog/bootstrap.env
# edit values in catalog/bootstrap.env
./scripts/upload_catalog.sh
```

Force overwrite changed remote images:

```bash
FORCE_UPLOAD=true ./scripts/upload_catalog.sh
```

Optional env vars:

- `CATALOG_JSON` (default `catalog/products.json`)
- `CATALOG_ASSETS_DIR` (default `catalog/assets`)
- `IMAGE_PREFIX` (default `products`)
- `FORCE_UPLOAD` (default false; if true, overwrite changed remote objects)
- `MCART_BEARER_TOKEN` (optional; if set, script calls product-indexer reindex endpoint)

Post-run checks:

- Firestore product docs contain `gallery` only.
- GCS objects are grouped under `products/<productId>/gallery/<index>/thumb.*|hd.*`.
- UI detail route `/products/:id` shows gallery and zoom behavior for HD images.
