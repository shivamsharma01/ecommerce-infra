# Run from: ecomm-infra/deploy
# Monorepo root = ../.. (parent of ecomm-infra)
#
# Helm reads ~/.kube/config (same as kubectl after get-credentials). You do not need the kubectl
# binary for make data-install / flyway-install (Helm checks the API). apps-apply needs kubectl:
#   gcloud components install kubectl
# If the API server is a local IP (e.g. 192.168.49.x), switch context to GKE:
#   gcloud container clusters get-credentials mcart-gke --location asia-south2-a --project ecommerce-491019

NS ?= mcart
HELM ?= helm
KUBECTL ?= kubectl
GKE_PROJECT ?= ecommerce-491019
GKE_CLUSTER ?= mcart-gke
GKE_LOCATION ?= asia-south2-a
# So `make flyway-install AUTH_DB_PASS=...` is visible in the recipe (and passwords with `$` are not mangled by Make).
export AUTH_DB_PASS AUTH_DB_PASS_FILE USER_DB_PASS USER_DB_PASS_FILE
ROOT := $(abspath $(CURDIR)/../..)
K8S := $(abspath $(CURDIR))/k8s/apps
GW  := $(abspath $(CURDIR))/k8s/gateway

.PHONY: helm-repo k8s-ready kubectl-required data-install data-install-redis data-install-es flyway-install apps-apply gateway-install gateway-apply catalog-bootstrap

# Helm reaches the API without the kubectl binary; kubectl cluster-info fails if kubectl is missing.
k8s-ready:
	@if $(HELM) list -n kube-system >/dev/null 2>&1; then exit 0; fi; \
	if command -v $(KUBECTL) >/dev/null 2>&1 && $(KUBECTL) cluster-info >/dev/null 2>&1; then exit 0; fi; \
	echo "Cannot reach the Kubernetes API (Helm could not list kube-system; kubectl check also failed or kubectl is missing)."; \
	if ! command -v $(KUBECTL) >/dev/null 2>&1; then \
	  echo "Install kubectl for diagnostics and for make apps-apply / gateway-apply:"; \
	  echo "  gcloud components install kubectl"; \
	fi; \
	if command -v $(KUBECTL) >/dev/null 2>&1; then \
	  ctx=$$($(KUBECTL) config current-context 2>/dev/null || echo unknown); \
	  server=$$($(KUBECTL) config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo ""); \
	  echo "kubectl context: $$ctx  API server: $$server"; \
	  case "$$server" in \
	    *192.168.49*|*127.0.0.1*|*localhost*|*.docker.internal*|*docker-desktop*) \
	      echo "This looks like a local cluster, not GKE.";; \
	  esac; \
	fi; \
	echo "Ensure kubeconfig points at GKE:"; \
	echo "  gcloud container clusters get-credentials $(GKE_CLUSTER) --location $(GKE_LOCATION) --project $(GKE_PROJECT)"; \
	echo "Private clusters need network path to the control plane (authorized networks / VPN)."; \
	exit 1

kubectl-required:
	@if command -v $(KUBECTL) >/dev/null 2>&1; then exit 0; fi; \
	echo "kubectl not found. Install it, then retry:"; \
	echo "  gcloud components install kubectl"; \
	exit 1

helm-repo:
	$(HELM) repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
	$(HELM) repo add opensearch https://opensearch-project.github.io/helm-charts 2>/dev/null || true
	$(HELM) repo update

data-install: helm-repo k8s-ready
	test -f helm/values-postgresql.yaml || (echo "cp helm/values-postgresql.example.yaml helm/values-postgresql.yaml && edit"; exit 1)
	$(HELM) upgrade --install mcart-pg bitnami/postgresql -n $(NS) --create-namespace -f helm/values-postgresql.yaml

data-install-redis: helm-repo k8s-ready
	test -f helm/values-redis.yaml || (echo "cp helm/values-redis.example.yaml helm/values-redis.yaml && edit"; exit 1)
	$(HELM) upgrade --install mcart-redis bitnami/redis -n $(NS) -f helm/values-redis.yaml

# OpenSearch (Elasticsearch-compatible HTTP API). Bitnami Elasticsearch images are often unavailable on Docker Hub.
data-install-es: helm-repo k8s-ready
	test -f helm/values-opensearch.yaml || (echo "cp helm/values-opensearch.example.yaml helm/values-opensearch.yaml && edit"; exit 1)
	$(HELM) upgrade --install mcart-os opensearch/opensearch -n $(NS) -f helm/values-opensearch.yaml

# Prefer AUTH_DB_PASS_FILE / USER_DB_PASS_FILE (e.g. mkstemp files) over env vars to avoid shell history.
# Passwords must match auth_user / user_user in helm/values-postgresql.yaml → primary.initdb.scripts.
# Use shell vars below (not $(AUTH_DB_PASS)): Make eats `$` inside passwords if expanded here.
flyway-install: k8s-ready
	@set -e; \
	if { [ -z "$${AUTH_DB_PASS_FILE-}" ] && [ -z "$${AUTH_DB_PASS-}" ]; } || { [ -z "$${USER_DB_PASS_FILE-}" ] && [ -z "$${USER_DB_PASS-}" ]; }; then \
	  echo "Set both: AUTH_DB_PASS or AUTH_DB_PASS_FILE, and USER_DB_PASS or USER_DB_PASS_FILE."; \
	  echo "They must match the CREATE USER ... PASSWORD values in helm/values-postgresql.yaml (initdb)."; \
	  exit 1; \
	fi; \
	if [ -n "$${AUTH_DB_PASS_FILE-}" ]; then AUTH_ARG="--set-file auth.password=$${AUTH_DB_PASS_FILE}"; \
	else AUTH_ARG="--set auth.password=$${AUTH_DB_PASS}"; fi; \
	if [ -n "$${USER_DB_PASS_FILE-}" ]; then USER_ARG="--set-file user.password=$${USER_DB_PASS_FILE}"; \
	else USER_ARG="--set user.password=$${USER_DB_PASS}"; fi; \
	$(HELM) upgrade --install mcart-bootstrap helm/mcart-bootstrap -n $(NS) $$AUTH_ARG $$USER_ARG

# Application manifests (canonical copy lives under ecomm-infra/deploy/k8s/apps/<service>/).
# Per-service secret.yaml is gitignored — copy secret.example.yaml → secret.yaml, edit, then apps-apply applies it if present.
apps-apply: k8s-ready kubectl-required
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/serviceaccount.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/configmap.yaml
	@if [ -f $(K8S)/auth/secret.yaml ]; then $(KUBECTL) apply -n $(NS) -f $(K8S)/auth/secret.yaml; else echo "auth: no secret.yaml (copy secret.example.yaml)"; fi
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/serviceaccount.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/configmap.yaml
	@if [ -f $(K8S)/user/secret.yaml ]; then $(KUBECTL) apply -n $(NS) -f $(K8S)/user/secret.yaml; else echo "user: no secret.yaml (copy secret.example.yaml)"; fi
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/serviceaccount.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/configmap.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/search/configmap.yaml
	@if [ -f $(K8S)/search/secret.yaml ]; then $(KUBECTL) apply -n $(NS) -f $(K8S)/search/secret.yaml; else echo "search: no secret.yaml (optional; copy secret.example.yaml if OpenSearch uses basic auth)"; fi
	$(KUBECTL) apply -n $(NS) -f $(K8S)/search/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/search/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/serviceaccount.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/configmap.yaml
	@if [ -f $(K8S)/product-indexer/secret.yaml ]; then $(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/secret.yaml; else echo "product-indexer: no secret.yaml (optional; copy secret.example.yaml if OpenSearch uses basic auth)"; fi
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/mcart-ui/configmap.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/mcart-ui/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/mcart-ui/service.yaml

# Gateway API + JWT (Envoy Gateway + cert-manager). See k8s/gateway/README.md.
# install.yaml ships CRDs + controller only — it does NOT create a GatewayClass (see 00-gatewayclass.yaml).
# Do not use `helm install ... gateway-helm --version v0.0.0-latest` for production; use the pinned install.yaml.
gateway-install: k8s-ready
	@echo "Installing Envoy Gateway v1.7.1 (official install.yaml: CRDs + controller)..."
	$(KUBECTL) apply --server-side -f "https://github.com/envoyproxy/gateway/releases/download/v1.7.1/install.yaml"
	$(KUBECTL) wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
	@echo "Creating GatewayClass envoy-gateway (required; not in upstream install.yaml)..."
	$(KUBECTL) apply -f $(GW)/00-gatewayclass.yaml
	@echo "Verifying GatewayClass is visible and accepted:"
	@$(KUBECTL) get gatewayclass envoy-gateway -o wide

	@echo "Installing cert-manager via Helm (Gateway API HTTP-01 solver enabled)..."
	$(HELM) repo add jetstack https://charts.jetstack.io 2>/dev/null || true
	$(HELM) repo update
	$(HELM) upgrade --install cert-manager jetstack/cert-manager \
	  --namespace cert-manager --create-namespace \
	  --version v1.16.3 \
	  --set crds.enabled=true \
	  --set config.enableGatewayAPI=true
	$(KUBECTL) wait --timeout=5m -n cert-manager deploy/cert-manager --for=condition=Available
	$(KUBECTL) wait --timeout=5m -n cert-manager deploy/cert-manager-webhook --for=condition=Available
	$(KUBECTL) wait --timeout=5m -n cert-manager deploy/cert-manager-cainjector --for=condition=Available

gateway-apply: k8s-ready kubectl-required
	$(KUBECTL) apply -f $(GW)/00-namespace.yaml
	$(KUBECTL) apply -f $(GW)/00-gatewayclass.yaml
	$(KUBECTL) apply -f $(GW)/05-referencegrant.yaml
	$(KUBECTL) apply -f $(GW)/01-gateway.yaml
	$(KUBECTL) apply -f $(GW)/02-httproutes.yaml
	$(KUBECTL) apply -f $(GW)/03-securitypolicy-jwt.yaml
	$(KUBECTL) apply -f $(GW)/10-cert-manager-clusterissuer.yaml
	$(KUBECTL) apply -f $(GW)/11-certificate.yaml

# One-time per project: default Firestore Native database (reads catalog/bootstrap.env).
catalog-firestore:
	bash "$(abspath $(CURDIR))/scripts/create_firestore_database.sh"

# Demo catalog bootstrap (images -> GCS, products -> Firestore, optional reindex).
# Required vars: PROJECT_ID, BUCKET. Optional: CATALOG_JSON, CATALOG_ASSETS_DIR, IMAGE_PREFIX, REINDEX_URL, MCART_BEARER_TOKEN.
catalog-bootstrap:
	@if [ -z "$(PROJECT_ID)" ] || [ -z "$(BUCKET)" ]; then \
	  echo "Usage: make catalog-bootstrap PROJECT_ID=<gcp-project> BUCKET=<catalog-images-bucket>"; \
	  exit 1; \
	fi
	python3 "$(abspath $(CURDIR))/scripts/bootstrap_catalog.py"
