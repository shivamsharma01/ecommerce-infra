# ecomm-infra

Infrastructure and Kubernetes config for the **mcart** demo on **Google Cloud**: Terraform (VPC, GKE, DNS, IAM), Helm (PostgreSQL, Redis, OpenSearch, Flyway bootstrap), and manifests for **auth**, **user**, **product**, **search**, **product-indexer**, and **mcart-ui**.

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
| [`cloudbuild.yaml`](cloudbuild.yaml) | Cloud Build: `make apps-apply`, `make gateway-install`, `make gateway-apply` |

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

**Cloud Build:** grant the build service account `roles/container.developer`. The trigger runs `cloudbuild.yaml` (apps + gateway). It does **not** apply gitignored secrets.

---

## Operations notes

- **Terraform destroy:** delete gateway/load balancer resources in the cluster first; wait for forwarding rules to clear. [`terraform/destroy_cleanup.tf`](terraform/destroy_cleanup.tf) runs a small script to drop stuck `k8s-fw-*` firewall rules. If you removed `google_compute_global_address.mcart_public` from config, run `terraform state rm` on that resource if it still appears in state from an older revision.
- **Catalog / Firestore demo:** [`deploy/catalog/README.md`](deploy/catalog/README.md).
- **ConfigMap env keys:** Spring maps `SPRING_*` / `APP_*` env vars; see table in older commits or each `configmap.yaml`.

---

## Cost

Terraform defaults favor smaller demos (e.g. preemptible nodes). The **gateway** path adds in-cluster **Envoy + cert-manager** CPU/RAM versus a pure managed Ingress-only edge.
