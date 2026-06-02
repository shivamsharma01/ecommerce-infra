# order service

Checkout orchestration: reads cart and user address, prices from product, decrements inventory, charges payment, persists order, clears cart, publishes order-paid email event.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Security | OAuth2 resource server |
| Database | PostgreSQL (JPA); JSON column for shipping address (`@JdbcTypeCode(SqlTypes.JSON)`) |
| HTTP clients | WebClient/RestTemplate to cart, user, product, inventory, payment |
| Messaging | Pub/Sub publisher (`order-paid-events`) |
| JSON | Jackson databind + JSR310 module for Hibernate JSON mapping |
| Other | Lombok, Actuator |

Default port: **8089**. **No Redis.**

## 2. APIs

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/orders/checkout` | Full checkout saga |
| GET | `/orders` | List order summaries for user |
| GET | `/actuator/health/**` | Health |

## 3. Main flows

### Checkout (`POST /orders/checkout`)

Typical sequence:

1. **Validate** checkout body (address id, payment method fields per DTO).
2. **User** — fetch default or specified shipping address (HTTP).
3. **Cart** — GET cart lines (HTTP).
4. **Product** — resolve prices/titles for line items (HTTP).
5. **Inventory** — POST decrement for all lines (HTTP).
6. **Payment** — POST charge for computed total (HTTP).
7. **Postgres** — insert `OrderEntity` + line items; flush transaction.
8. **Cart** — POST `/cart/clear` (HTTP).
9. **Pub/Sub** — publish `ORDER_PAID` for email service (if enabled).

Logging may show “Checkout completed” around payment before DB flush — failure on step 7 leaves charged mock payment without visible order until fixed.

### Compensation

If a step fails after inventory decrement, service attempts **inventory increment** rollback. Payment failure before DB commit avoids order row; payment success + DB failure is the hardest edge case (manual reconciliation in production).

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| JWT | `userId` from token |
| Body | `@Valid` on checkout request |
| Preconditions | Empty cart, missing address, stock errors from inventory → 4xx |

`GlobalExceptionHandler` maps downstream HTTP errors to appropriate statuses.

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **User** | Cannot load address → checkout aborted (4xx/5xx) |
| **Cart** | Empty or unreachable → abort |
| **Product** | Missing product/price → abort |
| **Inventory decrement** | Insufficient stock → abort; may not reach payment |
| **Payment** | Failed charge → abort; compensate inventory if already decremented |
| **Postgres persist** | **500** after possible successful payment — user sees error; cart may still have items |
| **Cart clear** | Often logged; order may exist with stale cart |
| **Pub/Sub order-paid** | Email may not send; order still committed |

## 6. Redis usage

**None.**
