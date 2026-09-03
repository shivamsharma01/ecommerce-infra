# MCART Diagram and Documentation Errata

**Purpose:** Map each design artifact to what is **Implemented** in code versus **Designed but not currently implemented**, so portfolio materials, interviews, and demos do not contradict the repository.

**Companion document:** [Modernization Assessment](modernization-assessment.md)

### Status labels

| Label | Use when |
|-------|----------|
| **Implemented** | Behavior matches code |
| **Partially implemented** | Core idea exists; details differ |
| **Designed but not currently implemented** | In diagram/docs only |
| **Aspirational** | Future/enterprise target shape |
| **Outdated** | Was intended at design time; code took a different (valid) path |

---

## Draw.io diagrams

### `architecture diagram/architecture-diagram.drawio`

| Diagram element | Status | Code reality |
|-----------------|--------|--------------|
| Web + admin clients | **Implemented** | Angular 20 SSR (`ecommerce-ui`) |
| API gateway / edge auth | **Implemented** | Envoy Gateway + JWT SecurityPolicy + TLS |
| Domain microservices | **Partially implemented** | auth, user, email, product, cart, inventory, payment, order, search, product-indexer — **no** shipment, fraud, or dedicated admin service |
| Event / integration layer | **Partially implemented** | GCP Pub/Sub + outbox (auth, product). **No** Kafka. **No** formal saga engine |
| Saga / workflow coordination | **Designed but not currently implemented** | Checkout is sync orchestration with manual inventory increment on payment fail |
| Transactional DBs | **Implemented** | Postgres, Firestore |
| Search index | **Implemented** | OpenSearch (diagram may say Elasticsearch — same role) |
| Cache / session | **Partially implemented** | Redis in auth + email only. **Not** in search |
| Payment PSP (Razorpay/Stripe) | **Designed but not currently implemented** | Mock payment service |
| Shipment / fraud / logistics | **Aspirational** | Shipping is address on order only |
| Analytics / ML | **Aspirational** | Not built |

**Interview-safe phrasing:** "The architecture diagram shows the **target enterprise shape**; the repository is a **working subset** focused on catalog, cart, checkout, auth, and search indexing."

---

### `architecture diagram/solution-architecture.drawio.xml`

| Diagram element | Status | Code reality |
|-----------------|--------|--------------|
| Cloud CDN / DNS → gateway | **Partially implemented** | DNS → LB → Envoy; CDN not required for demo |
| Auth, Cart, Payment, Email, Search pods | **Implemented** | All deployed in `mcart` namespace |
| Shipment service | **Designed but not currently implemented** | Not in repo |
| Admin service (separate) | **Designed but not currently implemented** | Admin = UI routes + `SCOPE_product.admin` JWT scope |
| Fraud API | **Aspirational** | Not integrated |
| Mobile app | **Aspirational** | Responsive web only |
| Pub/Sub messaging | **Implemented** | See Terraform `pubsub.tf` |

---

### `deployment diagram/deployment diagram.drawio` (+ XML variants)

| Diagram element | Status | Code reality |
|-----------------|--------|--------------|
| GCP VPC + GKE | **Implemented** | Terraform in `ecommerce-infra/terraform/` |
| Regional external LB → NEGs → Envoy | **Implemented** | Envoy Gateway LoadBalancer pattern |
| Region `asia-south1` | **Outdated** | **Implemented:** `asia-south2` |
| Namespaces `gateway` / `core-services` | **Outdated** | **Implemented:** `mcart-gateway` + `mcart` |
| HPA on all deployments | **Designed but not currently implemented** | No HPA manifests in `deploy/k8s/` |
| Multi-zone node spread | **Partially implemented** | Topology spread on some apps; demo often single-zone |
| cert-manager TLS | **Implemented** | `deploy/k8s/gateway/11-certificate.yaml` |

**Interview-safe phrasing:** "HPA and multi-zone in the deployment diagram reflect **design intent**; the demo cluster is cost-optimized."

---

### `cicd diagram/cicd.drawio`

| Diagram element | Status | Code reality |
|-----------------|--------|--------------|
| Per-service GitHub repos | **Implemented** | Separate `.git` per service directory |
| Cloud Build → Artifact Registry | **Implemented** | `cloudbuild.yaml` per service |
| Image tag + SHA | **Implemented** | Cloud Build pushes tagged images |
| SonarQube | **Designed but not currently implemented** | Not in all cloudbuild files |
| Multi-env dev-1/2/3 namespaces | **Designed but not currently implemented** | Often single `mcart` namespace |
| Helm / kubectl deploy | **Implemented** | `ecommerce-infra/deploy/Makefile` |
| Manual prod approval gate | **Partially implemented** | Documented intent; verify per pipeline |

---

### `er diagrams/er-auth.drawio`

| Entity | Status | Code reality |
|--------|--------|--------------|
| AUTH_IDENTITY | **Implemented** | `AuthIdentityEntity` |
| AUTH_USER | **Implemented** | `AuthUserEntity` |
| EMAIL_VERIFICATION | **Implemented** | `EmailVerificationEntity` |

**Note:** Matches Flyway schema in `deploy/helm/mcart-bootstrap/files/auth/`.

---

### `er diagrams/er-user.drawio`

| Finding | Status |
|---------|--------|
| File content mirrors auth ER | **Outdated** |
| User profile in separate service DB | **Implemented** | `user_profile`, `user_addresses` in user service Postgres, populated via Pub/Sub on signup |

**Do not claim:** synchronous `POST /internal/users` on signup. **Implemented path:** auth outbox → `user-signup-events` → `UserSignupSubscriber`.

---

## Sequence diagrams (text files)

### `auth-flow-login.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| POST login → JWT | **Implemented** | Path `/auth/login`; response uses `accessToken` (diagram may say `access_token`) |
| Refresh token | **Implemented** | HttpOnly cookie + Redis store |

---

### `auth-flow-signup.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| Gateway → user service HTTP on signup | **Outdated** | **Implemented:** auth DB write + outbox → Pub/Sub → user subscriber creates profile |
| Verification email | **Partially implemented** | Async via outbox → `email-verification-events`, not direct HTTP to email |

**Correct narrative for portfolio:** "Signup uses the **transactional outbox** so user profile creation and verification email are **reliable and decoupled** from the auth request path."

---

### `checkout-flow.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| Hosted payment (Razorpay) + redirect | **Designed but not currently implemented** | |
| Payment webhook | **Designed but not currently implemented** | |
| Event bus: PaymentSucceeded → order/inventory/cart | **Designed but not currently implemented** | |
| Sync decrement → mock charge → persist → clear cart | **Implemented** | `OrderService.checkout` |
| Inventory increment on payment fail | **Implemented** | Manual compensation only |

**Portfolio label:** Use **Simulated scenario** for payment. Never claim Razorpay integration.

**Recommended replacement diagram:** See Part 5 sequence diagram in [modernization-assessment.md](modernization-assessment.md).

---

### `product-search-flow.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| Redis cache before search | **Designed but not currently implemented** | Search service has no Redis dependency |
| POST search → OpenSearch | **Implemented** | `SearchController` → OpenSearch index `products` |
| Public search at gateway | **Implemented** | Public HTTPRoute |

---

### `search-indexing-sync-flow.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| Outbox → Pub/Sub → indexer → search index | **Implemented** | Product Firestore outbox → `product-events` → product-indexer → OpenSearch |
| Topic name `product.events` | **Outdated** | **Implemented:** `product-events` |
| DLQ `product.events.dlq` | **Designed but not currently implemented** | No DLQ in `terraform/pubsub.tf` |
| Idempotent processing by eventId | **Partially implemented** | Version/`updatedAt` skip in indexer; **eventId omitted** from Pub/Sub payload |
| Elasticsearch branding | **Outdated** | **Implemented:** OpenSearch cluster |

---

### `product-image-upload.txt` / `product-image-read.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| Admin upload to GCS | **Implemented** | Product service + Workload Identity |
| Public read via stored URLs | **Implemented** | No GCS credentials in browser |
| Detailed sequence | **Implemented** | See also `ecommerce-infra/docs/sequence-diagrams/product-image-gcs-flow.md` |

---

### `gateway-install.txt`

| Aspect | Status | Notes |
|--------|--------|-------|
| Gateway API CRDs + Envoy + cert-manager | **Implemented** | `make gateway-install` in infra deploy |

---

## Infra and service markdown docs

### `ecommerce-infra/docs/services/order.md`

| Claim | Status | Correction |
|-------|--------|------------|
| "Full checkout saga" | **Outdated** | Sync orchestrator with one compensation step |
| Payment success + DB failure edge case | **Implemented** | Correctly documented |

---

### `ecommerce-infra/docs/services/payment.md`

| Claim | Status | Correction |
|-------|--------|------------|
| "Idempotency — check implementation" | **Partially implemented** | **No** unique constraint on `order_id`; each charge creates new row |
| Status `COMPLETED` | **Outdated** | **Implemented:** `SUCCESS` / `FAILED` |

---

### `ecommerce-infra/docs/services/product-indexer.md`

| Claim | Status | Correction |
|-------|--------|------------|
| Malformed event "often ack" | **Outdated** | **Implemented:** invalid payload → `processMessage` returns false → **nack** (redelivery) |

---

### `ecommerce-infra/docs/interview-prep-and-demo.md`

| Aspect | Status |
|--------|--------|
| Diagram vs code gap analysis | **Implemented** — accurate; use as secondary reference |
| Lists tracing/DLQ as future | **Still accurate** as of Phase 0 |

---

## Quick reference: what to say in client conversations

| Topic | Say this | Do not say this |
|-------|----------|-----------------|
| Platform type | "Reference hybrid microservices modernization scenario" | "Our production legacy monolith" |
| Checkout | "Synchronous orchestration with known consistency gaps we're modernizing" | "Fully event-driven saga with Kafka" |
| Payment | "Payment provider **simulated for demonstration purposes**" | "Integrated with Razorpay/Stripe" |
| Search | "OpenSearch fed asynchronously by outbox and Pub/Sub" | "Redis-cached Elasticsearch" |
| Messaging | "GCP Pub/Sub" | "Kafka event bus" |
| Signup | "Outbox pattern for reliable profile and email creation" | "Direct sync call to user service" |
| HPA / multi-region | "Documented as design target" | "Running in production with HPA today" |

---

## Maintenance

When implementation catches up to a diagram (e.g. after Phase 3 saga, Phase 6 DLQ):

1. Update the relevant row in this errata from **Designed** → **Implemented**.
2. Update or archive the source diagram in `ecommerce-docs/`.
3. Cross-reference the case study in [modernization-assessment.md](modernization-assessment.md).

---

*Errata version: Phase 0 baseline — September 2026*
