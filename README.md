# ecomm-infra

Terraform (GKE + networking + optional API Gateway/DNS), Helm (data stores + Flyway bootstrap), and Kubernetes app manifests for mcart.

**Start here:** [SETUP.md](./SETUP.md) — what to fill in, commit, keep out of Git, and run only at deploy time.

| Doc | Purpose |
|-----|---------|
| [SETUP.md](./SETUP.md) | Placeholders, secrets, first push |
| [docs/terraform-first-apply.md](./docs/terraform-first-apply.md) | First Terraform apply |
| [docs/deployment-bootstrap.md](./docs/deployment-bootstrap.md) | Helm, Flyway, `make apps-apply` |
| [docs/ingress-and-domain.md](./docs/ingress-and-domain.md) | DNS, Ingress, Gateway backend, JWT URLs |
| [docs/gcp-platform-setup.md](./docs/gcp-platform-setup.md) | What Terraform creates |
| [docs/demo-cost-and-cicd.md](./docs/demo-cost-and-cicd.md) | Cost tuning, preemptible + data, CI |
| [docs/kubernetes-secrets-production.md](./docs/kubernetes-secrets-production.md) | GSM + External Secrets |
| [docs/production-configuration-reference.md](./docs/production-configuration-reference.md) | Env / ConfigMaps |
