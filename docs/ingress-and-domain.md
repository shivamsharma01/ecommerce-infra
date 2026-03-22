# Domain, Ingress, Gateway, JWT

## Path

`Browser → mcart.store (DNS → mcart_static_ip_address) → HTTPS LB → API Gateway → GKE Ingress (ingress_https_backend_base_url) → Services`

`api_gateway_backend_disable_auth` is Google→backend identity only; **`Authorization`** headers still reach Spring.

## ConfigMaps

| Key area | Value |
|----------|--------|
| auth `AUTH_ISSUER_URI`, `AUTH_VERIFICATION_BASE_URL` | `https://mcart.store` |
| mcart-ui `API_BASE_URL` | `https://mcart.store` |
| Services `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | Same as issuer |

## URL prefixes

auth: `/.well-known/*`, `/oauth2/*`, `/auth/*` · user: `/user/*` · product: `/api/products`, `/v3/api-docs`, `/swagger-ui` · search: `/api/search` · product-indexer: `/product-indexer/*` · mcart-ui: `/` (last in Ingress rules)

## Order

1. `terraform apply` → DNS **A** to **`mcart_static_ip_address`** (can do early; front LB).
2. `make apps-apply` → **`make ingress-apply`**.
3. `kubectl get ingress mcart-store -n mcart` → set **`ingress_https_backend_base_url`**, bump **`api_gateway_config_id`**, `terraform apply`.
4. ManagedCertificate **Active** → uncomment **`networking.gke.io/managed-certificates`**, re-apply Ingress.

**Check:** `dig +short mcart.store A` vs static IP; `kubectl describe managedcertificate mcart-store-cert -n mcart`.

## Related

[terraform-first-apply.md](./terraform-first-apply.md) · [gcp-platform-setup.md](./gcp-platform-setup.md) · [production-configuration-reference.md](./production-configuration-reference.md)
