#!/usr/bin/env python3
"""
Upload demo catalog images to GCS and upsert products into Firestore.

Expected env:
  PROJECT_ID            GCP project id
  BUCKET                GCS bucket name
Optional env:
  CATALOG_JSON          default: deploy/catalog/products.json
  CATALOG_ASSETS_DIR    default: deploy/catalog/assets

Local gallery paths:
  - Single file: thumbPath + hdPath as today.
  - Directory: thumbPath may be a folder path, or a missing .jpg/.png path whose basename
    without extension is a folder (e.g. kurtas-suits.jpg → kurtas-suits/).
    Folder layout: N.ext + N.1.ext (thumb + HD), or thumb/ + hd/ with matching filenames.
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

# Stored document must not duplicate the collection document id; Java @DocumentId maps path only.
_DELETE_REDUNDANT_PRODUCT_ID = {"productId": firestore.DELETE_FIELD}


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


def _deploy_relative_path(base_dir: Path, env_name: str, default_relative: str) -> Path:
    """Resolve env path relative to deploy/ (parent of scripts/), not the process cwd."""
    raw = os.getenv(env_name, "").strip()
    if not raw:
        return (base_dir / default_relative).resolve()
    p = Path(raw)
    if p.is_absolute():
        return p.resolve()
    return (base_dir / p).resolve()


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


_IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png", ".webp", ".gif"})


def _rel_under_assets(assets_root: Path, path: Path) -> str:
    return path.resolve().relative_to(assets_root.resolve()).as_posix()


def _scan_gallery_folder(folder: Path) -> List[tuple[Path, Path]]:
    """
    Pairs (thumb_file, hd_file) under folder.

    Layout 1: numeric base images — N.ext (thumb) + N.1.ext (HD), stem of base is digits only.
    Layout 2: thumb/ and hd/ subdirs with the same filenames.
    """
    files = [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in _IMAGE_SUFFIXES]
    numeric_bases = [p for p in files if p.stem.isdigit()]
    if numeric_bases:
        out: List[tuple[Path, Path]] = []
        ext = numeric_bases[0].suffix
        for base in sorted(numeric_bases, key=lambda p: int(p.stem)):
            n = base.stem
            hd_candidate = folder / f"{n}.1{ext}"
            if not hd_candidate.is_file():
                hd_candidate = base
            out.append((base, hd_candidate))
        return out

    thumb_dir = folder / "thumb"
    hd_dir = folder / "hd"
    if thumb_dir.is_dir() and hd_dir.is_dir():
        pairs: List[tuple[Path, Path]] = []
        for t in sorted(
            thumb_dir.iterdir(),
            key=lambda p: (len(p.name), p.name),
        ):
            if not t.is_file() or t.suffix.lower() not in _IMAGE_SUFFIXES:
                continue
            h = hd_dir / t.name
            if not h.is_file():
                raise SystemExit(f"Gallery HD missing for {t.name}: {h}")
            pairs.append((t, h))
        if not pairs:
            raise SystemExit(f"No images in {thumb_dir}")
        return pairs

    raise SystemExit(
        f"Gallery folder {folder} has no numeric N.jpg + N.1.jpg pairs "
        f"and no thumb/ + hd/ subdirectories."
    )


def _expand_gallery_item(assets_root: Path, thumb_ref: str, hd_ref: str, alt: str) -> List[Dict[str, str]]:
    """One JSON gallery entry → one or more local (thumbPath, hdPath, alt) rows."""
    thumb_remote = thumb_ref.startswith("http://") or thumb_ref.startswith("https://")
    hd_remote = hd_ref.startswith("http://") or hd_ref.startswith("https://")
    if thumb_remote or hd_remote:
        return [{"thumbPath": thumb_ref, "hdPath": hd_ref, "alt": alt}]

    thumb_path = assets_root / thumb_ref
    hd_path = assets_root / hd_ref

    if thumb_path.is_file():
        if not hd_path.is_file():
            raise SystemExit(f"Missing HD image file: {hd_path}")
        return [{"thumbPath": thumb_ref, "hdPath": hd_ref, "alt": alt}]

    if thumb_path.is_dir():
        pairs = _scan_gallery_folder(thumb_path)
        return [
            {
                "thumbPath": _rel_under_assets(assets_root, t),
                "hdPath": _rel_under_assets(assets_root, h),
                "alt": f"{alt} ({i})" if len(pairs) > 1 else alt,
            }
            for i, (t, h) in enumerate(pairs, start=1)
        ]

    # JSON path is a file that does not exist — try same path without extension as a directory
    # (e.g. kurtas-suits.jpg → kurtas-suits/)
    suf = thumb_path.suffix.lower()
    if suf in _IMAGE_SUFFIXES:
        dir_guess = assets_root / Path(thumb_ref).with_suffix("")
        if dir_guess.is_dir():
            pairs = _scan_gallery_folder(dir_guess)
            return [
                {
                    "thumbPath": _rel_under_assets(assets_root, t),
                    "hdPath": _rel_under_assets(assets_root, h),
                    "alt": f"{alt} ({i})" if len(pairs) > 1 else alt,
                }
                for i, (t, h) in enumerate(pairs, start=1)
            ]

    raise SystemExit(f"Missing image file: {thumb_path}")


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

    expanded: List[Dict[str, str]] = []
    for item in gallery:
        expanded.extend(
            _expand_gallery_item(
                assets_root,
                item["thumbPath"],
                item["hdPath"],
                item.get("alt", "Image"),
            )
        )
    gallery = expanded

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
    out: Dict[str, Any] = {
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
    catalog_json = _deploy_relative_path(base_dir, "CATALOG_JSON", "catalog/products.json")
    assets_dir = _deploy_relative_path(base_dir, "CATALOG_ASSETS_DIR", "catalog/assets")
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
        doc_ref = coll.document(product_id)
        doc_ref.set(doc, merge=True)
        doc_ref.update(_DELETE_REDUNDANT_PRODUCT_ID)
        upserted += 1

    print(f"Upserted {upserted} products to Firestore collection '{collection_name}' in project '{project_id}'.")

    if reindex_url and bearer_token:
        _trigger_reindex(reindex_url, bearer_token)
    elif reindex_url:
        print("REINDEX_URL set but MCART_BEARER_TOKEN missing; skipping reindex.")


if __name__ == "__main__":
    main()
