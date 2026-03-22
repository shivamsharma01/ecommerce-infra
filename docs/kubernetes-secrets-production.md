# Kubernetes secrets in production (mcart)

Production clusters should **not** store database passwords, signing keys, or API tokens in Git. This repo keeps only **ConfigMaps** (non-sensitive) and **ExternalSecret** manifests (references to Google Secret Manager — GSM). The Kubernetes `Secret` objects are created at runtime by [External Secrets Operator (ESO)](https://external-secrets.io/).

## Recommended pattern (GKE + GCP Secret Manager + ESO)

```text
Secret values in GSM
        ↓
External Secrets Operator (watches ExternalSecret CRs)
        ↓
Kubernetes Secret (in-namespace, optional rotation)
        ↓
Pod env / volumeMount (via envFrom.secretRef)
```

Alternatives you may use instead of ESO:

- **Secret Manager CSI driver** mounts secrets as volumes without copying into a Kubernetes Secret (good for file-shaped credentials).
- **HashiCorp Vault** with Vault provider for ESO or CSI.
- **Cloud-specific**: AWS Secrets Manager / Azure Key Vault with the matching ESO provider.

## One-time cluster setup

1. Install External Secrets Operator in a dedicated namespace (for example `external-secrets`):

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
   ```

2. Create a small Kubernetes **ServiceAccount** in that namespace (for example `external-secrets`) and bind it to a **GCP service account** with [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity).

3. Grant the GCP service account **`roles/secretmanager.secretAccessor`** on the project (or tighter conditions per secret).

4. Apply a **ClusterSecretStore** that points at GSM. Copy and edit [ecomm-infra/k8s/examples/cluster-secret-store-gcp.yaml](../k8s/examples/cluster-secret-store-gcp.yaml); the name **`gcpsm-cluster`** must match `secretStoreRef` in each service’s `external-secret.yaml`.

## Creating secrets in Google Secret Manager

Use one GSM **secret ID** per value (simplest to reason about), or one JSON secret and ESO `dataFrom.extract` (advanced).

Examples (replace project and values):

```bash
gcloud config set project YOUR_PROJECT_ID

# Auth service
echo -n 'your-db-password' | gcloud secrets create mcart-auth-db-password --data-file=-
echo -n '' | gcloud secrets create mcart-auth-redis-password --data-file=-   # or a real password
echo -n 'your-jwt-signing-secret' | gcloud secrets create mcart-auth-jwt-secret --data-file=-
echo -n 'oauth-client-secret' | gcloud secrets create mcart-auth-oauth2-client-secret --data-file=-
echo -n 'smtp-user' | gcloud secrets create mcart-auth-smtp-username --data-file=-
echo -n 'smtp-app-password' | gcloud secrets create mcart-auth-smtp-password --data-file=-

# User service
echo -n 'user-db-password' | gcloud secrets create mcart-user-db-password --data-file=-

# Search / product-indexer (only if Elasticsearch uses authentication)
echo -n 'elastic' | gcloud secrets create mcart-search-es-username --data-file=-
echo -n 'changeme' | gcloud secrets create mcart-search-es-password --data-file=-
echo -n 'elastic' | gcloud secrets create mcart-product-indexer-es-username --data-file=-
echo -n 'changeme' | gcloud secrets create mcart-product-indexer-es-password --data-file=-
```

Secret IDs must match the `remoteRef.key` values in each service’s `ecomm-infra/deploy/k8s/apps/<service>/external-secret.yaml`.

## Per-service checklist

| Service | ConfigMap | ExternalSecret (GSM keys) | Notes |
|---------|-----------|---------------------------|--------|
| **auth** | `ecomm-infra/deploy/k8s/apps/auth/configmap.yaml` | `mcart-auth-db-password`, `mcart-auth-redis-password`, `mcart-auth-jwt-secret`, `mcart-auth-oauth2-client-secret`, `mcart-auth-smtp-username`, `mcart-auth-smtp-password` | Align `DB_URL`, Redis, issuer URLs with your real cluster DNS / Ingress. |
| **user** | `ecomm-infra/deploy/k8s/apps/user/configmap.yaml` | `mcart-user-db-password` | Prefer **Workload Identity** for Pub/Sub; do not mount JSON keys unless necessary. |
| **product** | `ecomm-infra/deploy/k8s/apps/product/configmap.yaml` | (none in Git) | `product-secrets` is **optional** on the Deployment. Add an ExternalSecret later if you introduce API keys or similar. |
| **search** | `ecomm-infra/deploy/k8s/apps/search/configmap.yaml` | `mcart-search-es-username`, `mcart-search-es-password` | **Only apply** `search/external-secret.yaml` if Elasticsearch requires auth; otherwise skip it to avoid sync errors. |
| **product-indexer** | `ecomm-infra/deploy/k8s/apps/product-indexer/configmap.yaml` | Same pattern as search | Apply `external-secret.yaml` only when ES credentials are required. |
| **mcart-ui** | `ecomm-infra/deploy/k8s/apps/mcart-ui/configmap.yaml` | (optional) | Deployment tolerates missing `mcart-ui-secrets`. Add an ExternalSecret locally if SSR ever needs private tokens. |

## Apply order (example)

```bash
kubectl apply -f ecomm-infra/k8s/examples/cluster-secret-store-gcp.yaml   # once per cluster
kubectl apply -f ecomm-infra/deploy/k8s/apps/auth/configmap.yaml
kubectl apply -f ecomm-infra/deploy/k8s/apps/auth/external-secret.yaml   # after GSM secrets exist
kubectl apply -f ecomm-infra/deploy/k8s/apps/auth/deployment.yaml
kubectl apply -f ecomm-infra/deploy/k8s/apps/auth/service.yaml
```

Repeat the same pattern for other services: ConfigMap → ExternalSecret (if any) → Deployment → Service (+ ServiceAccount for product-indexer first).

## Local or emergency use (not for production Git)

To inject a secret once without GSM (e.g. debugging):

```bash
kubectl create secret generic auth-secrets \
  --from-literal=DB_PASSWORD='...' \
  --from-literal=JWT_SECRET='...' \
  -n YOUR_NAMESPACE
```

Never commit the resulting YAML (`kubectl get secret ... -o yaml`); it is base64-encoded but not encrypted.

## Rotating secrets

1. Add a new **version** of the secret in GSM (`gcloud secrets versions add ...`).
2. ESO will refresh on `refreshInterval` (default in manifests: `1h`), or restart the ESO pod / delete the generated Kubernetes Secret to force a sync.

## Naming and namespaces

- All example manifests use the **default** namespace unless you add `metadata.namespace` or use Kustomize overlays per environment (`dev`, `staging`, `prod`).
- GSM secret IDs can include an environment prefix (for example `mcart-prod-auth-db-password`) if you change `remoteRef.key` to match.
