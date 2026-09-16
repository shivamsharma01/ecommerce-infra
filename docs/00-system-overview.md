# System overview

MCART is a demo e-commerce platform on **Google Kubernetes Engine (GKE)**. A browser talks to **`https://mcart.space`**, which terminates TLS at **Envoy Gateway** and routes to microservices in the `mcart` namespace.

## High-level architecture

```text
                    ┌─────────────────────────────────────────┐
                    │  Envoy Gateway + cert-manager (TLS)      │
                    │  JWT at edge for protected routes        │
                    └───────────────────┬─────────────────────┘
                                        │
     ┌──────────────┬──────────┬───────┴───────┬──────────┬──────────────┐
     ▼              ▼          ▼               ▼          ▼              ▼
  mcart-ui       auth        product        search      cart          order
  (static/SSR)   user        inventory      product-    payment       email
                 email       (Postgres)     indexer     (mock)
                              │
                    Firestore (product, cart, outbox)
                    OpenSearch (search index "products")
                    Redis (auth, email only)
                    PostgreSQL (auth, user, inventory, payment, order)
                    Pub/Sub (async integration)
```

## Communication patterns

| Pattern | Used for |
|---------|----------|
| **Synchronous HTTP** | UI → services; order checkout → cart, inventory, payment, product, user |
| **Pub/Sub** | Auth/user signup; email verification; product → inventory + product-indexer; order → email receipt |
| **Transactional outbox** | Product and auth publish events reliably after DB/Firestore writes |
| **JWT (OAuth2)** | Auth issues tokens; other services validate as OAuth2 resource servers |

## Data stores by service

| Store | Services |
|-------|----------|
| **PostgreSQL** | auth, user, inventory, payment, order |
| **Firestore** | product (catalog + outbox), cart (line items) |
| **OpenSearch** | search (read), product-indexer (write) |
| **Redis** | auth, email (see service docs) |
| **GCS** | product (catalog images) |

## Main business flows (end-to-end)

1. **Sign up / verify email** — UI → auth → outbox → Pub/Sub → user (profile row) + email (SMTP link) → user verifies → auth publishes `EMAIL_VERIFIED` → user marks verified.
2. **Browse / search** — UI → product (Firestore) or search (OpenSearch index filled by product-indexer).
3. **Cart** — UI → cart (Firestore per user); optional stock check → inventory HTTP.
4. **Checkout** — UI → order → user (address), cart, product (prices), inventory (decrement), payment (mock charge), Postgres (order), cart clear, optional order-paid email via Pub/Sub.
5. **Admin catalog** — UI (admin scope) → product mutations → Firestore + outbox → inventory sync + search index via Pub/Sub.

## Edge security (gateway)

Two HTTPRoutes on `mcart.space`:

- **Public** — OIDC discovery, auth REST, product GETs, POST search, UI static assets, CORS OPTIONS.
- **Protected** — Bearer JWT validated at Envoy (`SecurityPolicy`); cart, orders, user, product writes, inventory, product-indexer admin.

Services still enforce their own JWT rules (scopes, `emailVerified`, admin scopes).

See [Edge gateway, TLS, JWT, Helm sequence diagrams](./sequence-diagrams/edge-gateway-tls-jwt-helm.md) for step-by-step flows.


