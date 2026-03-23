# ecomm-infra — setup checklist

Use this before your first `terraform apply`, Helm install, or **git push** to GitHub. It lists what belongs in the repo vs what must stay local/secret.

**First Terraform step (minimal):** [docs/terraform-first-apply.md](./docs/terraform-first-apply.md) — start with **`terraform/terraform.tfvars`** (`project_id` + `region` only).

---

## 1. What you **must not** commit (runtime / secrets only)

Create these on your machine or in your CI/CD platform; they are **gitignored** or **never stored in Git**:

| Item | Where it lives |
|------|----------------|
| **`terraform.tfvars`** | `ecomm-infra/terraform/` (gitignored). Create locally with at least `project_id` and `region` (see [docs/terraform-first-apply.md](./docs/terraform-first-apply.md)). |
| **Helm values with passwords** | `ecomm-infra/deploy/helm/values-postgresql.yaml`, `values-redis.yaml`, `values-elasticsearch.yaml` (gitignored). Copy from `*.example.yaml`. |
| **Terraform state** | Remote backend (recommended) or local `*.tfstate` (gitignored). |
| **`deploy/k8s/apps/**/secret.yaml`** | Gitignored. Copy from each `secret.example.yaml`, edit, `kubectl apply` or let `make apps-apply` pick it up. |
| **GitHub Actions secrets** (if you use the dispatch workflow) | Repository secrets: `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA`, `GKE_CLUSTER_NAME`, `GKE_REGION` (names must match `.github/workflows/dispatch-deploy-example.yml`). |
| **`KUBE_CONFIG` / kubeconfig** | Only in CI secrets or your laptop — never commit. |
| **Flyway / DB passwords at install time** | Pass to `make flyway-install` via env vars or `*_PASS_FILE` (see `deploy/Makefile`). |

---

## 2. What to **edit in tracked files** and commit (placeholders)

Replace illustrative values so the repo matches **your** project, domain, and registry. Until you do, manifests are templates.

### 2.1 Kubernetes — `deploy/k8s/apps/*`

| Location | Replace |
|----------|---------|
| **Every `deployment.yaml`** | `<ARTIFACT_REGISTRY_URL>` (e.g. `ghcr.io/myorg` or `REGION-docker.pkg.dev/PROJECT/REPO`) and `<VERSION>` (image tag). |
| **`auth/configmap.yaml`** | `CHANGEME_GCP_PROJECT_ID` → your GCP project ID. URLs like `https://auth.example.com`, `https://app.example.com`, `DB_URL` / `REDIS_HOST` if your Helm **release names** or **namespaces** differ from the sample (`postgresql.auth.svc`, `redis-service.auth.svc`). |
| **`user/configmap.yaml`** | `CHANGEME_GCP_PROJECT_ID`, `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` (must match auth JWT `iss`). JDBC host if not using the sample service DNS. |
| **`product/configmap.yaml`** | `CHANGEME_GCP_PROJECT_ID`. |
| **`product-indexer/configmap.yaml`** | `CHANGEME_GCP_PROJECT_ID`. `SPRING_ELASTICSEARCH_URIS` if your Elasticsearch **service DNS** differs (e.g. Bitnami release `mcart-es` → adjust cluster DNS). |
| **`search/configmap.yaml`** | Same Elasticsearch URI note as product-indexer. |
| **`mcart-ui/configmap.yaml`** | `API_BASE_URL` → your public API / gateway URL. |

### 2.2 Kubernetes **Secrets** (local files, not Git)

| Tracked template | You create (gitignored) |
|------------------|-------------------------|
| **`deploy/k8s/apps/<svc>/secret.example.yaml`** | **`secret.yaml`** in the same folder — see [docs/kubernetes-secrets-production.md](./docs/kubernetes-secrets-production.md). |

### 2.3 Helm **examples** (tracked) — copy then fill **local** copies

The `*.example.yaml` files use placeholders; your real files are gitignored:

| Example (commit) | Local file (do not commit) |
|------------------|----------------------------|
| `deploy/helm/values-postgresql.example.yaml` | `values-postgresql.yaml` — replace every `MY_PASSWORD` with real secrets; initdb SQL must match apps + Flyway. |
| `deploy/helm/values-redis.example.yaml` | `values-redis.yaml` — `MY_PASSWORD`. |
| `deploy/helm/values-elasticsearch.example.yaml` | `values-elasticsearch.yaml` — `MY_PASSWORD` (and tune resources as needed). |

### 2.4 Terraform — `terraform/terraform.tfvars`

Create **`terraform.tfvars`** (gitignored) with at least **`project_id`** and **`region`**. API Gateway and the public HTTPS load balancer are always created; set **`ingress_https_backend_base_url`** after the GKE Ingress exists, then bump **`api_gateway_config_id`** and re-apply.

Optional: `workload_service_accounts`, `create_cloud_dns_public_zone`, `domain_name` / `domain_aliases`, hardening (`master_authorized_networks`, `allow_unrestricted_kubernetes_api = false` with `checks.tf`).

### 2.5 Database schema (tracked)

- **`deploy/helm/mcart-bootstrap/files/auth/*.sql`** and **`files/user/*.sql`** — canonical Flyway migrations; commit when you change schema.
- **Bootstrap platform admin** (`V3__...sql`): user `bootstrap.admin@mcart.internal` / password `ChangeMeAfterFirstDeploy!` (change after deploy). JWT scope `product.admin` gates **product** and **product-indexer** admin HTTP APIs. Regenerate Argon2 hash via `./gradlew generateBootstrapPasswordHash` in the **`auth`** module if you change that password in SQL.

---

## 3. Step-by-step: before first deploy

1. **Install tools:** `terraform` (≥ 1.5), `kubectl`, `helm`, `gcloud` (optional but typical).
2. **Terraform:** `cd ecomm-infra/terraform && terraform init` → create `terraform.tfvars` → `terraform plan` → `terraform apply`.
3. **Cluster credentials:** `gcloud container clusters get-credentials ...` (or your OIDC flow in CI).
4. **Helm data layer:** copy three `values-*.example.yaml` → `values-*.yaml`, edit secrets → from `ecomm-infra/deploy` run `make data-install`, `data-install-redis`, `data-install-es`.
5. **Flyway:** `make flyway-install` with DB passwords matching PostgreSQL initdb (prefer `*_PASS_FILE` — see `deploy/Makefile`).
6. **ConfigMaps / Deployments:** replace placeholders in `deploy/k8s/apps/**` (section 2.1), then `make apps-apply`.
7. **Secrets:** copy each `secret.example.yaml` → `secret.yaml`, fill values (aligned with Helm DB/Redis/ES passwords), then `make apps-apply` again or `kubectl apply -f` those files (see `docs/kubernetes-secrets-production.md`).

---

## 4. Step-by-step: before **pushing this repo to GitHub**

1. **Search for leftovers:** `CHANGEME`, `example.com`, `<ARTIFACT_REGISTRY_URL>`, `<VERSION>` — decide whether you commit **real** project IDs and URLs or keep templates (many teams commit real **non-secret** IDs and domains).
2. **Confirm gitignore:** no `terraform.tfvars`, no `*.tfstate`, no `values-postgresql.yaml` / `values-redis.yaml` / `values-elasticsearch.yaml` with passwords, no `deploy/k8s/apps/**/secret.yaml`.
3. **Commit `terraform/.terraform.lock.hcl`** after `terraform init` (provider versions for reproducible applies).
4. **No kubeconfig, raw `secret.yaml` files, or Helm password files** in the index (`git status`).
5. **Optional:** enable GitHub Actions only after **repository secrets** for the dispatch example are configured; rename/adapt `dispatch-deploy-example.yml` if needed.

---

## 5. What stays **pending** until you actually run things (cannot be “filled” only in Git)

| Pending item | When you resolve it |
|--------------|---------------------|
| Real **Ingress / LB URL** for API Gateway backend | After first GKE Ingress (or LB) exists → set `ingress_https_backend_base_url` in `terraform.tfvars` and bump `api_gateway_config_id`, then re-apply Terraform. |
| **DNS A/AAAA** at registrar | After `terraform output` shows static IP or you use Cloud DNS delegation. |
| **K8s app secrets** | Create `secret.yaml` from examples or `kubectl create secret`; values never belong in Git. |
| **Image tags** in cluster | After CI builds images; use `kubectl set image` or replace `<VERSION>` in YAML. |
| **TLS / managed cert provisioning** | After DNS points at Google LB (can take time). |

---

## 6. Quick placeholder index (search the repo)

```text
MY_PASSWORD             → helm examples (replace before apply); local `values-*.yaml` gitignored  
CHANGEME_GCP_PROJECT_ID → ConfigMaps
<ARTIFACT_REGISTRY_URL> → all app deployment.yaml
<VERSION>               → all app deployment.yaml
*.example.com           → auth/user ConfigMaps (public URLs)
https://api.example.com → mcart-ui ConfigMap
YOUR_PROJECT_ID / YOUR_NAMESPACE → docs examples only (gcloud/kubectl snippets)
```

---
