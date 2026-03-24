#!/usr/bin/env python3
"""
Upload demo catalog images to GCS and upsert products into Firestore.

Expected env:
  PROJECT_ID            GCP project id
  BUCKET                GCS bucket name
Optional env:
  CATALOG_JSON          default: deploy/catalog/products.json
  CATALOG_ASSETS_DIR    default: deploy/catalog/assets
  IMAGE_PREFIX          default: products
  FIRESTORE_COLLECTION  default: products
  REINDEX_URL           optional (if set with token, trigger reindex)
  MCART_BEARER_TOKEN    optional auth token for reindex endpoint
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List
from urllib.request import Request, urlopen

from google.cloud import firestore, storage


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required env: {name}")
    return value


def _load_products(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        raise SystemExit(f"Catalog json not found: {path}")
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise SystemExit("Catalog json must be a list of product objects")
    return data


def _upload_images_if_needed(
    storage_client: storage.Client,
    bucket_name: str,
    assets_root: Path,
    image_prefix: str,
    image_paths: List[str] | None,
) -> List[str]:
    if not image_paths:
        return []
    urls: List[str] = []
    for image_path in image_paths:
        local = assets_root / image_path
        if not local.exists():
            raise SystemExit(f"Missing image file: {local}")
        object_name = f"{image_prefix}/{image_path}".replace("\\", "/")
        blob = storage_client.bucket(bucket_name).blob(object_name)
        blob.upload_from_filename(str(local))
        urls.append(f"https://storage.googleapis.com/{bucket_name}/{object_name}")
    return urls


def _normalized_product(raw: Dict[str, Any], image_urls: List[str]) -> Dict[str, Any]:
    sku = str(raw["sku"]).strip()
    categories = [str(x).strip() for x in raw.get("categories", []) if str(x).strip()]
    if not categories:
        raise SystemExit(f"Product {sku} must include non-empty categories")
    product_id = str(raw.get("productId") or f"P-{sku}")

    out: Dict[str, Any] = {
        "productId": product_id,
        "name": str(raw["name"]).strip(),
        "description": str(raw.get("description") or "").strip(),
        "price": float(raw["price"]),
        "sku": sku,
        "stockQuantity": int(raw.get("stockQuantity", 0)),
        "categories": categories,
        "brand": (str(raw["brand"]).strip() if raw.get("brand") is not None else None),
        "imageUrls": image_urls or raw.get("imageUrls") or [],
        "rating": (float(raw["rating"]) if raw.get("rating") is not None else None),
        "inStock": bool(raw.get("inStock", int(raw.get("stockQuantity", 0)) > 0)),
        "attributes": raw.get("attributes") or {},
        "version": int(raw.get("version", 1)),
        "createdAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    return out


def _trigger_reindex(reindex_url: str, token: str) -> None:
    req = Request(
        reindex_url,
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        data=b"{}",
    )
    with urlopen(req, timeout=30) as response:
        body = response.read().decode("utf-8", errors="replace")
        print(f"Reindex response: HTTP {response.status} {body}")


def main() -> None:
    project_id = _required_env("PROJECT_ID")
    bucket = _required_env("BUCKET")
    base_dir = Path(__file__).resolve().parents[1]
    catalog_json = Path(os.getenv("CATALOG_JSON", str(base_dir / "catalog" / "products.json")))
    assets_dir = Path(os.getenv("CATALOG_ASSETS_DIR", str(base_dir / "catalog" / "assets")))
    image_prefix = os.getenv("IMAGE_PREFIX", "products").strip() or "products"
    collection_name = os.getenv("FIRESTORE_COLLECTION", "products").strip() or "products"
    reindex_url = os.getenv("REINDEX_URL", "").strip()
    bearer_token = os.getenv("MCART_BEARER_TOKEN", "").strip()

    products = _load_products(catalog_json)
    fs = firestore.Client(project=project_id)
    storage_client = storage.Client(project=project_id)
    coll = fs.collection(collection_name)

    upserted = 0
    for raw in products:
        image_urls = _upload_images_if_needed(
            storage_client=storage_client,
            bucket_name=bucket,
            assets_root=assets_dir,
            image_prefix=image_prefix,
            image_paths=raw.get("imagePaths"),
        )
        doc = _normalized_product(raw, image_urls)
        doc_id = doc["productId"]
        coll.document(doc_id).set(doc, merge=True)
        upserted += 1

    print(f"Upserted {upserted} products to Firestore collection '{collection_name}' in project '{project_id}'.")

    if reindex_url and bearer_token:
        _trigger_reindex(reindex_url, bearer_token)
    elif reindex_url:
        print("REINDEX_URL set but MCART_BEARER_TOKEN missing; skipping reindex.")


if __name__ == "__main__":
    main()
