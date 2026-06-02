# Product image GCS flow

How catalog images are **written** (admin upload, IAM-backed) vs **read** (browser, no GCS credentials).

## Permissions summary

| Actor | GCS access | How |
|-------|------------|-----|
| **Admin browser** | None | Sends multipart upload to Product API with **Bearer JWT** (`SCOPE_product.admin`) |
| **Product pod** | **Write** | GCP SA `mcart-product@…` → `roles/storage.objectAdmin` on catalog bucket (Terraform) via **Workload Identity** |
| **Shopper browser** | **Read only (public)** | `<img src="https://storage.googleapis.com/…">` — no token; bucket IAM `allUsers` → `roles/storage.objectViewer` when public read is enabled |
| **Product API (GET)** | None for image bytes | Returns **URLs only** from Firestore; does not proxy image content |

Bucket setup: `ecomm-infra/deploy/scripts/create_catalog_bucket.sh` (`CATALOG_BUCKET_PUBLIC_READ=true` grants public read).  
Terraform: `google_storage_bucket_iam_member.product_catalog_object_admin` grants the product workload SA write access.

Object layout (from `ProductImageUploadService`):

```text
gs://{CATALOG_IMAGES_BUCKET}/products/sku-{sku-slug}/gallery/{n}/thumb.jpg
gs://{CATALOG_IMAGES_BUCKET}/products/sku-{sku-slug}/gallery/{n}/hd.jpg
```

Public URL stored in Firestore:

```text
https://storage.googleapis.com/{bucket}/products/sku-{sku-slug}/gallery/{n}/thumb.jpg
```

---

## Flow A — Admin upload (write to GCS)

Requires: JWT at gateway + `SCOPE_product.admin` at Product service + product SA `storage.objectAdmin`.

```text
title Product Image Upload (admin create)
participant Admin UI
participant API Gateway
participant Product Service
participant GCS Bucket
participant Firestore

Admin UI -> API Gateway: POST /api/products/upload\n(multipart: product JSON + image files)\nAuthorization: Bearer {jwt}

API Gateway -> API Gateway: Validate JWT\n(protected route;\nrequires valid Bearer token)

API Gateway -> Product Service: POST /api/products/upload\n(forward Authorization header)

Product Service -> Product Service: 1. Validate JWT\n2. Require SCOPE_product.admin\n3. Validate multipart manifest\n   (gallery slots, file names)

Product Service -> Product Service: Resolve ADC credentials\n(K8s SA product → WI →\nGCP SA mcart-product@…)

loop For each gallery image (thumb + hd)
  Product Service -> GCS Bucket: storage.create(\n  gs://…/products/sku-{slug}/gallery/{n}/thumb.jpg,\n  gs://…/products/sku-{slug}/gallery/{n}/hd.jpg\n)\n[IAM: roles/storage.objectAdmin]
  GCS Bucket --> Product Service: Object created
end

Product Service -> Product Service: Build gallery URLs:\nhttps://storage.googleapis.com/{bucket}/{object}

Product Service -> Firestore: Save ProductDocument +\noutbox event\n(gallery[].thumbnailUrl, gallery[].hdUrl)

Firestore --> Product Service: OK

Product Service --> API Gateway: 201 Created\nProductResponse {\n  id, name, sku,\n  gallery: [{ thumbnailUrl, hdUrl, alt }]\n}

API Gateway --> Admin UI: 201 Created\n(same JSON body)
```

**If GCS write fails:** upload throws → Product service returns **5xx**; nothing is committed to Firestore for that request (upload and create are in one reactive chain).

**If Firestore fails after GCS upload:** objects may exist in GCS without a matching product row (orphan objects until cleanup).

---

## Flow B — Shopper views product (read images, no GCS permissions)

Requires: **no JWT** for product GET at gateway; **no GCS credentials** in the browser.

```text
title Product Image Read (public UI)
participant Shopper UI
participant API Gateway
participant Product Service
participant Firestore
participant GCS Bucket

Shopper UI -> API Gateway: GET /api/products/{id}\n(no Authorization header)

API Gateway -> Product Service: GET /api/products/{id}\n(public HTTPRoute;\nno JWT at edge)

Product Service -> Product Service: Public read allowed\n(SecurityConfig: GET /api/** permitAll)

Product Service -> Firestore: Load product by id

Firestore --> Product Service: ProductDocument {\n  gallery: [\n    { thumbnailUrl: "https://storage.googleapis.com/…/thumb.jpg",\n      hdUrl: "https://storage.googleapis.com/…/hd.jpg" }\n  ]\n}

Product Service --> API Gateway: 200 OK\nProductResponse (URLs only;\nno image bytes)

API Gateway --> Shopper UI: 200 OK

Shopper UI -> Shopper UI: Render <img [src]="gallery[0].thumbnailUrl">\n(absolute https URL from API)

Shopper UI -> GCS Bucket: GET https://storage.googleapis.com/{bucket}/products/…/thumb.jpg\n(no Authorization header)

GCS Bucket -> GCS Bucket: Check bucket IAM:\nallUsers has roles/storage.objectViewer\n(public read)

GCS Bucket --> Shopper UI: 200 OK\n(image/jpeg bytes)

Shopper UI -> Shopper UI: Browser displays image
```

**If public read is not enabled:** browser GET to `storage.googleapis.com` returns **403**; UI shows broken image even though product API returned valid URLs.

**If product GET fails:** UI shows error state; no GCS request for that product.

---

## Flow C — Append gallery (same write pattern as create)

```text
title Product Image Upload (admin append gallery)
participant Admin UI
participant API Gateway
participant Product Service
participant GCS Bucket
participant Firestore

Admin UI -> API Gateway: POST /api/products/{id}/gallery\n(multipart: gallery manifest + files)\nAuthorization: Bearer {jwt}

API Gateway -> Product Service: Forward with JWT\n(protected route)

Product Service -> Firestore: Load existing product (for SKU slug + next index)

Product Service -> GCS Bucket: storage.create new thumb/hd objects\n[IAM: roles/storage.objectAdmin]

Product Service -> Firestore: Append gallery URLs;\nwrite outbox PRODUCT_UPDATED

Product Service --> Admin UI: 200 OK\nupdated ProductResponse
```

---

## Related code and infra

| Item | Location |
|------|----------|
| Upload + public URL builder | `product/.../ProductImageUploadService.java` |
| Admin-only POST security | `product/.../SecurityConfig.java` |
| Public GET product | `product/.../ProductController.java` |
| UI `<img [src]>` | `mcart-ui/.../product-detail.component.html`, `product-card.component.ts` |
| Gateway public vs protected routes | `ecomm-infra/deploy/k8s/gateway/02-httproutes.yaml` |
| Product SA bucket IAM | `ecomm-infra/terraform/iam_workloads.tf` |
| Public bucket read script | `ecomm-infra/deploy/scripts/create_catalog_bucket.sh` |
