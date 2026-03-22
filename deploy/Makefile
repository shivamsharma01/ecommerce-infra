# Run from: ecomm-infra/deploy
# Monorepo root = ../.. (parent of ecomm-infra)

NS ?= mcart
HELM ?= helm
KUBECTL ?= kubectl
ROOT := $(abspath $(CURDIR)/../..)
K8S := $(abspath $(CURDIR))/k8s/apps
# Set to 0 to skip Elasticsearch ExternalSecrets (search, product-indexer) if GSM keys are not ready yet.
APPLY_ES_SECRETS ?= 1

.PHONY: helm-repo data-install data-install-redis data-install-es flyway-install apps-apply

helm-repo:
	$(HELM) repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
	$(HELM) repo update

data-install: helm-repo
	test -f helm/values-postgresql.yaml || (echo "cp helm/values-postgresql.example.yaml helm/values-postgresql.yaml && edit"; exit 1)
	$(HELM) upgrade --install mcart-pg bitnami/postgresql -n $(NS) --create-namespace -f helm/values-postgresql.yaml

data-install-redis: helm-repo
	test -f helm/values-redis.yaml || (echo "cp helm/values-redis.example.yaml helm/values-redis.yaml && edit"; exit 1)
	$(HELM) upgrade --install mcart-redis bitnami/redis -n $(NS) -f helm/values-redis.yaml

data-install-es: helm-repo
	test -f helm/values-elasticsearch.yaml || (echo "cp helm/values-elasticsearch.example.yaml helm/values-elasticsearch.yaml && edit"; exit 1)
	$(HELM) upgrade --install mcart-es bitnami/elasticsearch -n $(NS) -f helm/values-elasticsearch.yaml

# Prefer AUTH_DB_PASS_FILE / USER_DB_PASS_FILE (e.g. mkstemp files) over env vars to avoid shell history.
flyway-install:
	@set -e; \
	AUTH_ARG=; USER_ARG=; \
	if [ -n "$(AUTH_DB_PASS_FILE)" ]; then AUTH_ARG="--set-file auth.password=$(AUTH_DB_PASS_FILE)"; \
	elif [ -n "$(AUTH_DB_PASS)" ]; then AUTH_ARG="--set auth.password=$(AUTH_DB_PASS)"; \
	else echo "Set AUTH_DB_PASS or AUTH_DB_PASS_FILE (must match initdb in values-postgresql.yaml)"; exit 1; fi; \
	if [ -n "$(USER_DB_PASS_FILE)" ]; then USER_ARG="--set-file user.password=$(USER_DB_PASS_FILE)"; \
	elif [ -n "$(USER_DB_PASS)" ]; then USER_ARG="--set user.password=$(USER_DB_PASS)"; \
	else echo "Set USER_DB_PASS or USER_DB_PASS_FILE"; exit 1; fi; \
	$(HELM) upgrade --install mcart-bootstrap helm/mcart-bootstrap -n $(NS) $$AUTH_ARG $$USER_ARG

# Application manifests (canonical copy lives under ecomm-infra/deploy/k8s/apps/<service>/).
apps-apply:
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/configmap.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/external-secret.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/auth/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/configmap.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/external-secret.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/user/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/configmap.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/search/configmap.yaml
	@if [ "$(APPLY_ES_SECRETS)" = "1" ]; then $(KUBECTL) apply -n $(NS) -f $(K8S)/search/external-secret.yaml; else echo "Skipping search ExternalSecret (APPLY_ES_SECRETS!=1)"; fi
	$(KUBECTL) apply -n $(NS) -f $(K8S)/search/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/search/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/serviceaccount.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/configmap.yaml
	@if [ "$(APPLY_ES_SECRETS)" = "1" ]; then $(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/external-secret.yaml; else echo "Skipping product-indexer ExternalSecret (APPLY_ES_SECRETS!=1)"; fi
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/product-indexer/service.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/mcart-ui/configmap.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/mcart-ui/deployment.yaml
	$(KUBECTL) apply -n $(NS) -f $(K8S)/mcart-ui/service.yaml
