# Kubernetes manifests (mcart)

Workload YAML: **`deploy/k8s/apps/<service>/`** (ConfigMap, Deployment, Service, ExternalSecret, ServiceAccount as needed).

**Image placeholders** in `deployment.yaml`: `<ARTIFACT_REGISTRY_URL>`, `<VERSION>` — replace before apply, or use CI / `kubectl set image`.

```bash
cd ecomm-infra/deploy && make apps-apply NS=mcart
```

If Elasticsearch secrets in GSM are not ready: `APPLY_ES_SECRETS=0 make apps-apply` (skips optional ExternalSecrets for `search` and `product-indexer`).

See **[../../SETUP.md](../../SETUP.md)** for placeholders and GitHub push checklist.
