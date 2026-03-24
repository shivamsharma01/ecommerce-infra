# Demo catalog seed

`products.json` is the source of truth for demo catalog bootstrap.

- Put real product photos in `assets/`.
- In each product record, set `imagePaths` (list) relative to `assets/` (example: `women/kurtas/item-01.jpg`).
- Do not commit proprietary images unless you own redistribution rights.

Bootstrap command (from `deploy/`):

```bash
make catalog-bootstrap PROJECT_ID=ecommerce-491019 BUCKET=<bucket-from-terraform-output>
```

Optional env vars:

- `CATALOG_JSON` (default `catalog/products.json`)
- `CATALOG_ASSETS_DIR` (default `catalog/assets`)
- `IMAGE_PREFIX` (default `products`)
- `MCART_BEARER_TOKEN` (optional; if set, script calls product-indexer reindex endpoint)
