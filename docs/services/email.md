# email service

Sends transactional email in response to **Pub/Sub** events. No public “send mail” REST API.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (minimal — health only) |
| Mail | Spring Mail → SMTP (e.g. Gmail app password) |
| Cache | **Redis** (dedupe only) |
| Messaging | Google Cloud Pub/Sub (subscribers) |
| Other | Actuator |

Default port: **8090**.

## 2. APIs

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Actuator health |

All real work is triggered by **Pub/Sub subscribers**, not HTTP.

## 3. Main flows

### Verification email

1. Auth publishes `SEND_VERIFICATION_EMAIL` on `email-verification-events`.
2. `VerificationEmailSubscriber` (if `email.pubsub.enabled=true`) receives message.
3. `VerificationEmailSender` builds HTML with link: `{base-url}/auth/verify-email?token=...`.
4. Send via SMTP → **ack** message.

### Order paid receipt

1. Order publishes `ORDER_PAID` on `order-paid-events` (when enabled).
2. `OrderPaidEmailSubscriber` parses JSON payload.
3. **Redis dedupe** by `orderId` — duplicate → ack without resend.
4. `OrderPaidEmailSender` sends HTML receipt → **ack**.
5. On SMTP failure → release dedupe key → **nack** for retry.

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Pub/Sub payload | Subscriber checks `eventType` / required fields (`email`, `token`, order fields) |
| Startup | `VerificationEmailSender` fails fast if base URL or From address empty |
| Missing customer email on order | Log warn, skip send, still ack after dedupe logic |

No HTTP request validation (no business REST API).

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **SMTP** (verification) | Exception → **nack** (retry) |
| **SMTP** (order paid) | Release Redis dedupe → **nack** |
| **Wrong event type** | Log warn → **ack** (no infinite retry) |
| **Pub/Sub disabled** | Subscribers not started (`@ConditionalOnProperty`) |

## 6. Redis usage

| Key pattern | Purpose | TTL |
|-------------|---------|-----|
| `mcart:email:order-paid:dedupe:{orderId}` | Idempotent order receipt | `dedupe-ttl-hours` (default 24h); deleted on SMTP failure before nack |

Verification emails do **not** use Redis dedupe (auth rate limits live in auth service).

Config: `SPRING_DATA_REDIS_*` / `REDIS_PASSWORD` in `email/secret.yaml`.
