# Kubernetes secrets (simple path)

This repo does **not** use External Secrets Operator or GCP Secret Manager for app credentials by default.

## Pattern

1. For each service that needs env secrets, copy **`deploy/k8s/apps/<service>/secret.example.yaml`** → **`secret.yaml`** (same directory).
2. Replace placeholders (`MY_PASSWORD`, `MY_EMAIL`, etc.) with real values. Align **Postgres / Redis / Elasticsearch** passwords with your Helm `values-*.yaml`.
3. **`secret.yaml` is gitignored** — never commit it.
4. From **`ecomm-infra/deploy`**, run **`make apps-apply`**. The Makefile applies **`secret.yaml`** when the file exists; otherwise it prints a hint.

## Optional: `kubectl create secret`

Instead of a file:

```bash
kubectl create secret generic auth-secrets -n mcart \
  --from-literal=DB_PASSWORD='...' \
  --from-literal=REDIS_PASSWORD='...' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Use the **same key names** as in `secret.example.yaml` so Deployments keep working.

## Key names per service

| Service | Secret name | Keys (see `secret.example.yaml`) |
|---------|-------------|-----------------------------------|
| auth | `auth-secrets` | `DB_PASSWORD`, `REDIS_PASSWORD`, `JWT_SECRET`, `OAUTH2_CLIENT_SECRET`, `SPRING_MAIL_USERNAME`, `SPRING_MAIL_PASSWORD` |
| user | `user-secrets` | `SPRING_DATASOURCE_PASSWORD` |
| search | `search-secrets` | `SPRING_ELASTICSEARCH_USERNAME`, `SPRING_ELASTICSEARCH_PASSWORD` |
| product-indexer | `product-indexer-secrets` | same ES keys |

**product** only mounts `product-secrets` if you create it manually (optional); there is no example file.

## Later: Secret Manager / ESO

If you outgrow local `secret.yaml`, you can add External Secrets Operator and GSM yourself; this tree no longer ships those manifests.
