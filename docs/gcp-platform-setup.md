# GCP platform setup (mcart)

**Repo checklist (commit vs secrets, placeholders):** [../SETUP.md](../SETUP.md).

This document describes what the Terraform in `ecomm-infra/terraform` automates for the mcart stack, how it maps to the microservices in this repository, and what still requires manual steps (for example DNS at your registrar).

## Architecture (target)

```text
Browser / client
  → mcart.store (DNS)
  → optional: global HTTPS load balancer + static IP
  → Cloud API Gateway (OpenAPI config)
  → GKE Ingress (HTTPS URL / IP)
  → Services → Pods
```

Pub/Sub and Firestore sit alongside the cluster: topics, subscriptions, and IAM for workload service accounts are created in Terraform when you supply those emails.

## What Terraform automates

| Area | Resources |
|------|-----------|
| APIs | Container, Compute, IAM, logging/monitoring, Artifact Registry, Firestore, Pub/Sub, API Gateway, Service Management/Control, DNS (for optional Cloud DNS) |
| Network + GKE | VPC, subnet, NAT, private GKE cluster, node pool, node service account + node IAM |
| Pub/Sub | Topics `product-events`, `user-signup-events`; subscriptions `product-events-sub`, `user-signup-events-sub` (60s ack deadline) |
| Workload IAM | Topic/subscription-level Pub/Sub roles; `roles/datastore.user` for Firestore where applicable; optional extra project-level bindings |
| Edge | Optional global static IPv4; optional Cloud DNS public zone + A records for `domain_name` and `domain_aliases` |
| API Gateway | API, API config (OpenAPI from `openapi/mcart-gateway.yaml.tftpl`), regional gateway |
| Custom domain + fixed IP | Optional external HTTPS load balancer (EXTERNAL_MANAGED) with managed certificate, serverless NEG → API Gateway |

## What stays manual (unless you change design)

- **Hostinger DNS**: If you do not use Cloud DNS, create an **A record** for `@` (and `www` if needed) pointing at `mcart_static_ip_address` from `terraform output`. Terraform cannot log in to Hostinger.
- **TLS to Ingress**: The OpenAPI template forwards to `ingress_https_backend_base_url`. Prefer a hostname on your Ingress that presents a valid certificate, then set `api_gateway_backend_disable_auth = false` when appropriate.
- **First Kubernetes deploy**: Ingress must exist and expose that URL before API Gateway traffic succeeds end-to-end.
- **OpenAPI revision**: When you change the backend URL or routes, bump `api_gateway_config_id` (for example `v2`) so a new API config revision is created.

## How microservices drive IAM (this repo)

These roles match how the services use GCP clients and the READMEs under each module.

| Service / role | GCP usage | Terraform when `workload_service_accounts` is set |
|----------------|-----------|---------------------------------------------------|
| **auth** | Publishes user signup events to topic `user-signup-events` (`OutboxPublisherJob`, `auth.pubsub.user-signup-topic`) | `roles/pubsub.publisher` on topic `user-signup-events` |
| **user** | Pull subscriber on `user-signup-events-sub` (`UserSignupSubscriber`) | `roles/pubsub.subscriber` on subscription `user-signup-events-sub` |
| **product** | Firestore + publishes to `product-events` | `roles/datastore.user` at project level; `roles/pubsub.publisher` on topic `product-events` |
| **product-indexer** | Firestore reads + subscriber on `product-events-sub` | `roles/datastore.user` at project level; `roles/pubsub.subscriber` on subscription `product-events-sub` |

Legacy or one-off accounts (for example a shared `firestore-java-app` service account that only needed `roles/pubsub.publisher`) can be attached with `extra_project_iam_members` without changing the map above.

For how workloads load **database passwords and other secrets** from **GCP Secret Manager** via External Secrets Operator (and what must never be committed to Git), see [kubernetes-secrets-production.md](./kubernetes-secrets-production.md).

For **Helm (Postgres / Redis / ES), Flyway Jobs, first bootstrap, and CI on `main`**, see [deployment-bootstrap.md](./deployment-bootstrap.md).

## Provider note

Cloud API Gateway resources and the API Gateway serverless NEG use the **`google-beta`** provider. The rest of the stack uses the standard **`google`** provider. Both are declared in `versions.tf`.

## Typical apply flow

1. Copy `terraform/terraform.tfvars.example` to `terraform.tfvars` and set `project_id`, `region`, and any optional blocks.
2. Set `workload_service_accounts` to the **GCP** service account emails bound to your pods via Workload Identity (or to the keys you mount, if you still use JSON keys).
3. After you know the public Ingress URL, set `ingress_https_backend_base_url` (for example `https://api.internal.example.com` or the load balancer hostname Google assigns).
4. To put **mcart.store** on the reserved IP with TLS to the load balancer: set `enable_api_gateway_https_load_balancer = true`, ensure `domain_name` / `domain_aliases` match the managed certificate, then point DNS at the static IP output.
5. Run `terraform init`, `terraform plan`, `terraform apply`.
6. If you enabled Cloud DNS, delegate your registrar (Hostinger or elsewhere) to `cloud_dns_zone_name_servers` from outputs. If not, create A records at the registrar to `mcart_static_ip_address`.

## Useful outputs

- `mcart_static_ip_address` — global IPv4 for DNS when using the HTTPS LB path.
- `api_gateway_default_hostname` — Google-managed gateway hostname (smoke tests without custom domain).
- `api_gateway_https_url` — `https://<domain_name>` when the HTTPS LB is enabled.
- `cloud_dns_zone_name_servers` — nameservers when `create_cloud_dns_public_zone` is true.

## Variables (quick reference)

| Variable | Purpose |
|----------|---------|
| `workload_service_accounts` | Emails for auth, user, product, product_indexer → Pub/Sub + Firestore IAM |
| `extra_project_iam_members` | Map of role → list of members (`serviceAccount:...`, `user:...`, etc.) |
| `ingress_https_backend_base_url` | HTTPS origin for GKE Ingress (no trailing slash) |
| `api_gateway_backend_disable_auth` | OpenAPI `x-google-backend.disable_auth` (often needed for IP backends) |
| `enable_api_gateway_https_load_balancer` | Static IP + managed cert + LB → API Gateway |
| `create_cloud_dns_public_zone` | Managed zone + A records for apex and `domain_aliases` |
| `api_gateway_config_id` | Bump when OpenAPI/backend changes |
