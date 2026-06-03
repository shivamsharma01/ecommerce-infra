# MCART — Interview prep, diagram findings, and demo script

Prepared from the **ecommerce** design folder (`architecture`, `deployment`, `ER`, `CI/CD`, sequence diagrams) cross-checked against the **implemented** MCART codebase (`auth`, `user`, `cart`, `order`, `product`, `ecomm-infra`, `mcart-ui`, etc.).

---

## Part 1 — Key findings in Draw.io / diagram documents

### Folder inventory

| File | Type | Purpose |
|------|------|---------|
| `architecture diagram/architecture-diagram.drawio` | Layered logical architecture | Client → Edge → Domain services → Events → Data → External integrations |
| `architecture diagram/solution-architecture.drawio.xml` | Solution view | Clients, API gateway, GKE services, external systems |
| `deployment diagram/deployment diagram.drawio(.xml)` | GCP/GKE deployment | VPC, NEGs, Gateway, HTTPRoute, regional LB, multi-zone nodes |
| `cicd diagram/cicd.drawio` | CI/CD pipeline | GitHub → Cloud Build → Artifact Registry → GKE dev/staging/prod |
| `er diagrams/er-auth.drawio` | ER model | `AUTH_IDENTITY`, `AUTH_USER`, `EMAIL_VERIFICATION` |
| `er diagrams/er-user.drawio` | ER model | Same auth tables (appears duplicated; user profile lives in **user** service DB in code) |
| `sequence diagrams/*.txt` | Text sequences | Login, signup, checkout, search, indexing, GCS images, gateway install |

---

### Architecture diagram (`architecture-diagram.drawio`)

**What it shows (layers):**

1. **Client layer** — web app, mobile, admin  
2. **Edge & access** — traffic management, API routing, auth, rate limiting / threat protection  
3. **Domain services** — catalog/search, cart/checkout, order/payment, inventory/fulfillment, notifications  
4. **Event & integration** — Pub/Sub-style async, domain events, **Saga / workflow coordination**  
5. **Data** — transactional DBs, search indexes, cache/session, analytics (aspirational)  
6. **External** — PSPs, logistics, fraud, email/SMS  

**Implemented in MCART today:**

| Diagram concept | Implementation |
|-----------------|----------------|
| Web + admin clients | **Angular 20 SSR** (`mcart-ui`) at `https://mcart.space` |
| API gateway / edge | **Envoy Gateway** + Gateway API + JWT `SecurityPolicy` + cert-manager TLS |
| Domain microservices | auth, user, email, product, cart, inventory, payment, order, search, product-indexer |
| Event layer | **GCP Pub/Sub** + **transactional outbox** (product, auth) |
| Transactional data | **PostgreSQL** (auth, user, inventory, payment, order), **Firestore** (product, cart) |
| Search index | **OpenSearch** (not Elasticsearch brand; same role) |
| Cache / session | **Redis** (auth refresh/lockout, email dedupe only — **not** search cache) |
| Email external | SMTP via **email** service |
| Payment PSP | **Mock** payment service (no Razorpay/Stripe) |
| Shipment / fraud / ML / logistics | **Not implemented** (future/aspirational on diagram) |

**Interview talking point:** The architecture diagram is the **target enterprise shape**; the repo is a **working subset** focused on catalog, cart, checkout, auth, and search indexing.

---

### Solution architecture (`solution-architecture.drawio.xml`)

**What it shows:**

- Clients (browser, mobile, admin portal) → **Cloud CDN / DNS** → **API gateway** on GKE  
- In-cluster pods: Auth, Cart, Payment, Email, Search, **Shipment**, **Admin**, Frontend  
- External: fraud API, email provider  
- Messaging / data icons (Pub/Sub, DB, cache)

**Key findings vs code:**

| Diagram | Reality |
|---------|---------|
| Separate **Admin service** | Admin is **routes + JWT scope** in `mcart-ui` + product APIs (`SCOPE_product.admin`) |
| **Shipment service** | Not built; shipping is an **address on the order** |
| **Fraud API** | Not integrated |
| **Mobile app** | Responsive web only (no native app) |
| Fraud / CDN | CDN not required for demo; DNS → static LB IP |

---

### Deployment diagram (`deployment diagram.drawio.xml`)

**What it shows:**

- **GCP VPC** with private subnet across zones (`asia-south1-a/b/c` in diagram)  
- **GKE** control plane + node pools + **HPA-enabled** deployments  
- Namespaces: `gateway`, `core-services`  
- **Regional external load balancer** → **Zonal NEGs** → Envoy data plane pods  
- Path: User → DNS `mcart.space` → LB → **Gateway** → **HTTPRoute** → **ClusterIP Service** → pods  
- Gateway **controller** programs GCP LB (logical abstraction note on diagram)

**Key findings vs `ecomm-infra` deploy:**

| Diagram | Actual MCART |
|---------|--------------|
| Region `asia-south1` | **`asia-south2`** (e.g. cluster `mcart-gke`, `asia-south2-a`) |
| Namespaces `gateway` / `core-services` | **`mcart-gateway`** (edge) + **`mcart`** (apps) |
| HPA on all deployments | **No HPA manifests** in repo (diagram is design intent) |
| Multi-zone spread | Topology spread on UI; single-zone cluster common in demo |
| NEG + regional LB | **Correct pattern** for Envoy Gateway `LoadBalancer` Service |

**Interview talking point:** You understand **data plane vs control plane**: Envoy Gateway controller watches `Gateway`/`HTTPRoute`; GCP LB forwards to Envoy pods via NEGs.

---

### CI/CD diagram (`cicd.drawio`)

**What it shows:**

- **Per-service GitHub repos** → Cloud Build: compile, unit tests, SonarQube, Docker build, tag `vX.Y.Z + SHA`  
- Push to **Artifact Registry** — same image promoted across envs  
- CD: dev cluster (multiple namespaces), staging (integration tests), prod (manual approval implied)  
- Deploy via **helm / kubectl**

**Key findings vs repo:**

| Diagram | Actual |
|---------|--------|
| One repo per service | **Separate repos** per microservice + `ecomm-infra` (matches intent) |
| SonarQube | Not evidenced in all `cloudbuild.yaml` files (design target) |
| Multi-env dev-1/2/3 | Demo often **single GKE cluster** + `mcart` namespace |
| Cloud Build updates deployment image | **Yes** — service `cloudbuild.yaml` can patch `ecomm-infra` deployment YAML |
| Infra deploy | Terraform + `make data-install` / `apps-apply` / `gateway-apply` |

---

### ER diagrams

#### `er-auth.drawio`

**Entities:**

- **`AUTH_IDENTITY`** — PK `auth_identity_id`; provider type, identifier, password hash, email, email_verified, login timestamps  
- **`AUTH_USER`** — PK `auth_identity_id`; `user_id`, status (ACTIVE/LOCKED/DELETED), platform admin flags  
- **`EMAIL_VERIFICATION`** — PK `verification_id`; FK to identity; token/expiry fields  

**Matches code:** Yes — see `AuthIdentityEntity`, `AuthUserEntity`, `EmailVerificationEntity` in auth service. Signup creates identity + user row; verification is separate table.

#### `er-user.drawio`

**Finding:** File content mirrors **auth ER** (same `AUTH_USER` / `AUTH_IDENTITY` tables). In the **implemented system**, the **user service** has its own Postgres schema (`users`, `user_addresses`) populated via **Pub/Sub** on signup — not via synchronous `POST /internal/users` as in the old signup sequence diagram.

---

### Sequence diagrams — diagram vs implementation

| Sequence file | Main story | Implementation notes |
|---------------|------------|----------------------|
| `auth-flow-login.txt` | POST login → JWT | **Matches.** Path is `/auth/login`; response uses `accessToken` (+ refresh cookie). Diagram says `access_token` (OAuth2 naming). |
| `auth-flow-signup.txt` | Sync gateway → user service | **Differs.** Auth writes DB + **outbox → Pub/Sub** → user subscriber creates profile. No direct gateway→user HTTP on signup. |
| `checkout-flow.txt` | Hosted Razorpay + webhook + event bus | **Differs.** **Synchronous orchestration** in order service: decrement → mock charge → persist → clear cart. No payment redirect. Compensation via **increment inventory** on payment failure. |
| `product-search-flow.txt` | Redis cache + Elasticsearch | **Partially.** Search hits **OpenSearch** only; **no Redis** in search service. POST `/api/search` is public. |
| `search-indexing-sync-flow.txt` | Outbox → Pub/Sub → indexer → ES | **Matches conceptually.** Product Firestore outbox → `product-events` → product-indexer → OpenSearch. DLQ naming may differ in Terraform. |
| `product-image-upload/read.txt` | GCS + public read | **Matches** implemented flow (see `docs/sequence-diagrams/product-image-gcs-flow.md`). |
| `gateway-install.txt` | CRDs + Envoy + cert-manager | **Matches** `make gateway-install`. |

---

## Part 2 — Interview questions and answers (overall application)

### Architecture and design

**Q1. Give a one-minute overview of MCART.**  
**A:** MCART is a cloud-native e-commerce demo on **GKE**. An **Angular SSR** storefront talks to **Java/Spring microservices** through **Envoy Gateway** at `https://mcart.space`. **PostgreSQL** holds transactional data (auth, user, inventory, orders, payments); **Firestore** holds catalog and carts; **OpenSearch** powers search; **Pub/Sub** integrates signup, catalog changes, and order emails. **Terraform** provisions VPC/GKE/IAM; **Helm** installs Postgres/Redis/OpenSearch; **cert-manager** provides TLS.

**Q2. Why microservices instead of a monolith?**  
**A:** Separates concerns for learning and realistic ops: independent deploy (Cloud Build per repo), different data stores (Firestore for catalog vs Postgres for orders), and clear bounded contexts (auth vs catalog vs checkout). Trade-off: distributed transactions and observability complexity — mitigated with orchestrated checkout and outbox events.

**Q3. What patterns did you use?**  
**A:** API Gateway (Envoy), **OAuth2/OIDC** + JWT resource servers, **transactional outbox**, **orchestrated saga** (checkout in order service), **event-driven** catalog sync (product → inventory + search indexer), **Workload Identity** for GCS/Firestore, **edge JWT validation** + in-app authorization.

**Q4. Diagram shows choreography checkout with webhooks — what did you build?**  
**A:** **Orchestration:** `OrderService.checkout` calls cart, product, inventory, payment sequentially. Payment is **mock** and synchronous. On payment failure after decrement, **order service** calls inventory **increment** to compensate. Hosted PSP + webhook flow in the diagram is a **future** design.

**Q5. Saga vs orchestration — which do you use?**  
**A:** **Orchestration** for checkout (central coordinator in order service). **Choreography** for catalog (product outbox → Pub/Sub → inventory indexer and product-indexer react independently).

---

### Security and auth

**Q6. How does authentication work?**  
**A:** User posts credentials to **`POST /auth/login`**. Auth validates password (Argon2), checks email verified and Redis lockout, issues **RSA-signed JWT** (short TTL) and stores **opaque refresh token** in Redis (HttpOnly cookie). Protected APIs send `Authorization: Bearer …`.

**Q7. Where is JWT validated?**  
**A:** **Twice for protected routes:** (1) Envoy `SecurityPolicy` on `mcart-protected` HTTPRoute using JWKS from `https://mcart.space/oauth2/jwks`; (2) each Spring service as OAuth2 resource server (`issuer-uri: https://mcart.space`). Apps also check scopes (`product.admin`) and claims (`userId`, email verified on user APIs).

**Q8. Why RSA keys in a K8s secret?**  
**A:** Auth signs with **private** key (`auth-jwt-rsa` mounted at `/etc/mcart/jwt`). Verifiers fetch **public** keys via JWKS — no shared secret across services. Supports key rotation and multi-replica auth pods with the same key material.

**Q9. Is mTLS used between services?**  
**A:** **No.** TLS terminates at Envoy; in-cluster traffic is HTTP. Trust is JWT-based, not client certificates.

**Q10. Difference between `/auth/login` and `/oauth2/token`?**  
**A:** `/auth/login` is MCART’s **REST login** for the Angular UI. `/oauth2/token` is the **standard OAuth2 token endpoint** for authorization-code clients registered in Spring Authorization Server. Platform validation uses OIDC discovery + JWKS regardless of which path issued the token.

---

### Data and consistency

**Q11. Why Firestore for product and cart but Postgres for orders?**  
**A:** Catalog/cart fit document model and demo GCP integration; orders need **ACID** transactions, relational reporting, and Flyway migrations. Pragmatic polyglot persistence per bounded context.

**Q12. Cart document primary key?**  
**A:** Firestore doc ID `{userId}__{productId}` in collection `cart_items`. Stores quantity only — **no price** (prices fetched at display/checkout from product service).

**Q13. How does outbox avoid dual-write problems?**  
**A:** Product (and auth) write **business data + outbox row in one transaction**. A scheduled publisher reads pending outbox entries and publishes to Pub/Sub. If Pub/Sub is down, events remain in outbox for retry — no “saved product but lost event” without a record.

**Q14. How is search kept in sync with catalog?**  
**A:** Product mutation → outbox → **`product-events`** topic → **product-indexer** updates OpenSearch. Search is **eventually consistent** (seconds). Admin can **`POST /product-indexer/admin/reindex`** for bulk recovery.

**Q15. Inventory vs product stock quantity?**  
**A:** Product holds `stockQuantity` in Firestore; inventory holds **`availableQty`** in Postgres. On `PRODUCT_CREATED/UPDATED`, inventory **`init` replaces** qty (not additive). Checkout uses **decrement/increment** on inventory rows.

---

### Checkout and orders

**Q16. Walk through checkout.**  
**A:** `POST /orders/checkout` → resolve shipping address (user service) → get cart lines → **fetch current prices** from product API → **decrement inventory** → **mock payment charge** → persist order + line items in Postgres → clear cart → optional **ORDER_PAID** Pub/Sub for email receipt.

**Q17. What if inventory decrement fails?**  
**A:** Checkout **aborts before payment** — exception from inventory (e.g. insufficient stock).

**Q18. What if payment fails after decrement?**  
**A:** **Order service** calls **`POST /inventory/increment`** with the same lines to roll back stock, then returns error to client.

**Q19. What if order DB save fails after successful payment?**  
**A:** Known edge case in demo: mock payment may be recorded while order row missing — in production you’d use idempotent payment keys, order state machine, and reconciliation jobs.

---

### Infrastructure and DevOps

**Q20. Explain Terraform plan/apply/state in your project.**  
**A:** `.tf` files declare desired GCP infra. **`terraform plan`** previews changes; **`apply`** creates/updates resources. **State** maps resource names to GCP IDs. Special script **`make destroy`** removes Firestore indexes from state first so indexes survive teardown.

**Q21. What does Helm deploy vs kubectl?**  
**A:** **Helm:** Postgres, Redis, OpenSearch, Flyway bootstrap chart, cert-manager. **kubectl apply:** microservice Deployments, gateway manifests (`Gateway`, `HTTPRoute`, `SecurityPolicy`, `Certificate`).

**Q22. How is HTTPS configured?**  
**A:** cert-manager **ClusterIssuer** (Let’s Encrypt HTTP-01 via Gateway) → Secret **`mcart-tls`** → referenced by **Gateway** listener :443. Envoy terminates TLS; backends see HTTP.

**Q23. Load balancer role?**  
**A:** GCP **regional external LB** fronts Envoy’s `LoadBalancer` Service (static IP from Terraform). Routes `mcart.space` to Envoy pods via NEGs.

**Q24. Describe CI/CD as implemented.**  
**A:** Push to service repo triggers **Cloud Build**: Docker build → **Artifact Registry** → optional patch of image tag in `ecomm-infra` deployment YAML. Infra changes via Terraform and `make apps-apply`. Diagram’s SonarQube/multi-dev-namespace is aspirational.

**Q25. Workload Identity example?**  
**A:** Product pod uses K8s SA `product` → GCP SA `mcart-product@…` → **`roles/storage.objectAdmin`** on catalog GCS bucket for image upload.

---

### Frontend

**Q26. What is the Angular storefront?**  
**A:** **Angular 20** with **SSR** (Express on port 4000 in K8s). Same-origin API calls to `mcart.space`. JWT in sessionStorage; refresh via cookie. Cart page loads lines from cart API then **hydrates prices** via parallel product GETs.

**Q27. How does admin product upload work?**  
**A:** Multipart `POST /api/products/upload` with JWT `SCOPE_product.admin`. Product service uploads images to **GCS** (Workload Identity), stores public URLs in Firestore, writes outbox for inventory/search sync.

---

### Reliability and ops (conceptual)

**Q28. Define RTO 4h vs RPO 15min.**  
**A:** **RTO:** max time to restore service (e.g. rebuild GKE in 4 hours). **RPO:** max acceptable data loss (restore DB backup from ≤15 minutes ago). MCART demo doesn’t formalize these; you'd cite them in DR discussions.

**Q29. What would you add for production?**  
**A:** HPA/VPA, distributed tracing, dead-letter queues with alerts, real PSP, idempotent checkout, secret rotation, Redis HA, mTLS optional, CDN for static assets, WAF/rate limits at edge (diagram shows intent).

**Q30. Biggest gap between diagrams and code?**  
**A:** Checkout (hosted payment + async events vs sync mock), search Redis cache, shipment/fraud/admin microservices, multi-env CI/CD maturity, HPA, and region/namespace naming on deployment diagram.

---

## Part 3 — Demo script (what to say)

### Before you start (30 seconds)

> “This is **MCART**, a cloud-native e-commerce platform I built on **Google Kubernetes Engine**. Everything runs behind **`https://mcart.space`**: an **Angular** storefront and **Spring Boot microservices**, with **Envoy Gateway** for routing and JWT at the edge, **Let’s Encrypt TLS**, and data split across **PostgreSQL, Firestore, OpenSearch, Redis, and Pub/Sub**. I’ll show the happy path: browse, search, cart, checkout — then briefly touch admin and architecture.”

**Have ready:** browser on `https://mcart.space`, one verified test user, optional admin user, GCP console tab optional.

---

### Act 1 — Public browse (2 min)

1. Open **home / catalog** — no login required.  
   > “Product reads are **public** at the gateway — no JWT. Catalog lives in **Firestore**; images are served from **GCS** public URLs.”

2. Open a **product detail** page.  
   > “The API returns image URLs; the browser loads bytes directly from **Google Cloud Storage**.”

3. Run **search**.  
   > “Search hits **OpenSearch**, fed asynchronously by the **product-indexer** when admins change catalog via **outbox and Pub/Sub**.”

---

### Act 2 — Sign up / login (2 min)

4. **Sign up** or **log in**.  
   > “Auth uses **Spring Authorization Server**. Login returns a short-lived **JWT**; refresh token is an **HttpOnly cookie** stored server-side in **Redis** with rotation.”

5. Mention email verification if demo account needs it.  
   > “Signup publishes events through an **outbox** so the **user profile** and **verification email** are created reliably.”

---

### Act 3 — Cart and checkout (3 min)

6. **Add to cart** (logged in).  
   > “Cart is per-user in **Firestore**. Optional **inventory check** on add. Prices are **not** stored in cart — the UI fetches current product prices when displaying the cart.”

7. Open **cart**, show line totals.  
   > “Angular calls **cart** for quantities, then **product** for names and prices.”

8. **Checkout** with address.  
   > “Checkout is **orchestrated by the order service**: address from user service, prices from product, **decrement inventory**, **mock payment**, persist order in **Postgres**, clear cart. If payment fails, order service **increments inventory** to compensate.”

9. Show **order confirmation / orders list**.  
   > “Order lines store the **price at purchase time** in Postgres.”

---

### Act 4 — Admin (optional, 2 min)

10. Log in as **platform admin** → add or edit product / upload images.  
    > “Writes require **JWT with product.admin scope** at Envoy and in the product service. Images go to **GCS** via **Workload Identity**; catalog change triggers **inventory sync and search indexing**.”

---

### Act 5 — Architecture close (2 min)

11. Show **architecture or deployment diagram** (from ecommerce folder) or `docs/00-system-overview.md`.  
    > “Traffic flows **User → DNS → GCP Load Balancer → Envoy → HTTPRoutes**. Public vs protected routes split browse vs cart/orders. **Terraform** provisions the cluster and IAM; **Helm** installs data services; **cert-manager** handles TLS. Diagrams include some **future** pieces — shipment, fraud, hosted PSP — the running demo focuses on core commerce and event-driven catalog.”

12. If asked about trade-offs:  
    > “I chose **orchestration for checkout** for clarity and **outbox + Pub/Sub for catalog** for reliable async integration. Edge JWT reduces load on services but we still validate claims in each service.”

---

### Demo troubleshooting one-liners

| Issue | What to say |
|-------|-------------|
| 401 on cart | “Need login — protected route at Envoy.” |
| 403 on profile | “Email not verified yet.” |
| Checkout 500 after payment fix | “We fixed order JSON mapping — order persists after charge.” |
| Search empty | “Indexer may be catching up — product-indexer consumes Pub/Sub.” |
| Broken product images | “GCS bucket needs **public read** IAM for browser URLs.” |

---

### Strong closing (15 seconds)

> “MCART demonstrates **production-style patterns** — gateway security, polyglot persistence, outbox events, and scripted infra — in a scope I can deploy end-to-end on GKE. Happy to deep-dive on any service or diagram.”

---

## Quick reference — implemented service map

| Service | Port | Store | Role |
|---------|------|-------|------|
| auth | 8081 | Postgres + Redis | Login, JWT, OIDC, outbox |
| user | 8082 | Postgres | Profile, addresses |
| search | 8083 | OpenSearch | POST /api/search |
| product | 8084 | Firestore + GCS | Catalog CRUD, outbox |
| product-indexer | 8085 | OpenSearch | Index sync |
| inventory | 8086 | Postgres | Stock decrement/increment |
| cart | 8087 | Firestore | Cart lines |
| payment | 8088 | Postgres | Mock charge |
| order | 8089 | Postgres | Checkout orchestration |
| email | 8090 | Redis + SMTP | Pub/Sub emails |
| mcart-ui | 4000 | — | Angular SSR |

---

## Related docs in repo

- [System overview](./00-system-overview.md)
- [Edge gateway / TLS / JWT sequences](./sequence-diagrams/edge-gateway-tls-jwt-helm.md)
- [Product image GCS sequences](./sequence-diagrams/product-image-gcs-flow.md)
- [Cloud Shell deployment](../CLOUD_SHELL_DEPLOYMENT.md)
