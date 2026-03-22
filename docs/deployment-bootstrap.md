# Bootstrap deployments after infrastructure (GKE) is ready

**Prerequisite checklist (what to commit, placeholders, secrets):** [../SETUP.md](../SETUP.md).

**Terraform** provisions the cluster and platform IAM; **Helm** runs stateful data services; **Flyway** runs in **Jobs** after PostgreSQL is reachable; application YAML stays **versioned** and **updated on every merge to `main`**.

## What runs where

| Layer | Tool | Purpose |
|--------|------|---------|
| Cluster, VPC, IAM, Pub/Sub, optional API Gateway | Terraform (`ecomm-infra/terraform`) | Infra only — not app lifecycle |
| PostgreSQL, Redis, Elasticsearch | Helm (Bitnami charts) | Stateful workloads on GKE |
| Schema migrations | Helm chart `deploy/helm/mcart-bootstrap` | `flyway/flyway` **Jobs** + SQL versioned under `files/auth/` and `files/user/` (canonical; not in service JARs) |
| Firestore | GCP managed | No Helm; apps use Workload Identity |
| Microservice Deployments | `kubectl apply` via `ecomm-infra/deploy/Makefile` or GitOps | Runtime pods |

## Kubernetes manifests (central deploy)

**Layout:**

| Location | Holds |
|----------|--------|
| **Service repo** | `Dockerfile`, source, tests — **no** Kubernetes YAML (images only from CI) |
| **Central deploy** (`ecomm-infra/deploy`) | **What the cluster runs**: `k8s/apps/<service>/`, Helm values, Flyway bootstrap chart |

**Why:** One place to run “deploy everything after infra,” one history for production YAML, and service CI only **builds/pushes images**.

**Monorepo (this repo):** Canonical manifests are **`ecomm-infra/deploy/k8s/apps/<service>/`**. `make apps-apply` applies them in order. If you split git repos later, keep this tree in **`ecomm-infra`** (or a dedicated gitops repo) and point Argo CD / Flux at it.

## First-time bootstrap (single operator)

From repo root, with `kubectl` and `helm` pointed at the new cluster:

1. **Schema SQL:** canonical migrations live in `deploy/helm/mcart-bootstrap/files/{auth,user}/*.sql`. Edit there when the schema changes, then `helm upgrade` (see step 4). Local-only: `deploy/scripts/run-flyway-local.sh`.

2. **Install data stores** (copy `*.example.yaml` → `*.yaml`, edit passwords):

   ```bash
   cd ecomm-infra/deploy
   cp helm/values-postgresql.example.yaml helm/values-postgresql.yaml
   cp helm/values-redis.example.yaml helm/values-redis.yaml
   cp helm/values-elasticsearch.example.yaml helm/values-elasticsearch.yaml
   # Edit CHANGEME_* — DB user passwords in initdb must match flyway-install below
   make data-install
   make data-install-redis
   make data-install-es
   ```

3. **Wait for PostgreSQL:**

   ```bash
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n mcart --timeout=300s
   ```

4. **Run Flyway** (uses the same DB user passwords as in `values-postgresql.yaml` initdb). Prefer files to avoid passwords in shell history:

   ```bash
   printf '%s' "$AUTH_PASS" > /tmp/auth.db.pass && chmod 600 /tmp/auth.db.pass
   printf '%s' "$USER_PASS" > /tmp/user.db.pass && chmod 600 /tmp/user.db.pass
   make flyway-install AUTH_DB_PASS_FILE=/tmp/auth.db.pass USER_DB_PASS_FILE=/tmp/user.db.pass
   rm -f /tmp/auth.db.pass /tmp/user.db.pass
   ```

   Or `AUTH_DB_PASS` / `USER_DB_PASS` as before. Jobs use an **initContainer** (`nc` to `5432`) so Flyway does not start until TCP to Postgres succeeds.

5. **Wire ConfigMaps** to cluster DNS names for Postgres/Redis/ES (edit `ecomm-infra/deploy/k8s/apps/<service>/configmap.yaml` or use overlays), create **External Secrets** / GSM secrets, then:

   ```bash
   make apps-apply NS=mcart
   ```

   Optional: `APPLY_ES_SECRETS=0 make apps-apply` skips Elasticsearch ExternalSecrets for `search` and `product-indexer` until GSM secrets exist.

6. **Images:** ensure Deployment manifests reference real Artifact Registry tags (or run `kubectl set image` after CI has pushed images).

**Firestore / product / product-indexer:** no Flyway in this chart; they rely on GCP APIs once Workload Identity is bound.

## Ongoing deploys on merge to `main` (any service)

**Pattern A — Push-based (simplest):** In each service repo, GitHub Actions on `push` to `main`:

1. Build and push image `:sha` (or `:main`).
2. `kubectl set image deployment/NAME NAME=REG/NAME:sha -n mcart` using a **GCP/GitHub OIDC** service account with `container.developer`, **or**
3. `repository_dispatch` to a workflow in **`ecomm-infra`** that runs `kubectl set image` / `helm upgrade` for all or one service.

**Pattern B — GitOps (best at scale):** Service CI only updates a **central config repo** (image tag or Helm values). **Argo CD / Flux** reconciles the cluster. Initial bootstrap still uses the same Helm steps above once; Argo then owns Deployments continuously.

**Pattern C — Monorepo:** One workflow with `paths:` filters: only rebuild services whose folders changed, then patch the single cluster.

Use **`ecomm-infra/.github/workflows/dispatch-deploy-example.yml`** as the reference: it validates `client_payload.service` against an allowlist and passes `service` / `image` through **env vars** before `kubectl set image` (avoids shell injection from `repository_dispatch`).

Service repo calls `gh api repos/ORG/ecomm-infra/dispatches ...` with `event_type: mcart-deploy-image` and payload `{service,image}`.

## Flyway vs app startup

- **Auth** and **user** Spring Boot apps do **not** embed Flyway or `classpath:db/migration`; schema is owned by **`ecomm-infra/deploy/helm/mcart-bootstrap/files/`**.
- After editing SQL there, run **`helm upgrade mcart-bootstrap`** (or `make flyway-install` with passwords) so post-upgrade Flyway Jobs re-run.

### Local PostgreSQL (developer machine)

With Postgres listening on `localhost` and databases/users matching your JDBC URL:

```bash
cd ecomm-infra/deploy
export FLYWAY_URL='jdbc:postgresql://localhost:5432/auth'
export FLYWAY_USER='auth_user'
export FLYWAY_PASSWORD='...'
bash scripts/run-flyway-local.sh auth
# Repeat for `user` with FLYWAY_URL ending in `/user`.
```

## Terraform hook (optional)

You can add a `null_resource` **local-exec** after `google_container_cluster` to run `gcloud get-credentials` + `make data-install`, but that ties infra apply to Helm state and credentials on the machine running Terraform. Usually **keep Terraform for infra** and run **`ecomm-infra/deploy` in CI or manually** once the cluster exists.
