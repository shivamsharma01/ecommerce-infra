# MCART — Google Cloud Shell deployment & teardown

Project: `ecommerce-491019` · Region: `asia-south2` · Zone: `asia-south2-a` · Cluster: `mcart-gke` · Domain: `mcart.space`

Legend:

| Label | Meaning |
|--------|---------|
| **First time only** | Once per Cloud Shell home disk / new machine / new GCP project |
| **Every redeploy** | Run each full stack bring-up (after destroy or first apply) |
| **Teardown only** | When deleting running infrastructure |
| **Optional** | Skip unless needed |

---

## Variables (every redeploy)

```bash
export MCART=~/mcart/ecomm-infra
export PROJECT=ecommerce-491019
export ZONE=asia-south2-a
export CLUSTER=mcart-gke

gcloud config set project "$PROJECT"
gcloud config get-value project
```

---

## A. First-time Cloud Shell setup

### A1. Clone repository — **First time only**

```bash
mkdir -p ~/mcart && cd ~/mcart
git clone https://github.com/shivamsharma01/ecomm-infra.git ecomm-infra
cd ecomm-infra
```

> If your remote is named `ecommerce-infra`, clone into `ecomm-infra` anyway so `MCART=~/mcart/ecomm-infra` stays consistent.

**Every redeploy:** `cd ~/mcart/ecomm-infra && git pull`

---

### A2. Upload secret & config files — **First time only** (or after Cloud Shell home reset)

Use Cloud Shell **Upload** (or scp). Paths are under `$MCART`:

| File | Purpose |
|------|---------|
| `deploy/helm/values-postgresql.yaml` | Postgres + initdb users (auth, user, inventory, payment, order) |
| `deploy/helm/values-redis.yaml` | Redis password |
| `deploy/helm/values-opensearch.yaml` | OpenSearch config |
| `deploy/k8s/apps/auth/secret.yaml` | DB, Redis, JWT, OAuth |
| `deploy/k8s/apps/user/secret.yaml` | User DB password |
| `deploy/k8s/apps/email/secret.yaml` | SMTP + verification URL |
| `terraform/terraform.tfvars` | Optional if you changed defaults from `terraform.tfvars.example` |

**Optional — only when attaching to infra that already exists in GCP (not a greenfield apply):**

| File | Purpose |
|------|---------|
| `terraform/terraform.tfstate` | Current Terraform state from the machine that last applied |
| `terraform/terraform.tfstate.backup` | Backup of same |

Do **not** upload an old `tfstate` after a successful `make destroy` on this project; use fresh `terraform apply` instead.

**Every redeploy:** Skip upload if files are still in `~/mcart/ecomm-infra/…` from a previous session.

---

### A3. tmux for long runs — **Optional** (recommended first time)

```bash
sudo apt-get update -qq && sudo apt-get install -y -qq tmux 2>/dev/null || true
tmux new -s deploy
# Detach: Ctrl+b then d · Reattach: tmux attach -t deploy
```

---

### A4. Verify tools — **First time only** (or if versions look wrong)

```bash
gcloud version
terraform version    # need >= 1.5
helm version
kubectl version --client
make --version
```

If Terraform is too old:

```bash
wget -q https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
unzip -o terraform_1.9.8_linux_amd64.zip && mv terraform ~/bin/ && terraform version
```

---

### A5. Enable GCP APIs — **First time only** (per GCP project)

```bash
cd "$MCART/terraform"
./scripts/enable-apis.sh "$PROJECT"
```

---

### A6. GitHub token for Cloud Build — **First time only** (if using Cloud Build to bump image tags)

Create a fine-grained PAT: GitHub → Settings → Developer settings → fine-grained token → repo `ecomm-infra` → read + write.

```bash
gcloud config set project "$PROJECT"

# Replace with your PAT — never commit the real token
printf '%s' 'YOUR_GITHUB_PAT' | gcloud secrets versions add github-token --data-file=-

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')

gcloud secrets add-iam-policy-binding github-token \
  --project="$PROJECT" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Every redeploy:** Only repeat if the token expired (Cloud Build fails updating manifests).

---

## B. Deploy infrastructure & applications — **Every redeploy**

### B0. Preflight — **Every redeploy**

```bash
export MCART=~/mcart/ecomm-infra
export PROJECT=ecommerce-491019
export ZONE=asia-south2-a
export CLUSTER=mcart-gke

gcloud config set project "$PROJECT"

curl -sI --connect-timeout 10 https://compute.googleapis.com | head -1
curl -sI --connect-timeout 10 https://firestore.googleapis.com | head -1
```

---

### B1. Terraform (VPC, GKE, IAM, Pub/Sub, static IP, Firestore index/doc) — **Every redeploy** after destroy

```bash
cd "$MCART/terraform"

unset GOOGLE_APPLICATION_CREDENTIALS

gcloud auth application-default login

terraform init
terraform plan -out=tfplan
terraform apply tfplan

terraform output -raw mcart_gateway_static_ip_address
```

**If you kept Firestore indexes** from a previous `make destroy` (see teardown), `apply` may report indexes already exist. Import them (IDs from console → Firestore → Indexes):

```bash
terraform import google_firestore_index.cart_items_user_updated_at \
  'projects/ecommerce-491019/databases/(default)/collectionGroups/cart_items/indexes/INDEX_ID'

terraform import google_firestore_index.product_outbox_events_status_created_at \
  'projects/ecommerce-491019/databases/(default)/collectionGroups/outbox_events/indexes/INDEX_ID'
```

**Skip entire section** if GKE/VPC still exist and you only refresh apps (jump to B2).

---

### B2. Cluster credentials — **Every redeploy**

```bash
gcloud container clusters get-credentials "$CLUSTER" \
  --location "$ZONE" --project "$PROJECT"

kubectl get nodes
kubectl get ns
```

---

### B3. Data layer (Postgres, Redis, OpenSearch) — **Every redeploy** (fresh cluster / empty `mcart` ns)

```bash
cd "$MCART/deploy"

test -f helm/values-postgresql.yaml && test -f helm/values-redis.yaml && test -f helm/values-opensearch.yaml

make data-install data-install-redis data-install-es

# Namespace mcart exists after data-install; then JWT secret (once per cluster)
make ensure-auth-jwt-secret

kubectl -n mcart get pods
# Wait until mcart-pg-*, mcart-redis-*, opensearch-* are Running
```

**Skip** if Helm releases already exist and PVCs should be kept (app-only refresh → go to B5).

---

### B4. Flyway (DB migrations) — **Every redeploy** on **new** Postgres PVC

Passwords must match `CREATE USER …` in `helm/values-postgresql.yaml`.

```bash
cd "$MCART/deploy"

grep "CREATE USER" helm/values-postgresql.yaml

export AUTH_PASS='MY_PASSWORD'
export USER_PASS='MY_PASSWORD'
export INVENTORY_PASS='MY_PASSWORD'
export PAYMENT_PASS='MY_PASSWORD'
export ORDER_PASS='MY_PASSWORD'

printf '%s' "$AUTH_PASS" > /tmp/auth.db.pass && chmod 600 /tmp/auth.db.pass
printf '%s' "$USER_PASS" > /tmp/user.db.pass && chmod 600 /tmp/user.db.pass
printf '%s' "$INVENTORY_PASS" > /tmp/inventory.db.pass && chmod 600 /tmp/inventory.db.pass
printf '%s' "$PAYMENT_PASS" > /tmp/payment.db.pass && chmod 600 /tmp/payment.db.pass
printf '%s' "$ORDER_PASS" > /tmp/order.db.pass && chmod 600 /tmp/order.db.pass

make flyway-install \
  AUTH_DB_PASS_FILE=/tmp/auth.db.pass \
  USER_DB_PASS_FILE=/tmp/user.db.pass \
  INVENTORY_DB_PASS_FILE=/tmp/inventory.db.pass \
  PAYMENT_DB_PASS_FILE=/tmp/payment.db.pass \
  ORDER_DB_PASS_FILE=/tmp/order.db.pass

rm -f /tmp/*.db.pass
unset AUTH_PASS USER_PASS INVENTORY_PASS PAYMENT_PASS ORDER_PASS
```

Flyway jobs are removed after success (Helm hook). Empty `kubectl get jobs | grep flyway` is normal.

**Skip** if databases were migrated already on the same PVC.

---

### B5. Deploy applications — **Every redeploy**

```bash
cd "$MCART/deploy"

test -f k8s/apps/auth/secret.yaml && test -f k8s/apps/user/secret.yaml

make apps-apply NS=mcart

kubectl get pods -n mcart
kubectl get deploy -n mcart
```

Sanity checks:

```bash
kubectl exec -n mcart deploy/product -c product -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://auth:8081/actuator/health/liveness

kubectl exec -n mcart deploy/product -c product -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://search:80/health/readiness
```

Expect `200`. Fix `ImagePullBackOff` via Artifact Registry access / image tags in deployments.

---

### B6. Gateway + cert-manager — **Every redeploy** on a **new** cluster

```bash
cd "$MCART/deploy"

make gateway-install
make gateway-apply

kubectl get gateway -n mcart-gateway
kubectl get httproute -n mcart-gateway
kubectl get securitypolicy -n mcart-gateway
kubectl get gatewayclass envoy-gateway
```

**Skip** if gateway/cert-manager already installed and only app manifests changed.

---

### B7. Bind static IP to Envoy LoadBalancer — **Every redeploy** (new gateway / new LB)

```bash
GW_IP=$(cd "$MCART/terraform" && terraform output -raw mcart_gateway_static_ip_address)
echo "Gateway IP: $GW_IP"

ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=mcart-gateway,gateway.envoyproxy.io/owning-gateway-name=mcart \
  -o jsonpath='{.items[0].metadata.name}')

if [ -z "$ENVOY_SVC" ]; then
  ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system -o json | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(next((i['metadata']['name'] for i in d['items'] if i['spec'].get('type')=='LoadBalancer'),''))")
fi

echo "Service: $ENVOY_SVC"

kubectl -n envoy-gateway-system patch svc "$ENVOY_SVC" \
  -p "{\"spec\":{\"loadBalancerIP\":\"$GW_IP\"}}"

kubectl -n envoy-gateway-system get svc "$ENVOY_SVC" -w
# Ctrl+C when EXTERNAL-IP is assigned
```

**DNS — First time or when IP changes:** Point `mcart.space` and `www.mcart.space` A records to `$GW_IP` at your registrar (unless Terraform manages Cloud DNS).

---

### B8. Validate HTTPS and JWT — **Every redeploy**

```bash
kubectl -n mcart-gateway get certificate,secret
kubectl -n mcart-gateway describe certificate mcart-tls

curl -i https://mcart.space/.well-known/openid-configuration
curl -i https://mcart.space/oauth2/jwks
curl -i https://mcart.space/

curl -i https://mcart.space/api/products    # expect 401 without token
curl -i https://mcart.space/user

# With token:
curl -i -H "Authorization: Bearer YOUR_TOKEN" https://mcart.space/api/products
```

---

## C. Reference (not deployment steps)

### Bootstrap admin (Postgres seed user)

- Email: `bootstrap.admin@mcart.internal`
- Password: `ChangeMeAfterFirstDeploy!` (change after first login in prod)

### Browser devtools

- `crypto.randomUUID()` — generate a client-side UUID in the browser console when needed.

### Firestore data cleanup (optional, does not delete indexes)

To clear cart/outbox **documents** without dropping composite indexes: delete docs in the Firestore console (`cart_items`, `outbox_events`) or run `terraform/scripts/cart_firestore_destroy_cleanup.py` with `pip install google-cloud-firestore`. Leave `products` if you want to keep the catalog.

---

## D. Teardown — **Teardown only**

Use this flow instead of bare `terraform destroy` so **Firestore composite indexes stay in GCP** (faster next redeploy). See `terraform/scripts/destroy-preserve-firestore-indexes.sh`.

### D0. Preflight — **Teardown only**

```bash
export MCART=~/mcart/ecomm-infra
export PROJECT=ecommerce-491019
export ZONE=asia-south2-a
export CLUSTER=mcart-gke

gcloud config set project "$PROJECT"

curl -sI --connect-timeout 10 https://compute.googleapis.com | head -1
curl -sI --connect-timeout 10 https://firestore.googleapis.com | head -1
```

**Optional:** `pip3 install --user google-cloud-firestore` (for `cart_items` document cleanup during destroy).

---

### D1. Kubernetes & edge — **Teardown only** (skip if cluster already deleted)

```bash
gcloud container clusters get-credentials "$CLUSTER" \
  --location "$ZONE" --project "$PROJECT"

kubectl delete namespace mcart --timeout=120s --ignore-not-found

cd "$MCART/deploy"
kubectl delete -f k8s/gateway/ --ignore-not-found
kubectl delete namespace mcart-gateway --timeout=120s --ignore-not-found
kubectl delete namespace envoy-gateway-system --timeout=120s --ignore-not-found
kubectl delete gatewayclass envoy-gateway --ignore-not-found

helm uninstall cert-manager -n cert-manager --ignore-not-found
kubectl delete namespace cert-manager --timeout=120s --ignore-not-found

kubectl delete --ignore-not-found -f \
  "https://github.com/envoyproxy/gateway/releases/download/v1.7.1/install.yaml"
```

---

### D2. Wait for load balancers & firewalls — **Teardown only**

Wait 5–15 minutes, then:

```bash
gcloud compute forwarding-rules list --project="$PROJECT" --regions=asia-south2
gcloud compute forwarding-rules list --project="$PROJECT" --global

cd "$MCART/terraform"
export PROJECT_ID="$PROJECT" NETWORK_NAME=mcart-vpc
bash scripts/gke_lb_firewall_cleanup.sh
```

If VPC delete still fails, delete any remaining `k8s-*` firewalls on `mcart-vpc` manually.

---

### D3. Terraform destroy (preserves Firestore indexes) — **Teardown only**

```bash
cd "$MCART/terraform"

unset GOOGLE_APPLICATION_CREDENTIALS

# If GKE deletion protection is true in terraform.tfvars:
#   set deletion_protection = false → terraform apply → then destroy

make destroy
# or: ./scripts/destroy-preserve-firestore-indexes.sh
# or: ./scripts/destroy-preserve-firestore-indexes.sh -auto-approve
```

Do **not** run plain `terraform destroy` unless you want to delete Firestore composite indexes too.

**If destroy fails on refresh:** fix API connectivity and retry. Use `terraform state rm 'ADDRESS'` only for resources already gone in GCP.

---

### What teardown does / does not remove

| Removed | Kept |
|---------|------|
| GKE, VPC, NAT, static IP (Terraform) | Firestore **composite indexes** (if using `make destroy`) |
| Pub/Sub, workload SAs (Terraform) | Firestore `(default)` database |
| `mcart_infra/cart_bootstrap` doc (Terraform) | Artifact Registry images |
| `cart_items` docs (optional cleanup script) | GCS catalog bucket, Secret Manager secrets |
| | Registrar DNS records (update manually if IP changes) |

---

## E. Quick checklist: full redeploy after successful teardown

| Step | Section |
|------|---------|
| `git pull` | A1 |
| Secrets still on disk? | A2 skip if yes |
| `terraform apply` | B1 |
| `get-credentials` | B2 |
| `data-install` + `ensure-auth-jwt-secret` | B3 |
| `flyway-install` | B4 |
| `apps-apply` | B5 |
| `gateway-install` + `gateway-apply` | B6 |
| Patch Envoy LB IP + DNS | B7 |
| curl checks | B8 |

---

## F. Quick checklist: app-only refresh (cluster already running)

| Step | Section |
|------|---------|
| `git pull` | A1 |
| `get-credentials` | B2 |
| `make apps-apply` | B5 |
| Rollout / image tag updates | B5 |

Skip B1, B3–B4, B6–B7 unless you changed those layers.
