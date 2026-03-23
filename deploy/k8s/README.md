# Kubernetes manifests (mcart)

Workload YAML: **`deploy/k8s/apps/<service>/`** (ConfigMap, Deployment, Service, ExternalSecret, ServiceAccount as needed).

**Images:** `deployment.yaml` is updated by Cloud Build to your Artifact Registry + short SHA. If you apply by hand, set `image:` to a real URI.

```bash
cd ecomm-infra/deploy && make apps-apply NS=mcart
```

If Elasticsearch secrets in GSM are not ready: `APPLY_ES_SECRETS=0 make apps-apply` (skips ExternalSecrets for `search` and `product-indexer`).

**Ingress:** `deploy/k8s/ingress/` — `make ingress-apply`. See **[../docs/ingress-and-domain.md](../docs/ingress-and-domain.md)**.

---

## What still needs your intervention (checklist)

| Area | Action |
|------|--------|
| **GCP project id** | Replace `CHANGEME_GCP_PROJECT_ID` in `auth`, `user`, `product`, `product-indexer` ConfigMaps (and `k8s/examples/cluster-secret-store-gcp.yaml` before apply). |
| **DB / Redis / ES passwords** | Local **`deploy/helm/values-*.yaml`** (gitignored): use strong values; examples use **`MY_PASSWORD`** as the placeholder name. Postgres **superuser**, **auth_user**, **user_user**, **Redis**, and **Elasticsearch** must match what apps and Flyway use. |
| **Service DNS** | Confirm `DB_URL`, `REDIS_HOST`, Elasticsearch URIs in ConfigMaps match your Helm release names and **namespace** (defaults in `auth`/`user` may not match Bitnami service names — adjust if pods cannot connect). |
| **JWT / OAuth** | Issuer and redirect URIs in `auth` ConfigMap should match your public host (e.g. `https://mcart.store`). Resource servers need the same issuer. |
| **Terraform** | `terraform.tfvars`: `project_id`, `region`; after Ingress exists set **`ingress_https_backend_base_url`** and re-apply; DNS → **`mcart_static_ip_address`**. |
| **External Secrets** | Create GSM secrets, install ESO, apply ClusterSecretStore (no placeholders), then `external-secret.yaml` per app. See **[../docs/kubernetes-secrets-production.md](../docs/kubernetes-secrets-production.md)**. |
| **Bootstrap admin** | Flyway SQL `V3__...` platform admin password — change after deploy; regenerate hash in **auth** module if you change it. |
| **Flyway** | `make flyway-install` with passwords matching Postgres initdb. |

**Full reference:** [../../SETUP.md](../../SETUP.md) · [../docs/production-configuration-reference.md](../docs/production-configuration-reference.md)
