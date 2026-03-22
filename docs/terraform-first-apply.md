# First `terraform apply`

## `terraform.tfvars`

In **`ecomm-infra/terraform/`**, create **`terraform.tfvars`** (gitignored). Minimum: **`project_id`**, **`region`**.

Terraform always creates **API Gateway** and the **public HTTPS LB** on **`mcart_static_ip_address`**. **`ingress_https_backend_base_url`** is a placeholder until the GKE Ingress exists ([ingress-and-domain.md](./ingress-and-domain.md)).

## CLI

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

## Validate (optional)

```bash
cd ecomm-infra/terraform
make validate          # or: make validate-docker
```

## Apply

```bash
cd ecomm-infra/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## After apply

```bash
gcloud container clusters get-credentials mcart-gke --location YOUR_REGION_OR_ZONE --project YOUR_GCP_PROJECT_ID
```

Point **DNS A** for your domain → **`terraform output -raw mcart_static_ip_address`**. Then follow **[deployment-bootstrap.md](./deployment-bootstrap.md)** (Helm, Flyway, `make apps-apply`, ingress, second apply for **`ingress_https_backend_base_url`**).

## Related

[demo-cost-and-cicd.md](./demo-cost-and-cicd.md) · [gcp-platform-setup.md](./gcp-platform-setup.md) · [production-configuration-reference.md](./production-configuration-reference.md)
