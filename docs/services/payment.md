# payment service

Mock payment processing for the demo store. Persists charge records in **PostgreSQL**.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Security | OAuth2 resource server |
| Database | PostgreSQL (JPA) |
| Other | Lombok, Actuator |

Default port: **8088**. **No Redis.**

## 2. APIs

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/payments/charge` | Charge amount for order (mock) |
| GET | `/actuator/health/**` | Health |

Called by **order** service during checkout (service-to-service with user JWT or configured client).

## 3. Main flows

### Charge

1. Validate `ChargeRequest` (order id, amount, currency, etc.).
2. Simulate success/failure based on config or card test rules (demo).
3. Insert `PaymentEntity` with status `COMPLETED` or `FAILED`.
4. Return payment id and status to order.

### Idempotency

Order passes stable order id; payment service should treat duplicate charge attempts per deployment rules (check implementation for duplicate order id handling).

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Body | Jakarta validation on charge request |
| Business | Invalid amount or missing order → 400 |

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **PostgreSQL** | Charge not persisted → **5xx** to order |
| **No external PSP** | Mock only — no Stripe/network failures |

**Order behavior:** If payment returns failure, order checkout stops and may compensate inventory. If payment succeeds but order DB commit fails, money is “charged” in mock DB while order row missing — operational inconsistency documented in order flow.

## 6. Redis usage

**None.**
