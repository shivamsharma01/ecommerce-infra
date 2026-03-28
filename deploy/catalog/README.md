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

Bootstrap command (from `deploy/`):

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
