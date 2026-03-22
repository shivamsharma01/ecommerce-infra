# Demo cost, preemptible data, CI

## Terraform levers (`terraform.tfvars`)

| Variable | Tighter cost | Comfortable stack (preemptible + ES + JVM) |
|----------|----------------|-----------------------------------------------|
| `regional_cluster` | `false` | `false` (zonal) |
| `zone` | `"<region>-a"` | e.g. `asia-south2-a` |
| `node_machine_type` | `e2-standard-8` | `e2-highmem-4` |
| `node_min_count` / `node_max_count` | `1` / `2` | `2` / `3` |
| `node_preemptible` | `true` | `true` |
| `node_disk_type` | `pd-standard` | `pd-standard` |
| `node_disk_size_gb` | `80` | `≥120` |

Minimal single-node example:

```hcl
regional_cluster = false
zone             = "asia-south2-a"
node_min_count   = 1
node_max_count   = 2
node_machine_type = "e2-standard-8"
node_preemptible  = true
node_disk_type    = "pd-standard"
node_disk_size_gb = 80
```

Fixed baseline regardless of nodes: GKE control plane, **Cloud NAT**, **HTTPS LB + static IP + API Gateway**.

**Preemptible + Postgres/ES:** With Helm **`persistence.enabled: true`**, data is on **PVCs / GCE PDs**, not the node boot disk. Preemption detaches and reattaches volumes; expect **downtime**, not automatic data wipe. Use backups for anything important.

---

## CI (split repos: this workspace)

**`ecomm-infra`** only holds deploy YAML — not service source. Build workflows live in **each service repo** (see `user/.github/workflows/build-push-deploy.yml`): push to `main` → build → GHCR → optional `kubectl` / dispatch.

**Central rollout:** [`.github/workflows/dispatch-deploy-example.yml`](../.github/workflows/dispatch-deploy-example.yml) — `repository_dispatch` with allowlisted `service` + validated `image`; repo secrets: `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA`, `GKE_CLUSTER_NAME`, `GKE_REGION`. [WIF setup](https://github.com/google-github-actions/auth#setup).

A **single monorepo** that contains all `Dockerfile` trees would use one workflow with `paths` filters at that repo’s root (not in `ecomm-infra` alone).

---

## Related

[deployment-bootstrap.md](./deployment-bootstrap.md) · [terraform-first-apply.md](./terraform-first-apply.md) · [ingress-and-domain.md](./ingress-and-domain.md) · [SETUP.md](../SETUP.md)
