# mcart-ui

Angular storefront with **server-side rendering (SSR)**. Talks to backend APIs through the same host (`mcart.space`) or dev proxies.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Framework | **Angular 20** |
| SSR | Angular SSR (`@angular/ssr`) |
| Styling | Component SCSS (per project) |
| HTTP | `HttpClient` with interceptors for JWT |
| Auth | OAuth2/OIDC via auth service (login, refresh cookie flow) |

## 2. “APIs” (what the UI calls)

The UI does not expose business APIs; it **consumes** gateway-routed services:

| Area | Backend paths (examples) |
|------|---------------------------|
| Auth | `/auth/signup`, `/auth/login`, `/auth/refresh`, `/oauth2/*` |
| User | `/user/me`, `/user/addresses/*` |
| Product | `/api/products`, upload/admin routes |
| Cart | `/cart`, `/cart/items` |
| Order | `/orders/checkout`, `/orders` |
| Search | `/api/search` |

Local dev may use `proxy.conf.json` to forward to cluster or localhost ports.

## 3. Main flows

1. **Browse** — product list/detail, search page → product/search APIs.
2. **Account** — signup/login → auth; profile/addresses after verified JWT.
3. **Cart** — add/update lines (protected JWT).
4. **Checkout** — address selection + `POST /orders/checkout`.
5. **Admin** — product CRUD/upload when JWT includes admin scope.

Route guards enforce login and email-verified state where required.

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Forms | Angular reactive/template validators (required fields, email format) |
| Server | All real validation on microservices; UI shows error responses |

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| Any API | Interceptor may refresh token once; then show error toast/page |
| 401/403 | Redirect to login or verification prompt |
| 5xx | Generic error message; no compensating transactions in UI |

## 6. Redis usage

**None** in the UI (browser local storage / cookies for tokens only).
