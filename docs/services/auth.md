# auth service

Identity, login, OAuth2/OIDC issuer, email verification, and JWT issuance for the platform.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Security | Spring Security, **Spring Authorization Server** (OAuth2/OIDC), OAuth2 client |
| Database | PostgreSQL (JPA) |
| Cache / session | **Redis** (Spring Data Redis) |
| Messaging | Google Cloud Pub/Sub (outbox publisher) |
| Tokens | jjwt + RSA keys (`auth-jwt-rsa` K8s secret in deploy) |
| Other | MapStruct, Lombok, Bouncy Castle, Actuator |

Default port: **8081**. K8s service port **80** → 8081.

## 2. APIs

### Custom REST (`AuthController`, `EmailVerificationController`)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/auth/signup` | Public | Password registration |
| POST | `/auth/login` | Public | Password login |
| POST | `/auth/social/login` | Public* | Social identity login/provision |
| POST | `/auth/refresh` | Public | New access token (refresh cookie) |
| GET | `/auth/verify-email?token=` | Public | Verify email → **302** redirect to UI |
| POST | `/auth/resend-verification` | Public | Resend verification email (generic response) |
| GET | `/actuator/health/**` | Public | Health |

\*Social login path may require gateway to allow it; in-cluster it is treated like other auth routes.

### OAuth2 / OIDC (Authorization Server)

Standard endpoints under the configured issuer (e.g. `https://mcart.space`), including:

- `/.well-known/openid-configuration`
- `/oauth2/jwks` (public; used by gateway and resource servers)
- `/oauth2/token`, `/login`, etc.

## 3. Main flows

### Password signup

1. Validate request body (`@Email`, `@NotBlank` on password fields).
2. Reject duplicate email → **409**.
3. Create `auth_identity` + `auth_user` in Postgres.
4. Write outbox rows: verification email event + `USER_SIGNUP_COMPLETED` (`verified=false`).
5. Scheduled **outbox job** (every 5s) publishes to Pub/Sub.
6. Return tokens or success per API design (login may require verification first).

### Password login

1. Load identity; require **email verified**.
2. Check **Redis lockout** (`LoginAttemptService`) after too many failures.
3. Verify password; on failure increment Redis counter and optionally lock.
4. Issue **access JWT** + **refresh token** stored in Redis.

### Refresh

1. Read refresh cookie / body.
2. Lookup opaque refresh in Redis; rotate token.
3. Return new access JWT.

### Email verification

1. User clicks link → `GET /auth/verify-email`.
2. Validate token in DB; mark verified; enqueue `EMAIL_VERIFIED` outbox.
3. Redirect to frontend (`verified=1` or error query param).

### Outbox publishing

`OutboxPublisherJob` reads `PENDING` rows from Postgres and publishes to Pub/Sub topics configured in `application.yaml`.

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| HTTP body | Jakarta Bean Validation on signup/resend DTOs (`@Valid`) |
| Login/social | `@Valid` present but fewer field constraints — mostly service checks |
| Business rules | Duplicate email, unverified login, lockout, rate limits → domain exceptions |
| Security filter | OAuth2 AS chain vs resource rules per path |

`GlobalExceptionHandler` maps exceptions to HTTP status (409 conflict, 401 unauthorized, 429 rate limit, etc.).

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **Pub/Sub** (outbox) | Publish error → outbox row marked **FAILED**, `retry_count` incremented; job retries on schedule for PENDING only (failed rows need manual fix or re-queue) |
| **Pub/Sub missing** | Debug log; events stay PENDING until template available |
| **JSON serialize** on verify publish | Can fail verify redirect with generic error |
| **No direct HTTP** to user/email | Integration is async via Pub/Sub only |

Signup/login **succeed in Postgres** even if Pub/Sub is temporarily down; user/email catch up when outbox publishes.

## 6. Redis usage

| Key pattern | Purpose | TTL |
|-------------|---------|-----|
| `auth:login:fail:{authIdentityId}` | Failed login counter | Configurable lock window (e.g. 15 min) |
| `refresh:{tokenId}` | Refresh token metadata (`authIdentityId`, `userId`, issuedAt) | `refresh-token-ttl-seconds` |
| `email_verification:{authIdentityId}` | Rate limit initial verification send | 1 hour |
| `email_verification_resend:{authIdentityId}` | Rate limit resend | 1 hour |

Redis is **required** for refresh tokens and lockout in production config (`deploy/k8s/apps/auth/secret.yaml` → `REDIS_PASSWORD`).

## 7. Pub/Sub topics (outbound)

| Topic | Events |
|-------|--------|
| `user-signup-events` | `USER_SIGNUP_COMPLETED`, `EMAIL_VERIFIED` |
| `email-verification-events` | `SEND_VERIFICATION_EMAIL` |
