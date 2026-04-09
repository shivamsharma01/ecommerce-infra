# Public edge: Gateway API + Envoy Gateway

Traffic: **browser → regional LB → Envoy (TLS) → Kubernetes Services**. TLS is **cert-manager** + Let’s Encrypt (HTTP-01). JWT at the edge uses **`SecurityPolicy`** (issuer `https://<domain>`, JWKS from auth).

**Prerequisites:** `deploy/` Helm data + `make apps-apply` (apps + secrets). Terraform reserves **`mcart_gateway_static_ip_address`** and optional Cloud DNS A records.

## One-shot install (cluster)

```bash
cd deploy
make gateway-install   # Envoy v1.7.1 install.yaml + GatewayClass + cert-manager Helm (enableGatewayAPI)
make gateway-apply     # Gateway, HTTPRoutes, JWT policy, ClusterIssuer, Certificate, ReferenceGrant
```

Upstream **`install.yaml` does not create a `GatewayClass`**. This repo adds [`00-gatewayclass.yaml`](00-gatewayclass.yaml) (`envoy-gateway`). Do not install Envoy with ad-hoc `gateway-helm` “latest” charts for prod.

## After apply

```bash
kubectl get gatewayclass envoy-gateway
kubectl wait --for=condition=Programmed gateway/mcart -n mcart-gateway --timeout=600s
kubectl get certificate -n mcart-gateway
```

Bind Terraform’s **regional** IP to the Envoy **LoadBalancer** Service in `envoy-gateway-system` (data plane, not the `envoy-gateway` ClusterIP control-plane Service). If label selectors return nothing, pick the `LoadBalancer` Service with ports 80/443:

```bash
GW_IP=$(cd ../../../terraform && terraform output -raw mcart_gateway_static_ip_address)
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=mcart-gateway,gateway.envoyproxy.io/owning-gateway-name=mcart -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[ -z "$ENVOY_SVC" ] && ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name' | head -1)
kubectl -n envoy-gateway-system patch svc "$ENVOY_SVC" -p "{\"spec\":{\"loadBalancerIP\":\"$GW_IP\"}}"
```

DNS: point apex + `www` at that IP (Terraform can manage this with `create_cloud_dns_public_zone=true`).

## Routing summary

See comments in [`02-httproutes.yaml`](02-httproutes.yaml). Roughly: **auth OIDC + UI + public reads/search POST** without Envoy JWT; **mutations, `/user`, `/product-indexer/admin`** require a valid Bearer JWT at the edge (apps still enforce their own rules).

## Cost note

Versus a pure **GCE Ingress** setup you pay for **extra pods** (Envoy data plane, Envoy Gateway controller, cert-manager) on the cluster; the external IP is **regional** instead of global HTTP(S) LB pricing.

## Destroy / teardown

Before `terraform destroy`, delete Gateway-backed Services / namespace `mcart-gateway` and wait for GCP LBs to drain. `terraform/destroy_cleanup.tf` runs [`../../../terraform/scripts/gke_lb_firewall_cleanup.sh`](../../../terraform/scripts/gke_lb_firewall_cleanup.sh) to remove stuck **`k8s-fw-*`** firewall rules.

## Upgrading from old GCE Ingress state

If Terraform state still has `google_compute_global_address.mcart_public`, remove it after DNS uses the gateway IP only:

`terraform state rm 'google_compute_global_address.mcart_public'`

(or the `[0]` instance if your state used `count`).
