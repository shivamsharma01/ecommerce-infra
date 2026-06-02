# product-indexer service

Keeps OpenSearch **`products`** index in sync with catalog changes. Consumes `product-events` from Pub/Sub; optional admin HTTP to reindex.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Search | OpenSearch client |
| Messaging | Pub/Sub subscriber |
| Security | OAuth2 resource server on admin routes |
| Other | Actuator |

Default port: **8085**. **No Redis.**

Note: Java packages use `elasticsearch` naming; the cluster is **OpenSearch** in deploy.

## 2. APIs

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/product-indexer/admin/reindex` | Protected at gateway | Bulk reindex catalog into OpenSearch |
| GET | `/actuator/health/**` | Public | Health |

Exact admin path — check `AdminController` in repo; gateway routes protected indexer paths to this service.

## 3. Main flows

### Event-driven index update

1. Product outbox publishes `PRODUCT_CREATED` / `UPDATED` / `DELETED`.
2. Subscriber receives message.
3. Index, update, or delete document in OpenSearch by `productId`.
4. **Ack** on success; **nack** on transient OpenSearch errors.

### Admin reindex

Bulk load products (HTTP to product API or direct source per implementation) and bulk-index into OpenSearch.

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Pub/Sub | Event type and payload fields |
| Admin HTTP | JWT + admin scope when security enabled |

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **OpenSearch** | Index failure → **nack** (retry message) |
| **Product HTTP** (reindex) | Partial failure logged; reindex endpoint may return 5xx |
| **Malformed event** | Often ack after log to avoid poison loop (confirm in subscriber code) |

Search UI may lag catalog until indexer succeeds.

## 6. Redis usage

**None.**
