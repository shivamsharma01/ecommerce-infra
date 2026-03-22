# GCP platform (Terraform)

**Checklist:** [SETUP.md](../SETUP.md).

## Architecture

`Browser → domain (DNS → mcart_static_ip_address) → HTTPS LB → API Gateway → ingress_https_backend_base_url (GKE Ingress) → Services`

## Terraform creates

VPC, subnet, NAT, GKE, node pool, Pub/Sub (+ optional workload IAM), **global static IP**, **API Gateway** + OpenAPI config + regional gateway + serverless NEG + HTTPS LB + managed cert, optional Cloud DNS.

## After apply

- DNS **A** → **`mcart_static_ip_address`** (registrar or Cloud DNS).
- **`ingress_https_backend_base_url`** ← GKE Ingress HTTPS origin; bump **`api_gateway_config_id`**; **`terraform apply`** again.
- GKE **ManagedCertificate** Active → uncomment **`networking.gke.io/managed-certificates`** on Ingress ([ingress-and-domain.md](./ingress-and-domain.md)).

## Outputs

`mcart_static_ip_address`, `api_gateway_default_hostname`, `api_gateway_https_url`, `kubectl_context_hint`.

## Microservices → IAM

With **`workload_service_accounts`**: auth publishes `user-signup-events`; user subscribes; product + indexer Firestore + Pub/Sub as in Terraform. **`extra_project_iam_members`** for extras.

**Secrets / Helm:** [kubernetes-secrets-production.md](./kubernetes-secrets-production.md), [deployment-bootstrap.md](./deployment-bootstrap.md).

**Providers:** `google` + `google-beta` (`versions.tf`).
