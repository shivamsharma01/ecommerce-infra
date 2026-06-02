# Edge gateway, TLS, OAuth2/OIDC, JWT, and Helm

Sequence diagrams for how MCART exposes **`https://mcart.space`**: Gateway API + Envoy, cert-manager TLS, OIDC/JWKS, JWT at the edge, and Helm for cluster data services.

Manifests: `ecomm-infra/deploy/k8s/gateway/` · Install: `make gateway-install` + `make gateway-apply` · Data: `make data-install` etc.

---

## Architecture (static)

```text
                         Internet
                            │
                            ▼
              ┌─────────────────────────────┐
              │  GCP regional LoadBalancer   │  ← Terraform static IP
              │  (Envoy Gateway Service)     │
              └──────────────┬──────────────┘
                             │ :443 TLS (Secret mcart-tls)
                             │ :80  HTTP (ACME challenges + public routes)
                             ▼
              ┌─────────────────────────────┐
              │  Envoy Gateway (data plane)  │
              │  namespace: envoy-gateway-   │
              │  system                      │
              └──────────────┬──────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
  HTTPRoute            HTTPRoute           SecurityPolicy
  mcart-public         mcart-protected     mcart-jwt
  (no JWT at edge)     (JWT required)      → attached to mcart-protected
         │                   │
         └─────────┬─────────┘
                   │ ReferenceGrant → Services in namespace mcart
                   ▼
    auth · mcart-ui · product · cart · order · user · search · …
```

---

## Flow 1 — Gateway API CRDs + Envoy Gateway install

What `make gateway-install` does before any MCART routes exist.

```text
title Gateway install (make gateway-install)
participant Operator
participant Kubernetes API
participant Gateway API CRDs
participant Envoy Gateway Controller
participant cert-manager

Operator -> Kubernetes API: kubectl apply\nGateway API standard-install.yaml v1.1.0

Kubernetes API -> Gateway API CRDs: Register kinds:\nGateway, HTTPRoute,\nGatewayClass, ReferenceGrant, …

Operator -> Kubernetes API: kubectl apply\nEnvoy Gateway install.yaml v1.7.1

Kubernetes API -> Envoy Gateway Controller: Start deployment\n(envoy-gateway-system)

Operator -> Kubernetes API: kubectl apply\n00-gatewayclass.yaml\n(name: envoy-gateway)

Note over Operator,Kubernetes API: GatewayClass links controller\n→ EnvoyProxy mcart-envoy-proxy

Operator -> cert-manager: helm upgrade --install cert-manager\n(enableGatewayAPI=true)

cert-manager -> Kubernetes API: Install cert-manager CRDs +\ncontroller + webhook

Note over Operator,cert-manager: Cluster can now accept\nGateway / HTTPRoute / Certificate resources
```

---

## Flow 2 — cert-manager TLS (Let's Encrypt HTTP-01 via Gateway)

How HTTPS gets a valid certificate for `mcart.space`. Run after `make gateway-apply`.

```text
title TLS certificate issuance (cert-manager + Gateway)
participant Operator
participant cert-manager
participant Let's Encrypt
participant Gateway
participant Envoy
participant Auth Service

Operator -> cert-manager: kubectl apply\nClusterIssuer letsencrypt-gateway\nCertificate mcart-tls

cert-manager -> cert-manager: Create Order + Challenge\nfor mcart.space, www.mcart.space

cert-manager -> Gateway: Create temporary HTTPRoute\n(HTTP-01 solver on listener :80)

Note over Gateway,Envoy: Challenge path MUST stay on :80.\nmcart-public avoids broad /.well-known\nso ACME is not stolen by auth routes.

Let's Encrypt -> Envoy: GET http://mcart.space/.well-known/acme-challenge/{token}

Envoy -> cert-manager: Route challenge → solver pod

cert-manager --> Let's Encrypt: Present challenge response

Let's Encrypt --> cert-manager: ACME authorization OK

cert-manager -> Kubernetes API: Write Secret mcart-tls\n(tls.crt + tls.key)

Gateway -> Gateway: listener https :443\ncertificateRefs → Secret mcart-tls

Note over Envoy: Browser traffic on https://mcart.space\nis now TLS-terminated at Envoy

Auth Service -> Auth Service: (unchanged)\n/.well-known/openid-configuration\nis auth OIDC — not ACME
```

**If issuance fails:** check `kubectl get certificate -n mcart-gateway`, challenge HTTPRoute, and that DNS points at the gateway IP before expecting HTTPS.

---

## Flow 3 — Public request (no JWT at edge)

Example: browse product catalog or load the UI.

```text
title Public request (mcart-public HTTPRoute)
participant Browser
participant GCP LoadBalancer
participant Envoy Gateway
participant HTTPRoute mcart-public
participant Product Service

Browser -> GCP LoadBalancer: GET https://mcart.space/api/products/{id}\n(no Authorization header)

GCP LoadBalancer -> Envoy Gateway: Forward :443 (TLS terminate)

Envoy Gateway -> HTTPRoute mcart-public: Match hostname mcart.space\npath GET /api/products/*\nrule: product-read-public

Note over Envoy Gateway: No SecurityPolicy on mcart-public\nJWT not checked at edge

Envoy Gateway -> Product Service: GET /api/products/{id}\n(HTTP to K8s Service product:80)

Product Service -> Product Service: SecurityConfig:\nGET /api/** permitAll

Product Service --> Browser: 200 OK\nProductResponse JSON
```

Other **public** paths on `mcart-public`: `/auth/*`, `/oauth2/*`, `/.well-known/openid-configuration`, `POST /api/search`, UI `/`, OPTIONS preflights.

---

## Flow 4 — OAuth2 vs OIDC in MCART

**OAuth2** = token issuance framework. **OIDC** = identity layer + discovery + JWKS for verifying JWTs.

### 4a — User login (custom REST; OAuth2-style tokens)

What the Angular UI uses today (`POST /auth/login`).

```text
title User login (REST — UI path)
participant Browser
participant Envoy Gateway
participant Auth Service
participant PostgreSQL
participant Redis

Browser -> Envoy Gateway: POST https://mcart.space/auth/login\n{ identifier, password }\n(withCredentials: true)

Envoy Gateway -> Auth Service: mcart-public → auth:8081

Auth Service -> PostgreSQL: Load auth_identity + user

Auth Service -> Auth Service: 1. Require email verified\n2. Check Redis login lockout\n3. Verify password

Auth Service -> Auth Service: JwtTokenProvider.sign()\niss=https://mcart.space\nclaims: userId, scope, …

Auth Service -> Redis: Store refresh token\n(refresh:{tokenId})

Auth Service --> Browser: 200 OK\n{ accessToken, expiresIn }\n+ Set-Cookie (refresh)

Browser -> Browser: sessionStorage mcart.accessToken\nAttach Bearer on protected API calls
```

### 4b — OIDC discovery + JWKS (used by Envoy and microservices)

Validators never call `/auth/login`; they use **OIDC discovery** to find signing keys.

```text
title OIDC discovery and JWKS (validators)
participant Envoy Gateway
participant Cart Service
participant Auth Service

Note over Envoy Gateway,Cart Service: On startup or cache expiry\n(Spring issuer-uri, Envoy remoteJWKS)

Envoy Gateway -> Auth Service: GET /.well-known/openid-configuration\n(public route)

Auth Service --> Envoy Gateway: {\n  "issuer": "https://mcart.space",\n  "jwks_uri": "https://mcart.space/oauth2/jwks",\n  …\n}

Envoy Gateway -> Auth Service: GET /oauth2/jwks\n(public route)

Auth Service --> Envoy Gateway: { "keys": [ { "kty":"RSA", "kid":"…", "n":"…", "e":"…" } ] }

Cart Service -> Auth Service: Same discovery chain\n(SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI\n= https://mcart.space)

Note over Auth Service: Spring Authorization Server\nalso exposes /oauth2/token, /login\n(OAuth2 authorization code flow —\navailable but UI uses REST login)
```

---

## Flow 5 — Protected request (Bearer JWT at Envoy SecurityPolicy)

Example: view cart after login. **Two layers:** Envoy JWT, then app scopes/claims.

```text
title Protected API (SecurityPolicy + resource server)
participant Browser
participant Envoy Gateway
participant SecurityPolicy mcart-jwt
participant HTTPRoute mcart-protected
participant Cart Service

Browser -> Envoy Gateway: GET https://mcart.space/cart\nAuthorization: Bearer {jwt}

Envoy Gateway -> HTTPRoute mcart-protected: Match GET /cart

HTTPRoute mcart-protected -> SecurityPolicy mcart-jwt: JWT validation required\n(targetRef: mcart-protected)

SecurityPolicy mcart-jwt -> Auth Service: remoteJWKS\nhttps://mcart.space/oauth2/jwks\n(cache 5m)

SecurityPolicy mcart-jwt -> SecurityPolicy mcart-jwt: 1. Parse Bearer token\n2. Verify signature (RSA)\n3. Check iss = https://mcart.space\n4. Check exp not expired

alt JWT invalid or missing
  SecurityPolicy mcart-jwt --> Browser: 401 Unauthorized\n(request never reaches cart)
else JWT valid
  SecurityPolicy mcart-jwt -> HTTPRoute mcart-protected: Strip spoof headers:\nx-mcart-user-id, x-mcart-auth-sub, …

  HTTPRoute mcart-protected -> Cart Service: GET /cart\n(forward Authorization header)

  Cart Service -> Cart Service: OAuth2 resource server:\nvalidate JWT again (issuer + signature)

  Cart Service -> Cart Service: Read userId claim;\nload Firestore cart_items

  Cart Service --> Browser: 200 OK\nCartResponse
end
```

**Protected at edge (mcart-protected):** `/cart`, `/orders`, `/user`, product mutations (`POST/PUT/DELETE /api/products`), `/inventory`, admin `/product-indexer/admin`, etc.

**Still validated in-app:** e.g. `SCOPE_product.admin` on product writes, `emailVerified` on `/user/me`.

---

## Flow 6 — Helm deploy order (data plane)

How MCART uses Helm vs plain `kubectl apply` for apps/gateway.

```text
title Helm data install (make data-install / flyway-install)
participant Operator
participant Helm
participant Kubernetes
participant PostgreSQL Pod
participant Flyway Job

Operator -> Helm: make data-install\nhelm upgrade --install mcart-pg\nbitnami/postgresql\n-f helm/values-postgresql.yaml

Helm -> Kubernetes: Render chart templates;\ncreate StatefulSet, Service, Secret,\ninitdb scripts (DB users)

Kubernetes -> PostgreSQL Pod: Start Postgres;\nrun initdb SQL (auth_user, cart_user, …)

Operator -> Helm: make data-install-redis\nhelm upgrade --install mcart-redis\nbitnami/redis

Operator -> Helm: make data-install-es\nhelm upgrade --install mcart-os\nopensearch/opensearch

Operator -> Helm: make flyway-install\nAUTH_DB_PASS=… USER_DB_PASS=…\nhelm upgrade --install mcart-bootstrap\n(local chart helm/mcart-bootstrap)

Helm -> Kubernetes: Create Flyway Jobs\n(auth, user, inventory, payment, order)

Flyway Job -> PostgreSQL Pod: Run V1__*.sql migrations

Note over Operator,Kubernetes: Microservices + gateway YAML\nare NOT Helm charts here:\nmake apps-apply (kubectl)\nmake gateway-apply (kubectl)

Operator -> Kubernetes: make apps-apply\nkubectl apply deploy/k8s/apps/*

Operator -> Kubernetes: make gateway-apply\nGateway, HTTPRoutes, SecurityPolicy,\nClusterIssuer, Certificate
```

| Component | Tool | Chart / path |
|-----------|------|----------------|
| PostgreSQL | Helm | `bitnami/postgresql` + `helm/values-postgresql.yaml` |
| Redis | Helm | `bitnami/redis` + `helm/values-redis.yaml` |
| OpenSearch | Helm | `opensearch/opensearch` + `helm/values-opensearch.yaml` |
| DB migrations | Helm | `helm/mcart-bootstrap` (Flyway jobs) |
| cert-manager | Helm | `jetstack/cert-manager` (in `gateway-install`) |
| Microservices | kubectl | `deploy/k8s/apps/*` |
| Gateway / JWT / TLS | kubectl | `deploy/k8s/gateway/*` |

---

## Route summary (public vs protected)

| Path (examples) | HTTPRoute | JWT at Envoy |
|-----------------|-----------|--------------|
| `GET /api/products/*` | mcart-public | No |
| `POST /api/search` | mcart-public | No |
| `/auth/login`, `/oauth2/jwks` | mcart-public | No |
| `/` (Angular UI) | mcart-public | No |
| `GET/POST /cart/*` | mcart-protected | **Yes** |
| `POST /orders/checkout` | mcart-protected | **Yes** |
| `POST /api/products/upload` | mcart-protected | **Yes** |
| `GET /user/me` | mcart-protected | **Yes** |

Source: `deploy/k8s/gateway/02-httproutes.yaml`, `03-securitypolicy-jwt.yaml`.

---

## Related files

| Topic | Path |
|-------|------|
| Gateway README | `ecomm-infra/deploy/k8s/gateway/README.md` |
| Install Makefile | `ecomm-infra/deploy/Makefile` (`gateway-install`, `data-install`, `flyway-install`) |
| Auth Authorization Server | `auth/.../AuthorizationServerConfig.java` |
| UI login + Bearer token | `mcart-ui/.../auth.service.ts` |
| Cloud Shell runbook | `ecomm-infra/CLOUD_SHELL_DEPLOYMENT.md` |
