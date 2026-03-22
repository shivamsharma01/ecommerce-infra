# ecomm-infra

Terraform (GKE + networking + optional API Gateway/DNS), Helm (data stores + Flyway bootstrap), and Kubernetes app manifests for mcart.

**Start here:** [SETUP.md](./SETUP.md) — what to fill in, commit, keep out of Git, and run only at deploy time.

| Doc | Purpose |
|-----|---------|
| [SETUP.md](./SETUP.md) | Placeholders, secrets, push checklist |
| [docs/gcp-platform-setup.md](./docs/gcp-platform-setup.md) | What Terraform manages |
| [docs/deployment-bootstrap.md](./docs/deployment-bootstrap.md) | Helm + `kubectl` bootstrap order |
| [docs/kubernetes-secrets-production.md](./docs/kubernetes-secrets-production.md) | GSM + External Secrets |
| [docs/production-configuration-reference.md](./docs/production-configuration-reference.md) | Env vars, ConfigMap ↔ Spring, prod checklist |
