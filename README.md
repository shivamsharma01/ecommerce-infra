# ecomm-infra

Terraform (GKE, VPC, API Gateway, public HTTPS LB), Helm (PostgreSQL, Redis, Elasticsearch, Flyway bootstrap), and Kubernetes manifests for **mcart**.

**This checkout is wired for:** GCP project **`ecommerce-491019`**, region **`asia-south2`**, zonal cluster **`mcart-gke`** in **`asia-south2-a`**, domain **`mcart.store`**, Artifact Registry **`asia-south2-docker.pkg.dev/ecommerce-491019/docker-apps/`**.

**End-to-end without GitHub:** use **Cloud Source Repositories** (or another supported host) for Git, **Cloud Build** triggers for **service images** and for **this repo’s** `cloudbuild.yaml` to apply YAML to GKE. See **§10** for a plain-language checklist.

---

## What never goes in Git

| Item | Location |
|------|----------|
| `terraform.tfvars` | `terraform/` (see `terraform/terraform.tfvars.example`) |
| Helm passwords | `deploy/helm/values-postgresql.yaml`, `values-redis.yaml`, `values-elasticsearch.yaml` (copy from `*.example.yaml`) |
| App secrets | `deploy/k8s/apps/<svc>/secret.yaml` (copy from `secret.example.yaml`) |

---

## 1. Terraform

**Why a script before `terraform apply`?** Enabling APIs with Terraform (`google_project_service`) needs **Service Usage Admin** (or Owner) on the **same credentials Terraform uses**. Many setups use a **service account** that can create GKE/Compute but **cannot** list or enable APIs—you then get **403 Permission denied to list services**. This repo enables APIs **once** with **`gcloud`** (your user or an admin SA), then Terraform only creates infrastructure.

**Step A — one time per project** (as Owner / Editor / `roles/serviceusage.serviceUsageAdmin`):

```bash
gcloud auth login
gcloud config set project ecommerce-491019

cd terraform
./scripts/enable-apis.sh ecommerce-491019
# or: make apis-enable PROJECT_ID=ecommerce-491019
```

Wait **1–2 minutes** after it finishes.

**Step B — Terraform** (can use a narrower service account if you prefer):

```bash
gcloud auth application-default login   # or point ADC at your terraform SA key
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit if needed
terraform init
terraform plan -out=tfplan && terraform apply tfplan
```

**Creates:** VPC, subnet, NAT, GKE, Pub/Sub, global static IP, API Gateway + OpenAPI backend, HTTPS forwarding rule, optional Cloud DNS.

**First apply** uses placeholder `ingress_https_backend_base_url` (default `https://0.0.0.0`). After workloads + Ingress exist, set it to the GKE Ingress HTTPS origin, bump `api_gateway_config_id`, and apply again (see §5).

```bash
gcloud container clusters get-credentials mcart-gke --location asia-south2-a --project ecommerce-491019
terraform output -raw mcart_static_ip_address   # DNS A/AAAA for mcart.store → this IP
```

**If you already applied an older version** that created `google_project_service.*` in state, remove them from state after upgrading (they are no longer in code):

```bash
cd terraform
terraform state list | grep 'google_project_service.required' | xargs -r terraform state rm
```

### Who may run `terraform apply`? (fixes 403 “permission denied” / “IAM API disabled”)

Terraform is acting as **whatever credentials Application Default Credentials use** (`gcloud auth application-default login`, or `GOOGLE_APPLICATION_CREDENTIALS` pointing at a key). That principal must be allowed to create VPCs, GKE, service accounts, Pub/Sub, API Gateway, load balancers, and project IAM bindings.

**Easiest for a solo project:** use your Google user and grant yourself **Editor** or **Owner** on **`ecommerce-491019`** (IAM → Grant access → Principal = your email → Role = *Editor*).

**If you use a dedicated service account for Terraform**, bind it on the project (replace `SA_EMAIL`):

```bash
PROJECT_ID=ecommerce-491019
SA_EMAIL=terraform-runner@${PROJECT_ID}.iam.gserviceaccount.com

# Broad but simple (tighten later):
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor"
```

A **narrower** set (still large) would include at least: `roles/compute.admin`, `roles/container.admin`, `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.projectIamAdmin`, `roles/apigateway.admin`, `roles/pubsub.admin`, plus **Service Management** access for API Gateway (`roles/servicemanagement.admin` or related). In practice **Editor** avoids trial-and-error on individual permissions.

**“IAM API has not been used / is disabled”** (sometimes the error shows a **project number**, not `ecommerce-491019`—that number is the same project): run **`./scripts/enable-apis.sh`** again for **`ecommerce-491019`**, wait 2–5 minutes, then verify:

```bash
make apis-verify PROJECT_ID=ecommerce-491019
# or: ./scripts/verify-apis.sh ecommerce-491019
```

**Wrong project:** ensure `project_id` in **`terraform.tfvars`**, **`gcloud config set project`**, and the account you used for **`enable-apis.sh`** all refer to the **same** project.

---

## 2. Helm data layer + Flyway

From **`deploy/`**:

```bash
cp helm/values-postgresql.example.yaml helm/values-postgresql.yaml
cp helm/values-redis.example.yaml helm/values-redis.yaml
cp helm/values-elasticsearch.example.yaml helm/values-elasticsearch.yaml
# Edit passwords; Postgres initdb users must match Flyway below

make data-install data-install-redis data-install-es

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n mcart --timeout=300s

printf '%s' "$AUTH_PASS" > /tmp/auth.db.pass && chmod 600 /tmp/auth.db.pass
printf '%s' "$USER_PASS" > /tmp/user.db.pass && chmod 600 /tmp/user.db.pass
make flyway-install AUTH_DB_PASS_FILE=/tmp/auth.db.pass USER_DB_PASS_FILE=/tmp/user.db.pass
rm -f /tmp/auth.db.pass /tmp/user.db.pass
```

Canonical SQL: `deploy/helm/mcart-bootstrap/files/{auth,user}/`. **Auth** and **user** apps do not run Flyway on startup.

**Local Flyway only:** `deploy/scripts/run-flyway-local.sh` with `FLYWAY_URL` / `FLYWAY_USER` / `FLYWAY_PASSWORD` set.

---

## 3. Kubernetes apps + secrets

1. Align **ConfigMaps** if your Helm release names differ (defaults target Bitnami-style DNS under namespace `mcart`).
2. Copy each **`deploy/k8s/apps/<svc>/secret.example.yaml`** → **`secret.yaml`** and set values matching Helm DB/Redis/ES passwords.
3. Apply:

```bash
cd deploy
make apps-apply NS=mcart
```

**Secret names:** `auth-secrets`, `user-secrets`, `search-secrets`, `product-indexer-secrets` (keys are listed in each `secret.example.yaml`). Optional: `kubectl create secret generic ... --from-literal=...`.

**Images:** each `deployment.yaml` points at Artifact Registry (`…/docker-apps/<service>:<tag>`). After a **service** Cloud Build finishes, copy the new **short SHA** tag from the build log into the matching `deployment.yaml` in this repo, commit, and run the **ecomm-infra** deploy trigger—or run `kubectl set image deployment/<name> <name>=<full-image-uri> -n mcart` from a machine that has cluster access.

---

## 4. Ingress + managed certificate

```bash
cd deploy
make ingress-apply NS=mcart
```

When **`kubectl describe managedcertificate mcart-store-cert -n mcart`** shows **Active**, uncomment `networking.gke.io/managed-certificates: mcart-store-cert` in `deploy/k8s/ingress/mcart-store-ingress.yaml` and re-apply.

**Traffic path:** `Browser → mcart.store (DNS → static IP) → HTTPS LB → API Gateway → GKE Ingress → Services`.

**JWT / OIDC:** ConfigMaps use issuer **`https://mcart.store`** (`AUTH_ISSUER_URI`, `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI`, `API_BASE_URL` on UI).

**Ingress paths (summary):** `/.well-known`, `/oauth2`, `/login`, `/auth` → auth; `/user` → user; `/api/products`, `/v3/api-docs`, `/swagger-ui` → product; `/api/search` → search; `/product-indexer` → product-indexer; `/` → mcart-ui.

---

## 5. Second Terraform apply (API Gateway → Ingress)

```bash
kubectl get ingress mcart-store -n mcart -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# If hostname instead of IP, use https://<hostname>
```

Set in **`terraform.tfvars`**:

```hcl
ingress_https_backend_base_url = "https://<ingress-ip-or-host>"
api_gateway_config_id          = "v2"   # bump from previous
```

Then `terraform apply`. `api_gateway_backend_disable_auth` defaults to `true` (Google→backend identity); `Authorization` headers still reach Spring.

---

## 6. Cloud Build → GKE (this repo)

**File:** `cloudbuild.yaml` at the root of **ecomm-infra**. Your trigger should use it as the build configuration (or path `cloudbuild.yaml`).

**What it does:** installs `make`, runs `gcloud container clusters get-credentials`, then `make apps-apply` and `make ingress-apply` under `deploy/` (namespace default `mcart`).

**Substitutions** (set in the trigger UI if defaults are wrong):

| Variable | Meaning | Example |
|----------|---------|---------|
| `_CLUSTER_NAME` | GKE cluster | `mcart-gke` |
| `_GKE_LOCATION` | Zone **or** region | `asia-south2-a` (zonal) or `asia-south2` (regional) |
| `_GKE_LOCATION_KIND` | How to interpret location | `zone` or `region` |
| `_K8S_NAMESPACE` | Namespace | `mcart` |

**IAM:** On your GCP project, grant the **Cloud Build** service account the role **Kubernetes Engine Developer** (`roles/container.developer`).  
Default Cloud Build SA: **`PROJECT_NUMBER@cloudbuild.gserviceaccount.com`** (Cloud Console → Cloud Build → Settings, or IAM).

If the trigger uses a **custom** build service account, grant **`roles/container.developer`** to that account instead.

**Secrets:** This deploy build does **not** apply gitignored `secret.yaml` files. Create Kubernetes Secrets once (from your laptop with `kubectl`, or a one-off job). After that, each trigger run refreshes ConfigMaps, Deployments, Services, and Ingress from Git.

---

## 7. Cloud Build (service repos)

Each microservice repo has a **`cloudbuild.yaml`** that only **builds and pushes** the image to Artifact Registry. Rolling out a new tag is: update **`ecomm-infra`** `deployment.yaml` (or `kubectl set image`) → run the **ecomm-infra** trigger.

---

## 8. Cost knobs (Terraform)

Zonal preemptible pool is already oriented toward lower cost. In `terraform.tfvars` you can tune `node_machine_type`, `node_min_count` / `node_max_count`, `node_preemptible`, `node_disk_size_gb`. Fixed cost includes control plane, Cloud NAT, HTTPS LB, API Gateway.

---

## 9. Env / ConfigMap quick reference

Deployments use `envFrom` on `<service>-config` and optional `<service>-secrets`. Spring maps env vars with relaxed binding (e.g. `SPRING_DATASOURCE_URL` → `spring.datasource.url`).

| Service | Notable ConfigMap keys |
|---------|-------------------------|
| auth | `DB_URL`, `REDIS_HOST`, `AUTH_ISSUER_URI`, `GCP_PROJECT_ID`, OAuth redirect, mail host |
| user | `SPRING_DATASOURCE_URL`, `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI`, Pub/Sub |
| product | Firestore, Pub/Sub, `APP_SECURITY_*`, JWT issuer |
| search | `SPRING_ELASTICSEARCH_URIS`, JWT issuer |
| product-indexer | Firestore, ES, Pub/Sub subscription, JWT issuer |
| mcart-ui | `API_BASE_URL`, `PORT` |

---

## 10. Plain-language checklist (infra + apps + automatic deploy)

Do these **in order** the first time. Later you only repeat the parts that changed.

1. **Google Cloud project**  
   Use project **`ecommerce-491019`** (or yours). Enable billing. Install **`gcloud`**, **`kubectl`**, **`helm`**, **`terraform`** on your computer.

2. **Artifact Registry**  
   Create a Docker repo named **`docker-apps`** in **`asia-south2`** if you do not already have it. Service images will be stored as  
   `asia-south2-docker.pkg.dev/PROJECT_ID/docker-apps/SERVICE_NAME:TAG`.

3. **Terraform (creates the cluster and network)**  
   On your PC: clone **ecomm-infra**, copy **`terraform/terraform.tfvars.example`** to **`terraform/terraform.tfvars`**, adjust if needed, then run **`terraform init`** and **`terraform apply`** inside **`terraform/`**.  
   This creates **GKE**, **VPC**, **static IP**, **API Gateway** front end, etc.

4. **Point DNS at Google**  
   Take the static IP from **`terraform output`** and create an **A record** for **`mcart.store`** (and **`www`** if you use it) at your domain registrar so traffic hits Google’s load balancer.

5. **Helm: databases**  
   On your PC, **`kubectl`** must talk to the new cluster (**`gcloud container clusters get-credentials …`**). Under **`ecomm-infra/deploy`**, copy the three **`values-*.example.yaml`** files to **`values-*.yaml`**, set strong passwords, then run **`make data-install`**, **`data-install-redis`**, **`data-install-es`**.

6. **Flyway (database schema)**  
   Still under **`deploy/`**, run **`make flyway-install`** with the same database passwords you put in the Postgres values file.

7. **Kubernetes secrets for apps**  
   For **auth**, **user**, and optionally **search** / **product-indexer**, copy each **`secret.example.yaml`** to **`secret.yaml`**, fill in real passwords (matching Postgres/Redis/Elasticsearch), then run **`make apps-apply`** **once** from your PC—or apply those YAML files manually.  
   *Cloud Build will not commit `secret.yaml` (it stays local or in a secure store you choose).*

8. **First apply of app YAML + Ingress from your PC (sanity check)**  
   Run **`make apps-apply`** and **`make ingress-apply`**. Fix any errors (missing secrets, wrong image tag).  
   Get the **Ingress** IP with **`kubectl get ingress -n mcart`**.

9. **Fix API Gateway → Ingress link**  
   Put that Ingress URL (as **`https://…`**) into **`ingress_https_backend_base_url`** in **`terraform.tfvars`**, bump **`api_gateway_config_id`**, run **`terraform apply`** again.

10. **Managed certificate**  
    When the cert object is **Active**, uncomment the managed-cert annotation in **`deploy/k8s/ingress/mcart-store-ingress.yaml`** and apply again (from PC or via trigger).

11. **Connect Cloud Build to Git**  
    Mirror or connect **ecomm-infra** to **Cloud Source Repositories** (or supported Git host). Create a **trigger** that runs on pushes to your main branch and uses **`cloudbuild.yaml`**.

12. **Grant Cloud Build permission to GKE**  
    Give the Cloud Build service account **Kubernetes Engine Developer** on the project (see §6).

13. **Service image triggers**  
    For **auth**, **user**, **product**, **search**, **product-indexer**, **mcart-ui**, create one trigger per repo using each **`cloudbuild.yaml`**. Pushing code builds and pushes a new image. Then update the image line in **ecomm-infra** and push—or use **`kubectl set image`**—and run the **ecomm-infra** trigger to roll out.

---

## 11. Git / CSR checklist

- Do not commit **`terraform.tfvars`**, **`*.tfstate`**, Helm **`values-*.yaml`** with real passwords, or **`deploy/k8s/apps/**/secret.yaml`**.
- Commit **`terraform/.terraform.lock.hcl`** after **`terraform init`**.
