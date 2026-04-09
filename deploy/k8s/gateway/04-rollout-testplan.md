## Parallel rollout test plan (gateway.mcart.space)

### 0) Install + apply

From `ecomm-infra/deploy`:

```bash
make gateway-install
make gateway-apply
```

### 1) Reserve and bind the static IP (recommended)

This repo reserves a **regional** static IP for the Envoy Gateway LoadBalancer (`terraform/google_compute_address.mcart_gateway`).

After `terraform apply`, bind it to the Envoy Service created for your `Gateway` by setting `spec.loadBalancerIP` (or provider-specific annotations) on that Service.

To find the Service name (created by Envoy Gateway controller):

```bash
kubectl get svc -n envoy-gateway-system \
  --selector gateway.envoyproxy.io/owning-gateway-namespace=mcart-gateway,gateway.envoyproxy.io/owning-gateway-name=mcart
```

### 2) DNS cutover (parallel hostname)

If Terraform manages Cloud DNS (`create_cloud_dns_public_zone=true`), it will create:
- `gateway.mcart.space` → the reserved regional IP

Otherwise, create an A record for `gateway.<domain>` pointing at the Envoy LB IP.

### 3) Connectivity checks

Get the gateway IP (as seen by Gateway API):

```bash
GATEWAY_HOST=$(kubectl get gateway -n mcart-gateway mcart -o jsonpath='{.status.addresses[0].value}')
echo "$GATEWAY_HOST"
```

Public endpoints (should succeed without token):

```bash
curl -i -H "Host: gateway.mcart.space" "http://${GATEWAY_HOST}/"
curl -i -H "Host: gateway.mcart.space" "http://${GATEWAY_HOST}/.well-known/openid-configuration"
curl -i -H "Host: gateway.mcart.space" "http://${GATEWAY_HOST}/oauth2/jwks"
```

Protected endpoints (should be `401` without token):

```bash
curl -i -H "Host: gateway.mcart.space" "http://${GATEWAY_HOST}/api/products"
curl -i -H "Host: gateway.mcart.space" "http://${GATEWAY_HOST}/user/me"
```

Protected endpoints (should succeed with token):

```bash
TOKEN="paste_access_token_here"
curl -i -H "Host: gateway.mcart.space" -H "Authorization: Bearer ${TOKEN}" "http://${GATEWAY_HOST}/api/products"
```

### 4) Cutover (main hostname)

Once `gateway.mcart.space` is stable:\n+- add `mcart.space` + `www.mcart.space` to the `HTTPRoute` `hostnames`\n+- move DNS A records from the old Ingress IP to the gateway IP\n+- keep the old Ingress manifests for quick rollback\n+
