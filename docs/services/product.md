# product service

Product catalog: CRUD, image upload to GCS, Firestore persistence, and **transactional outbox** → Pub/Sub for inventory and search indexing.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot **3.2.5** |
| API | **Spring WebFlux** (reactive) |
| Security | OAuth2 resource server (optional `app.security.enabled`) |
| Database | **Google Firestore** (products + outbox collections) |
| Storage | Google Cloud Storage (catalog images) |
| Messaging | Pub/Sub via outbox publisher job |
| Other | MapStruct, validation, Actuator |

Default port: **8084**. **No Redis.**

## 2. APIs

| Method | Path | Auth (typical) |
|--------|------|----------------|
| GET | `/health` | Public |
| GET | `/api/products/{id}` | Public read |
| GET | `/api/products?page&size` | Public paginated list |
| POST | `/api/products/upload` | Admin (`SCOPE_product.admin`) |
| PUT | `/api/products/{id}` | Admin |
| POST | `/api/products/{id}/gallery` | Admin |
| DELETE | `/api/products/{id}` | Admin |

Gateway: GET/HEAD/OPTIONS `/api/products` are **public** at edge; mutations require JWT + admin scope.

## 3. Main flows

### Create / update / delete product

1. Validate `ProductRequest` (name, SKU, price > 0, stock ≥ 0, gallery 1–10 images, etc.).
2. Check SKU uniqueness on create/update.
3. Read/write `ProductDocument` in Firestore; bump version on update.
4. Write matching **outbox** document (`PRODUCT_CREATED`, `PRODUCT_UPDATED`, `PRODUCT_DELETED`).
5. Return mapped DTO.

### Upload images

Multipart upload → GCS (thumb + HD paths) → build product → `createProduct`.

### Outbox → Pub/Sub

`OutboxPublisherJob` (scheduled ~5s) publishes pending outbox events to **`product-events`** topic. Downstream: **inventory** subscriber, **product-indexer** subscriber.

### Read

Firestore `findById` or list-all with in-memory pagination (page size clamped).

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Body | `@Valid` on `ProductRequest`, upload/append DTOs |
| Constraints | `@NotBlank`, `@NotNull`, `@DecimalMin`, `@Min`, rating 0–5, gallery size |
| Business | Duplicate SKU → `DuplicateSkuException` → **409** |
| Security | Admin mutations require JWT scope when security enabled |

`GlobalExceptionHandler`: 404 not found, 409 duplicate SKU, 503 outbox persistence errors, 400 validation errors.

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **Firestore** | Persistence errors → `OutboxPersistenceException` or reactive errors → 5xx |
| **GCS upload** | Missing bucket/config → `IllegalStateException`; bad multipart → 400 |
| **Pub/Sub** (outbox job) | Publish failure increments retry on outbox doc; batch errors logged; retried on next tick |
| **HTTP outbound** | None |

Product write **commits to Firestore** before outbox publish; search/inventory may lag seconds until outbox runs.

## 6. Redis usage

**None** in application code (architecture diagrams may show cache — not implemented in search/product path).
