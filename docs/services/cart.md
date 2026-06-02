# cart service

Per-user shopping cart stored in **Firestore**. Optional real-time stock checks against inventory over HTTP.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Security | OAuth2 resource server (JWT) |
| Database | **Firestore** (`cart_items` collection) |
| HTTP client | `RestTemplate` → inventory service |
| Other | MapStruct, Lombok, Actuator |

Default port: **8087**. **No Redis.**

## 2. APIs

All cart routes require **Bearer JWT** with `userId` claim.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/cart` | List cart lines |
| POST | `/cart/items` | Add or update line (`productId`, `quantity`) |
| DELETE | `/cart/items/{productId}` | Remove line |
| POST | `/cart/clear` | Clear all lines |
| GET | `/actuator/health/**` | Health |

## 3. Main flows

### Add / update item

1. Resolve `userId` from JWT.
2. If `inventory.check-enabled=true`, **GET** inventory for `productId` — reject if insufficient stock.
3. Upsert `CartItemDocument` in Firestore (composite key user + product).
4. Return `CartResponse` with line items and totals.

### Read cart

Load all documents for user; map to response (no inventory call unless configured elsewhere).

### Clear cart

Used by **order** service after successful checkout (HTTP DELETE with same user JWT).

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| JWT | Resource server; `userId` required in controller |
| Body | `AddCartItemRequest`: `@NotBlank productId`, `@Min(1) quantity` |
| Inventory | Optional HTTP check — failure modes below |

`GlobalExceptionHandler` for validation and domain errors.

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **Inventory HTTP** (when enabled) | Connection/timeout/5xx → typically surfaces as error to client (cannot confirm stock) |
| **Firestore** | Read/write errors → **500** (e.g. transaction manager issues if misconfigured) |
| **Order clearing cart** | Order checkout may succeed in DB but cart clear failure is handled in order service (logged; user may see stale cart) |

Note: `@Transactional` was removed from cart service because it conflicted with reactive Firestore transaction manager when returning blocking responses.

## 6. Redis usage

**None.**
