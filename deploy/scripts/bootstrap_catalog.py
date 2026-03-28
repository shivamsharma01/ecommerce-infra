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
  FORCE_UPLOAD          optional true/false (default false)

Catalog image input (required):
  gallery: [{"thumbPath":"...", "hdPath":"...", "alt":"..."}]
"""

from __future__ import annotations

import json
import os
import argparse
import hashlib
import base64
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


def _bool_env(name: str, default: bool = False) -> bool:
    raw = os.getenv(name, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "y", "on"}


def _md5_b64(path: Path) -> str:
    hasher = hashlib.md5()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            hasher.update(chunk)
    return base64.b64encode(hasher.digest()).decode("ascii")


def _public_url(bucket: str, object_name: str) -> str:
    return f"https://storage.googleapis.com/{bucket}/{object_name}"


def _normalize_gallery_input(raw: Dict[str, Any]) -> List[Dict[str, str]]:
    explicit = raw.get("gallery")
    if not explicit:
        sku = str(raw.get("sku", "")).strip()
        raise SystemExit(
            f"Product {sku or '<unknown>'} is missing required 'gallery' array."
        )

    gallery: List[Dict[str, str]] = []
    for idx, item in enumerate(explicit, start=1):
        if not isinstance(item, dict):
            raise SystemExit("gallery items must be objects")
        thumb = str(item.get("thumbPath", "")).strip()
        hd = str(item.get("hdPath", "")).strip() or thumb
        alt = str(item.get("alt", "")).strip() or f"Image {idx}"
        if not thumb:
            raise SystemExit(f"gallery[{idx}] is missing thumbPath")
        gallery.append({"thumbPath": thumb, "hdPath": hd, "alt": alt})
    return gallery


def _upload_blob_if_needed(
    bucket_obj: storage.Bucket, local: Path, object_name: str, force_upload: bool
) -> None:
    blob = bucket_obj.blob(object_name)
    local_size = local.stat().st_size
    local_md5 = _md5_b64(local)

    if blob.exists():
        blob.reload()
        if blob.size == local_size and blob.md5_hash == local_md5:
            return
        if not force_upload:
            raise SystemExit(
                f"Remote object differs for {object_name}. "
                "Set FORCE_UPLOAD=true or pass --force to overwrite."
            )

    blob.upload_from_filename(str(local))


def _upload_gallery_if_needed(
    storage_client: storage.Client,
    bucket_name: str,
    assets_root: Path,
    image_prefix: str,
    product_id: str,
    gallery: List[Dict[str, str]],
    force_upload: bool,
) -> List[Dict[str, str]]:
    bucket_obj = storage_client.bucket(bucket_name)
    uploaded: List[Dict[str, str]] = []

    for idx, item in enumerate(gallery, start=1):
        thumb_ref = item["thumbPath"]
        hd_ref = item["hdPath"]
        alt = item.get("alt", f"Image {idx}")

        thumb_is_local = not thumb_ref.startswith("http://") and not thumb_ref.startswith("https://")
        hd_is_local = not hd_ref.startswith("http://") and not hd_ref.startswith("https://")

        if thumb_is_local:
            thumb_local = assets_root / thumb_ref
            if not thumb_local.exists():
                raise SystemExit(f"Missing image file: {thumb_local}")
            thumb_ext = thumb_local.suffix.lower() or ".jpg"
            thumb_object = f"{image_prefix}/{product_id}/gallery/{idx}/thumb{thumb_ext}".replace("\\", "/")
            _upload_blob_if_needed(bucket_obj, thumb_local, thumb_object, force_upload)
            thumbnail_url = _public_url(bucket_name, thumb_object)
        else:
            thumbnail_url = thumb_ref

        if hd_is_local:
            hd_local = assets_root / hd_ref
            if not hd_local.exists():
                raise SystemExit(f"Missing HD image file: {hd_local}")
            hd_ext = hd_local.suffix.lower() or ".jpg"
            hd_object = f"{image_prefix}/{product_id}/gallery/{idx}/hd{hd_ext}".replace("\\", "/")
            _upload_blob_if_needed(bucket_obj, hd_local, hd_object, force_upload)
            hd_url = _public_url(bucket_name, hd_object)
        else:
            hd_url = hd_ref

        uploaded.append({"thumbnailUrl": thumbnail_url, "hdUrl": hd_url, "alt": alt})

    return uploaded


def _normalized_product(raw: Dict[str, Any], gallery_urls: List[Dict[str, str]]) -> Dict[str, Any]:
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
        "gallery": gallery_urls,
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


def _product_id(raw: Dict[str, Any]) -> str:
    sku = str(raw["sku"]).strip()
    return str(raw.get("productId") or f"P-{sku}")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bootstrap catalog into Firestore + GCS.")
    parser.add_argument("--force", action="store_true", help="Overwrite changed remote images.")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    project_id = _required_env("PROJECT_ID")
    bucket = _required_env("BUCKET")
    base_dir = Path(__file__).resolve().parents[1]
    catalog_json = Path(os.getenv("CATALOG_JSON", str(base_dir / "catalog" / "products.json")))
    assets_dir = Path(os.getenv("CATALOG_ASSETS_DIR", str(base_dir / "catalog" / "assets")))
    image_prefix = os.getenv("IMAGE_PREFIX", "products").strip() or "products"
    collection_name = os.getenv("FIRESTORE_COLLECTION", "products").strip() or "products"
    reindex_url = os.getenv("REINDEX_URL", "").strip()
    bearer_token = os.getenv("MCART_BEARER_TOKEN", "").strip()
    force_upload = args.force or _bool_env("FORCE_UPLOAD", False)

    products = _load_products(catalog_json)
    fs = firestore.Client(project=project_id)
    storage_client = storage.Client(project=project_id)
    coll = fs.collection(collection_name)

    upserted = 0
    for raw in products:
        product_id = _product_id(raw)
        gallery = _normalize_gallery_input(raw)
        gallery_urls = _upload_gallery_if_needed(
            storage_client=storage_client,
            bucket_name=bucket,
            assets_root=assets_dir,
            image_prefix=image_prefix,
            product_id=product_id,
            gallery=gallery,
            force_upload=force_upload,
        )
        doc = _normalized_product(raw, gallery_urls)
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
