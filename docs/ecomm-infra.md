# ecomm-infra

Infrastructure-as-code and Kubernetes manifests to run the full MCART stack on **GCP**.

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Cloud | Google Cloud Platform |
| IaC | **Terraform** (VPC, GKE, IAM, Firestore indexes, Pub/Sub topics, GCS, etc.) |
| Package mgmt | **Helm** (PostgreSQL, Redis, OpenSearch, Flyway jobs) |
| Orchestration | **Kubernetes** (GKE) — app Deployments, Services, Secrets |
| Ingress | **Envoy Gateway** + Gateway API CRDs + **cert-manager** (TLS) |
| Edge auth | Envoy **SecurityPolicy** JWT validation against auth JWKS |
| Scripts | Makefiles, shell (deploy, destroy-preserve-indexes, flyway) |

## 2. “APIs” (interfaces operators use)

Not HTTP APIs — **operator interfaces**:

| Interface | Purpose |
|-----------|---------|
| `terraform apply/destroy` | Provision/teardown GCP resources |
| `make` targets in `terraform/` and `deploy/` | Wrapped apply, destroy with index preservation, flyway, gateway install |
| `kubectl` / `helm` | Install data plane and app manifests |
| `CLOUD_SHELL_DEPLOYMENT.md` | End-to-end runbook |

Public **customer APIs** are exposed after gateway install at `https://mcart.space` per HTTPRoute definitions in `deploy/k8s/gateway/`.

## 3. Main flows

### Provision (`terraform apply`)

1. VPC + GKE cluster + node pools.
2. IAM / workload identity for services.
3. Firestore database + **composite indexes** (cart queries, product outbox).
4. Pub/Sub topics/subscriptions, GCS buckets, secrets wiring.

### Deploy apps (`deploy/Makefile`)

1. `data-install` — namespace, Helm: Postgres, Redis, OpenSearch.
2. `flyway-install` — schema migrations per DB (auth, user, inventory, payment, order).
3. `apps-install` — microservice Deployments + secrets from `values-*.yaml`.
4. `gateway-install` — Gateway API CRDs, Envoy Gateway, HTTPRoutes, JWT policy, cert-manager Certificate.

### Teardown (`make destroy`)

Runs `destroy-preserve-firestore-indexes.sh`: removes index resources from Terraform state, then destroys other infra so **Firestore indexes can remain** (`lifecycle prevent_destroy` on index resources).

## 4. How requests are validated (edge)

| Layer | Mechanism |
|-------|-----------|
| **Public HTTPRoute** | No JWT; CORS for browser |
| **Protected HTTPRoute** | Envoy validates Bearer JWT (issuer, JWKS from auth) |
| **Scopes** | Some routes require claim scopes (e.g. product admin) |

Services still validate JWT independently.

## 5. When downstream calls fail

| Scenario | Behavior |
|----------|----------|
| Terraform provider errors (API, IPv6) | Documented workarounds in Cloud Shell guide (`sysctl` IPv6) |
| Destroy blocked by firewalls/LB | Manual firewall/LB cleanup scripts |
| Helm hook Flyway job fails | Fix SQL/credentials; re-run `flyway-install` |
| Gateway CRDs missing | `gateway-install` applies standard Gateway API manifest before Envoy |

## 6. Redis usage

Redis is **deployed by Helm** in the cluster (`deploy` data chart) for:

- **auth** — refresh tokens, login lockout, email rate limits
- **email** — order-paid dedupe

Other services do not use Redis. Connection strings and passwords come from Helm values / K8s secrets (`REDIS_PASSWORD`, host `redis-master` or similar per chart).

## Related docs

- [Cloud Shell deployment runbook](../ecomm-infra/CLOUD_SHELL_DEPLOYMENT.md)
- [Gateway README](../ecomm-infra/deploy/k8s/gateway/README.md)
- [System overview](./00-system-overview.md)
