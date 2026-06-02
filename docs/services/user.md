# user service

User profile and shipping addresses. Consumes auth signup events; serves authenticated profile APIs.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 21 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Security | OAuth2 **resource server** (JWT from auth issuer) |
| Database | PostgreSQL (JPA) |
| Messaging | Google Cloud Pub/Sub (subscriber, optional) |
| Other | MapStruct, Lombok, Actuator |

Default port: **8082**. **No Redis.**

## 2. APIs

All routes require **Bearer JWT** with `userId` claim unless noted.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/user/me`, `/user/profile` | Profile (requires `emailVerified`) |
| GET | `/user/addresses` | List addresses |
| GET | `/user/addresses/default` | Default shipping address |
| GET | `/user/addresses/{addressId}` | One address |
| POST | `/user/addresses` | Create address |
| POST | `/user/addresses/{addressId}/default` | Set default |
| GET | `/health`, `/actuator/**` | Health (public) |

## 3. Main flows

### Event-driven profile creation

1. **Pub/Sub** delivers `USER_SIGNUP_COMPLETED` from auth.
2. `UserSignupSubscriber` → `UserService.handleSignupEvent`.
3. Insert or update `users` row; never downgrade `email_verified` on replay.

### Email verified

1. `EMAIL_VERIFIED` event → set `email_verified = true`.
2. If user row missing, log warning and ack (no retry storm).

### Profile read

1. Parse `userId` from JWT.
2. Load user; if `email_verified` is false → **403** (consumer must verify email first).

### Addresses

Same verification gate. First address becomes default automatically.

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| JWT | Spring Resource Server validates issuer/signature |
| Claims | Controllers require `userId` claim; missing/invalid → **400** |
| Body | `UserAddressRequest` has **no** Jakarta constraints — trimming/null-to-empty in service |
| Business | Unverified user → **403**; missing user → **404** |

No `GlobalExceptionHandler`; controllers return status codes directly.

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **Pub/Sub consumer** | Handler exception → **nack** (message redelivered). Malformed event (no userId) → log + **ack** (drop). Unknown event type → **ack** |
| **Auth** | No HTTP to auth; only JWT validation at request time |

## 6. Redis usage

**None** in this service.
