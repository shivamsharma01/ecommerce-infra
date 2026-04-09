## Gateway API + JWT verification (Envoy Gateway)

This directory adds a **Gateway API**-based edge gateway in front of the `mcart` services, with **Bearer JWT verification** using the `auth` service as the OIDC/JWKS issuer.

### Why Envoy Gateway?

- Works with standard `Gateway` / `HTTPRoute` resources.
- Supports JWT validation via `SecurityPolicy` using the auth server's `/.well-known` + `/oauth2/jwks` endpoints.

### What you get

- **Parallel rollout hostname**: `gateway.<your-domain>` (default intended: `gateway.mcart.space`)
- **Public routes** (no JWT required):
  - `/` → `mcart-ui`
  - `/.well-known/*`, `/oauth2/*`, `/login*`, `/auth/*` → `auth`
- **Protected routes** (JWT required):
  - `/api/products*` → `product`
  - `/api/search*` → `search`
  - `/user*` → `user`
  - `/product-indexer*` → `product-indexer`

### Install Envoy Gateway (cluster-wide)

Envoy Gateway installs CRDs + controllers and creates a `GatewayClass` named `envoy-gateway`.

Pinned version (recommended): **v1.7.1**

```bash
kubectl apply --server-side -f "https://github.com/envoyproxy/gateway/releases/download/v1.7.1/install.yaml"
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

### Apply the MCART Gateway resources

```bash
kubectl apply -f deploy/k8s/gateway/00-namespace.yaml
kubectl apply -f deploy/k8s/gateway/01-gateway.yaml
kubectl apply -f deploy/k8s/gateway/02-httproutes.yaml
kubectl apply -f deploy/k8s/gateway/03-securitypolicy-jwt.yaml
```

Then get the external IP:

```bash
kubectl get gateway -n mcart-gateway mcart -o jsonpath='{.status.addresses[0].value}{"\n"}'
```

### DNS / HTTPS notes

- Envoy Gateway typically creates a **Service type `LoadBalancer`** for the managed Envoy proxy. This uses a **regional** IP (unlike the current GCE Ingress global IP).\n+- This repo adds Terraform for a **parallel DNS record** `gateway.<domain>` to point to the new IP.\n+- TLS termination for this gateway is **not** wired to GKE `ManagedCertificate` (that is Ingress-specific). If you want HTTPS on the Envoy Gateway, use `cert-manager` (Gateway API HTTP-01 solver) or provide a `Secret` with your certificate and enable the HTTPS listener in `01-gateway.yaml`.

