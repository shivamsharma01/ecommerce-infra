# ecomm-infra

Infrastructure and Kubernetes config for the **mcart** demo on **Google Cloud**: Terraform (VPC, GKE, DNS, IAM), Helm (PostgreSQL, Redis, OpenSearch, Flyway bootstrap), and manifests for **auth**, **user**, **email**, **product**, **search**, **product-indexer**, and **mcart-ui**.

**Default wiring in this repo:** GCP project `ecommerce-491019`, region `asia-south2`, zonal cluster `mcart-gke` (`asia-south2-a`), public hostname `mcart.space`, Artifact Registry `asia-south2-docker.pkg.dev/ecommerce-491019/docker-apps/`.

Public HTTPS uses **Kubernetes Gateway API + Envoy Gateway + cert-manager** (not GCE Ingress). Details: [`deploy/k8s/gateway/README.md`](deploy/k8s/gateway/README.md).

---

## What this repo does

| Area | Purpose |
|------|---------|
| [`terraform/`](terraform/) | VPC, subnet, NAT, GKE, workload service accounts + IAM, Pub/Sub, **regional static IP** for the gateway LB, optional Cloud DNS |
| [`deploy/helm/`](deploy/helm/) | Bitnami PostgreSQL/Redis, OpenSearch, one-shot Flyway bootstrap chart |
| [`deploy/k8s/apps/`](deploy/k8s/apps/) | Deployments, Services, ConfigMaps for each microservice (secrets via gitignored `secret.yaml`) |
| [`deploy/k8s/gateway/`](deploy/k8s/gateway/) | `Gateway`, `HTTPRoute`, JWT `SecurityPolicy`, cert-manager `ClusterIssuer` + `Certificate` |
| [`cloudbuild.yaml`](cloudbuild.yaml) | Cloud Build: `make apps-apply` by default; gateway steps opt-in via `_RUN_GATEWAY_INSTALL` / `_RUN_GATEWAY_APPLY` |

---

## Do not commit

| Item | Notes |
|------|--------|
| `terraform/terraform.tfvars` | Copy from [`terraform/terraform.tfvars.example`](terraform/terraform.tfvars.example) |
| `deploy/helm/values-*.yaml` | Copy from `*.example.yaml` (passwords) |
| `deploy/k8s/apps/*/secret.yaml` | Copy from `secret.example.yaml` |

---

## Quick start (new environment)

1. **APIs:** `cd terraform && ./scripts/enable-apis.sh <project_id>` (once per project).
2. **Terraform:** `terraform init && terraform apply` → note `terraform output -raw mcart_gateway_static_ip_address`.
3. **Cluster:** `gcloud container clusters get-credentials …`
4. **Data:** `cd deploy` — copy Helm values examples, `make data-install data-install-redis data-install-es`, then `make flyway-install` with DB passwords.
5. **Apps:** copy `secret.example.yaml` → `secret.yaml` where needed, `make apps-apply NS=mcart`.
6. **Edge:** `make gateway-install && make gateway-apply`, then bind the regional IP to the Envoy **LoadBalancer** Service (see gateway README). Point DNS at that IP.

**Cloud Build:** grant the build service account `roles/container.developer`. The default trigger only runs `apps-apply` (microservices). `gateway-install` needs extra GKE IAM (cluster roles / webhooks); run it once from an admin context, then set `_RUN_GATEWAY_APPLY=true` on the trigger when you change `deploy/k8s/gateway/`. It does **not** apply gitignored secrets.