# inventory service

Stock levels in **PostgreSQL**. Syncs from product events via Pub/Sub; exposes HTTP for cart checks and order checkout decrements.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Security | OAuth2 resource server (JWT on HTTP APIs) |
| Database | PostgreSQL (JPA) |
| Messaging | Pub/Sub subscriber (`product-events`) |
| Other | MapStruct, Lombok, Actuator |

Default port: **8086**. **No Redis.**

## 2. APIs

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/inventory/{productId}` | JWT (typical) | Current stock for product |
| POST | `/inventory/init` | JWT | Initialize stock row (admin/setup) |
| POST | `/inventory/decrement` | JWT | Reserve/decrement (checkout) |
| POST | `/inventory/increment` | JWT | Roll back / restock |
| GET | `/inventory/admin/items` | JWT | Admin list (see `InventoryAdminController`) |
| POST | `/inventory/admin/sync-from-catalog` | JWT | Manual catalog sync |
| GET | `/actuator/health/**` | Public | Health |

## 3. Main flows

### Product event sync (async)

1. `ProductEventSubscriber` receives `PRODUCT_CREATED` / `UPDATED` / `DELETED` from Pub/Sub.
2. Upsert or delete `inventory` row keyed by `productId`.
3. On handler error → **nack** for retry.

### HTTP decrement (checkout)

1. Order service calls with line items and quantities.
2. Transactional decrement per SKU; insufficient stock → **409** or domain error.
3. Order saga may call **increment** to compensate on later failure.

### Cart stock check

Cart optionally GETs `/inventory/{productId}` before add-to-cart.

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Decrement/increment body | `@Valid` DTOs with product id and positive quantity |
| Pub/Sub | JSON parse; ignore unknown event types with ack |
| JWT | Required on REST paths per security config |

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **PostgreSQL** | Transaction rolls back; HTTP 5xx |
| **Pub/Sub** | Processing exception → **nack**; poison messages may retry until fixed |
| **No outbound HTTP** | Inventory is a leaf service for sync |

Order checkout: if decrement fails, order aborts before payment or compensates if payment already ran (see order doc).

## 6. Redis usage

**None.**
