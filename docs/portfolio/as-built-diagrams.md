# MCART As-Built Architecture Diagrams

**Status:** Phase 0 — **Implemented** baseline only  
**Audience:** CTO / prospective clients  
**Companion:** [modernization-assessment.md](modernization-assessment.md) PART 12  

These diagrams match the repository. Do **not** use aspirational draw.io artifacts (Razorpay, Kafka, HPA everywhere) as “current” without the [diagram errata](diagram-errata.md) label.

Honesty labels: **Implemented** | **Designed but not currently implemented** | **Proposed modernization**

---

## Diagram 1 — System context (**Implemented**)

```mermaid
flowchart LR
  Browser[Browser]
  SMTP[SMTP_provider]
  GCP[GCP_PubSub_Firestore_GCS_GKE]

  subgraph edge [Edge]
    Gateway[Envoy_Gateway_TLS_JWT]
  end

  subgraph identity [Identity]
    Auth[auth]
    User[user]
    Email[email]
  end

  subgraph catalog [Catalog_and_Search]
    Product[product]
    Indexer[product_indexer]
    Search[search]
  end

  subgraph commerce [Commerce]
    Cart[cart]
    Inv[inventory]
    Order[order]
    Pay[payment_mock]
  end

  subgraph storefront [Storefront]
    UI[mcart_ui]
  end

  Browser --> Gateway
  Gateway --> UI
  Gateway --> Auth
  Gateway --> User
  Gateway --> Product
  Gateway --> Search
  Gateway --> Cart
  Gateway --> Order
  Auth --> GCP
  Product --> GCP
  Order --> GCP
  Email --> SMTP
  Indexer --> Search
```

**Talking points:** Payment and email are **not** on public HTTPRoutes (cluster-internal / Pub/Sub). Payment is a **simulated** provider.

---

## Diagram 2 — Container / service map + datastores (**Implemented**)

*Priority diagram #1 for time-limited decks.*

```mermaid
flowchart TB
  subgraph clients [Clients]
    Browser[Browser]
  end

  Gateway[Envoy_Gateway]

  subgraph apps [mcart_namespace]
    UI[mcart_ui]
    Auth[auth]
    User[user]
    Email[email]
    Product[product]
    Indexer[product_indexer]
    Search[search]
    Cart[cart]
    Inv[inventory]
    Order[order]
    Pay[payment]
  end

  subgraph data [Data_plane]
    PG[(PostgreSQL)]
    FS[(Firestore)]
    OS[(OpenSearch)]
    Redis[(Redis)]
    GCS[(GCS)]
    PS[PubSub]
  end

  Browser --> Gateway --> UI
  Gateway --> Auth
  Gateway --> User
  Gateway --> Product
  Gateway --> Search
  Gateway --> Cart
  Gateway --> Order

  Auth --> PG
  Auth --> Redis
  User --> PG
  Inv --> PG
  Pay --> PG
  Order --> PG
  Product --> FS
  Product --> GCS
  Cart --> FS
  Indexer --> OS
  Search --> OS
  Email --> Redis
  Auth --> PS
  Product --> PS
  Order --> PS
  PS --> User
  PS --> Email
  PS --> Indexer
  PS --> Inv
```

| Store | Owners |
|-------|--------|
| PostgreSQL | auth, user, inventory, payment, order |
| Firestore | product, cart |
| OpenSearch | search (read), product-indexer (write) |
| Redis | auth (tokens/lockout), email (order-paid dedupe) |
| GCS | product images |
| Pub/Sub | async integration bus |

---

## Diagram 3 — Sync vs async overlay (**Implemented**)

```mermaid
flowchart TB
  UI[mcart_ui]
  Auth[auth]
  User[user]
  Product[product]
  Search[search]
  Cart[cart]
  Order[order]
  Inv[inventory]
  Pay[payment]
  Email[email]
  Indexer[product_indexer]
  PS[PubSub]

  UI -->|"sync"| Auth
  UI -->|"sync"| User
  UI -->|"sync"| Product
  UI -->|"sync"| Search
  UI -->|"sync"| Cart
  UI -->|"sync"| Order
  Cart -->|"sync"| Inv
  Order -->|"sync"| User
  Order -->|"sync"| Cart
  Order -->|"sync"| Product
  Order -->|"sync"| Inv
  Order -->|"sync"| Pay
  Inv -->|"sync admin"| Product

  Auth -.->|"async outbox"| PS
  Product -.->|"async outbox"| PS
  Order -.->|"async direct publish"| PS
  PS -.-> User
  PS -.-> Email
  PS -.-> Indexer
  PS -.-> Inv
```

**Talking points:** Sync where the customer needs an immediate response. Async for signup fan-out, catalog fan-out, and email. Order → payment remains sync today (Case Study 1 baseline).

---

## Diagram 4 — Checkout sequence as-built (**Implemented**)

*Priority diagram #2 for time-limited decks.*

```mermaid
sequenceDiagram
  participant Client
  participant Order as OrderService
  participant User as UserService
  participant Cart as CartService
  participant Product as ProductService
  participant Inv as InventoryService
  participant Pay as PaymentService
  participant DB as OrderPostgres
  participant PS as PubSub

  Client->>Order: POST /orders/checkout
  Note over Order: @Transactional begins Postgres only
  Order->>User: GET address
  Order->>Cart: GET /cart
  loop each line item
    Order->>Product: GET /api/products/id
  end
  Order->>Order: compute totals
  Order->>Order: orderIdForDownstream equals new UUID
  Order->>Inv: POST /inventory/decrement
  Order->>Pay: POST /payments/charge
  alt payment fails
    Order->>Inv: POST /inventory/increment
    Order-->>Client: 400 Payment failed
  end
  Order->>DB: INSERT orders and order_items
  Order->>Cart: POST /cart/clear
  Order->>User: GET /user/me
  Order->>PS: publish ORDER_PAID
  Note over Order: commit if no uncaught exception
  Order-->>Client: 200 CheckoutResponse
```

**Honesty:** Not a Saga. Compensation exists only for payment failure → inventory increment. Mock payment — *simulated for demonstration purposes.*

---

## Diagram 5 — Checkout failure windows (**Implemented**)

```mermaid
flowchart TB
  Start[Checkout_start]
  Dec[Decrement_inventory]
  Pay[Charge_payment]
  Persist[Persist_order]
  Clear[Clear_cart]
  Event[Publish_ORDER_PAID]
  Done[Success]

  Start --> Dec --> Pay --> Persist --> Clear --> Event --> Done

  Pay -->|fail_or_exception| Comp[Increment_inventory]
  Comp --> Fail400[Client_400]

  Pay -->|SUCCESS_then_persist_fails| Orphan1[Charged_stock_down_no_order]
  Persist -->|clear_throws| Orphan2[TX_rollback_charged_stock_down_cart_intact]
  Clear -->|HTTP_ok_then_crash| Orphan3[Cart_cleared_order_rolled_back]
  Event -->|publish_fails| Soft[Order_ok_email_missing]
```

| Window | Inventory | Payment | Order | Cart | Handled today? |
|--------|-----------|---------|-------|------|----------------|
| Payment FAIL | Restored if increment OK | FAILED or none | None | Intact | Partial |
| Payment OK, persist FAIL | Decremented | SUCCESS | None | Intact | **No** |
| Persist OK, clear FAIL | Decremented | SUCCESS | Rolled back | Intact | **No** |
| Clear OK, crash before commit | Decremented | SUCCESS | Rolled back | **Cleared** | **No** |
| Publish FAIL | Decremented | SUCCESS | Committed | Cleared | Soft (no email) |
| Duplicate checkout | Double decrement risk | Double charge risk | Possible double order | Cleared after first | **No** idempotency |

---

## Diagram 6 — Signup / outbox sequence (**Implemented**)

```mermaid
sequenceDiagram
  participant Client
  participant Auth as AuthService
  participant AuthDB as AuthPostgres
  participant Outbox as OutboxTable
  participant Job as OutboxPublisherJob
  participant PS as PubSub
  participant User as UserService
  participant Email as EmailService

  Client->>Auth: POST /auth/signup
  Auth->>AuthDB: insert identity and user
  Auth->>Outbox: PENDING signup and verification events
  Auth-->>Client: 200 SignupResponse
  Job->>Outbox: poll PENDING every 5s
  Job->>PS: user-signup-events
  Job->>PS: email-verification-events
  Job->>Outbox: mark SENT
  PS->>User: create profile
  PS->>Email: send verification SMTP
```

**Talking points:** Signup does **not** call user service synchronously. Outbox is **Implemented** in auth (Postgres). FAILED outbox rows are not auto-retried (gap).

---

## Diagram 7 — Product → index sequence (**Implemented**)

*Priority diagram #3 for time-limited decks.*

```mermaid
sequenceDiagram
  participant Admin
  participant Product as ProductService
  participant FS as Firestore
  participant Outbox as OutboxEvents
  participant Job as OutboxPublisherJob
  participant PS as PubSub
  participant Indexer as ProductIndexer
  participant OS as OpenSearch
  participant Search as SearchService
  participant Inv as InventoryService

  Admin->>Product: create or update product
  Product->>FS: save ProductDocument
  Product->>Outbox: PENDING PRODUCT_CREATED or UPDATED
  Job->>Outbox: poll PENDING
  Job->>PS: product-events
  PS->>Indexer: product-events-sub
  Indexer->>OS: upsert by productId version
  PS->>Inv: inventory-product-events-sub
  Inv->>Inv: init available_qty from stockQuantity
  Note over Inv: UPDATE can overwrite checkout deductions
  Admin->>Search: POST /api/search
  Search->>OS: query products index
```

**Talking points:** Eventual consistency for search is intentional. Inventory consuming catalog updates is correct for create/delete; overwriting `available_qty` on UPDATE is Case Study 2.

---

## Diagram 8 — Data ownership map (**Implemented**)

```mermaid
flowchart LR
  subgraph authOwn [auth_owns]
    AuthPG[(auth_Postgres)]
  end
  subgraph userOwn [user_owns]
    UserPG[(user_Postgres)]
  end
  subgraph productOwn [product_owns]
    ProductFS[(product_Firestore)]
    GCS[(GCS_images)]
  end
  subgraph invOwn [inventory_owns]
    InvPG[(inventory_Postgres)]
  end
  subgraph orderOwn [order_owns]
    OrderPG[(order_Postgres)]
  end
  subgraph payOwn [payment_owns]
    PayPG[(payment_Postgres)]
  end
  subgraph searchOwn [search_read_model]
    OS[(OpenSearch_products)]
  end
  subgraph cartOwn [cart_owns]
    CartFS[(cart_Firestore)]
  end

  AuthPG -.->|"events"| UserPG
  ProductFS -.->|"events"| OS
  ProductFS -.->|"events"| InvPG
  OrderPG -.->|"ORDER_PAID"| EmailNote[email_side_effect]
```

| Boundary | Rule today |
|----------|------------|
| Auth vs User | Separate DBs; linked by Pub/Sub, not shared schema |
| Product vs Inventory | Separate stores; **do not** treat catalog `stockQuantity` as live stock after checkout starts |
| Order vs Payment | Two IDs: `orderIdForDownstream` vs `orders.order_id` — no FK |
| Search | Read model only; never source of truth for price/stock |

---

## Diagram 9 — Edge security (**Implemented**)

```mermaid
sequenceDiagram
  participant Browser
  participant DNS as DNS_mcart_space
  participant LB as GCP_LoadBalancer
  participant Envoy as Envoy_Gateway
  participant Auth as Auth_JWKS
  participant Svc as Resource_Server

  Browser->>DNS: https://mcart.space
  DNS->>LB: resolve
  LB->>Envoy: TLS terminated
  alt public route
    Envoy->>Svc: forward without JWT
  else protected route
    Envoy->>Auth: fetch JWKS cached
    Envoy->>Envoy: validate Bearer JWT
    Envoy->>Svc: forward with Authorization
    Svc->>Svc: validate JWT issuer scopes emailVerified
  end
```

**Talking points:** Defense in depth — edge JWT **and** service resource servers. S2S calls forward the **user** Bearer token (not mTLS / client credentials). Fold into Case Study 5 platform chapter — not a standalone JWT case study.

---

## Diagram 10 — Deployment as-built (**Implemented**)

```mermaid
flowchart TB
  subgraph gcp [GCP_asia_south2]
    subgraph gke [GKE_mcart_gke]
      subgraph gwNs [mcart_gateway]
        Envoy[Envoy_Gateway]
        Cert[cert_manager_TLS]
      end
      subgraph appNs [mcart]
        Apps[Deployments_Services]
      end
      subgraph dataNs [data_via_Helm]
        PG[PostgreSQL]
        Redis[Redis]
        OS[OpenSearch]
      end
    end
    AR[Artifact_Registry]
    PS[PubSub]
    FS[Firestore]
    GCS[GCS]
  end

  CB[Cloud_Build] --> AR
  AR --> Apps
  Envoy --> Apps
  Apps --> PG
  Apps --> Redis
  Apps --> OS
  Apps --> PS
  Apps --> FS
  Apps --> GCS
```

**Honesty:** No HPA manifests in repo (**Designed but not currently implemented**). Always-on cost ~₹2,000/day — Case Study 5. Namespaces are `mcart` + `mcart-gateway`, not diagram labels `core-services` / `gateway`.

---

## Diagram 11 — Transaction boundary (**Implemented**)

```mermaid
flowchart TB
  subgraph orderTX [Order_service_Transactional]
    SaveOrder[save_orders_and_items]
  end

  subgraph remote [Independent_commits]
    InvTX[Inventory_Postgres_TX]
    PayTX[Payment_Postgres_insert]
    CartFS[Cart_Firestore_clear]
    Pub[PubSub_publish]
  end

  Checkout[checkout_method] --> InvTX
  Checkout --> PayTX
  Checkout --> SaveOrder
  Checkout --> CartFS
  Checkout --> Pub

  Note1[Remote_HTTP_not_in_order_TX]
  Checkout --- Note1
```

**Talking points:** `@Transactional` on checkout only covers order Postgres. Holding the connection across remote HTTP is an anti-pattern and creates failure windows (Diagram 5).

---

## Diagram 12 — Inventory stock writers (**Implemented** problem)

```mermaid
flowchart LR
  Checkout[Checkout_decrement_increment]
  CatalogEvt[PRODUCT_UPDATED_PubSub]
  AdminSync[HTTP_sync_from_catalog]
  Qty[(inventory.available_qty)]

  Checkout -->|"conditional_SQL"| Qty
  CatalogEvt -->|"init_overwrites"| Qty
  AdminSync -->|"init_overwrites"| Qty
```

**Case Study 2 punchline:** Three writers to the same field. Checkout deductions can be clobbered by catalog sync.

---

## Diagram 13 — Pub/Sub topology (**Implemented**)

```mermaid
flowchart LR
  Auth[auth_outbox] --> US[user_signup_events]
  Auth --> EV[email_verification_events]
  Product[product_outbox] --> PE[product_events]
  Order[order_direct] --> OP[order_paid_events]

  US --> UserSub[user_signup_events_sub]
  EV --> EmailVerSub[email_verification_events_sub]
  PE --> IdxSub[product_events_sub]
  PE --> InvSub[inventory_product_events_sub]
  OP --> EmailPaidSub[order_paid_email_sub]

  UserSub --> User[user]
  EmailVerSub --> Email[email]
  IdxSub --> Indexer[product_indexer]
  InvSub --> Inv[inventory]
  EmailPaidSub --> Email
```

**Honesty:** No dead-letter subscriptions in Terraform (**Designed but not currently implemented**).

---

## Diagram 14 — CI/CD as-built (**Implemented** partial)

```mermaid
flowchart LR
  GH[GitHub_per_service_repo] --> CB[Cloud_Build]
  CB --> Test[compile_and_tests]
  Test --> Img[Docker_build]
  Img --> AR[Artifact_Registry]
  AR --> Patch[update_infra_deployment_image]
  Patch --> Apply[make_apps_apply]
  Apply --> GKE[GKE_mcart]
```

**Honesty:** SonarQube and multi-env promotion gates are **Designed but not currently implemented** in all pipelines. One repo per service is **Implemented**.

---

## Deck order suggestion (15 minutes)

1. Diagram 1 — context  
2. Diagram 2 — service map  
3. Diagram 3 — sync vs async  
4. Diagram 4 + 5 — checkout depth  
5. Diagram 7 — search pipeline credibility  
6. Diagram 9 + 10 — security and delivery  
7. Close with Case Study 1 opening sentence from PART 12.4  

---

## Next documentation step

After these diagrams: **Case Study 1 client draft** (resilient checkout) using Diagrams 4, 5, and 11.

See [modernization-assessment.md](modernization-assessment.md) §12.5 ordered immediate steps.
