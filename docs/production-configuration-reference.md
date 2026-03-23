# Production configuration reference (mcart)

Single place for **environment variables**, **Kubernetes ConfigMaps/Secrets**, how they connect to **`application.yaml` / `application.yml`**, and **placeholders you must replace** before production.

Related: [SETUP.md](../SETUP.md) (git push checklist), [kubernetes-secrets-production.md](./kubernetes-secrets-production.md) (GSM + External Secrets).

---

## 1. How ConfigMap / Secret link to Spring Boot

### 1.1 Kubernetes → container

Deployments use `envFrom`:

```yaml
envFrom:
  - configMapRef:
      name: <service>-config
  - secretRef:
      name: <service>-secrets
      optional: true
```

Each **key** in the ConfigMap or Secret becomes an **environment variable** in the container with the **same name** and the string value from `data`.

Example: ConfigMap entry `SERVER_PORT: "8080"` → process env `SERVER_PORT=8080`.

External Secrets Operator fills the Secret from GCP Secret Manager; key names (e.g. `DB_PASSWORD`) are whatever you define in `external-secret.yaml` → they still become env vars with those names.

### 1.2 Environment variables → Spring properties

Spring Boot applies **relaxed binding**:

| Env var (typical) | Spring property |
|-------------------|-----------------|
| `SPRING_DATASOURCE_URL` | `spring.datasource.url` |
| `SPRING_CLOUD_GCP_PROJECT_ID` | `spring.cloud.gcp.project-id` |
| `APP_SECURITY_ENABLED` | `app.security.enabled` |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | `spring.security.oauth2.resourceserver.jwt.issuer-uri` |

Rules: dots → underscores, uppercase, duplicate underscores collapsed. You do **not** need a matching line in YAML if the env var already maps to the property Spring expects.

### 1.3 `application.yaml` / `application.yml` in the JAR

Files under `src/main/resources/application.yaml` are **defaults** and **explicit bridges**:

- **`${ENV_VAR:default}`** — read from the environment (or ConfigMap-injected env); if unset, use `default`.
- Values set only in YAML without `${...}` are fixed unless overridden by env (via relaxed binding to the same property).

**Order of precedence (highest wins):** environment variables (including from ConfigMap/Secret) override packaged YAML.

So in prod you usually:

1. Put **non-secret** settings in **ConfigMap** (URLs, feature flags, public issuer URL).
2. Put **secrets** in **Kubernetes Secret** (from GSM via ExternalSecret, or manual `kubectl create secret`).
3. Keep **`application.yaml`** as structure + safe defaults for local dev.

---

## 2. Global items (every deploy)

| Item | Where | What to do |
|------|--------|------------|
| Container image | Each `deployment.yaml` | Replace `<ARTIFACT_REGISTRY_URL>` and `<VERSION>`. |
| Auth public URL | Auth + all JWT consumers | `AUTH_ISSUER_URI` (auth) and `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` (others) must equal the **`iss`** claim on access tokens (same string). |
| GCP project id | ConfigMaps | Replace `CHANGEME_GCP_PROJECT_ID`. |
| In-cluster DNS | ConfigMaps | JDBC URLs, Redis, Elasticsearch hosts must match **your** Helm release names and **namespaces** (samples use `postgresql.*.svc`, `redis-service.auth.svc`, `elasticsearch.elasticsearch.svc` — adjust if different). |
| GSM secrets + ESO | Cluster | Create secrets in Secret Manager; install ESO + ClusterSecretStore; apply `external-secret.yaml`. See [kubernetes-secrets-production.md](./kubernetes-secrets-production.md). |
| Bootstrap admin | Flyway SQL | After first deploy, change bootstrap password / hash if used. |

---

## 3. Service-by-service tables

Keys listed are the **environment variable names** your pods receive (ConfigMap/Secret **keys**). “YAML binding” shows how `application.yaml` ties in when it uses `${VAR}` or when Spring maps the env name directly.

### 3.1 `auth`

**Sources:** `deploy/k8s/apps/auth/configmap.yaml`, `auth-secrets` (ExternalSecret), `auth/src/main/resources/application.yaml`.

| Env var (ConfigMap / Secret) | Purpose | YAML / Spring binding |
|------------------------------|---------|------------------------|
| `SERVER_PORT` | HTTP port | `server.port` |
| `DB_URL`, `DB_USERNAME` | PostgreSQL | `spring.datasource.*` via `${DB_*}` |
| `DB_PASSWORD` | **Secret** | `${DB_PASSWORD:}` → datasource password |
| `REDIS_HOST`, `REDIS_PORT` | Redis | `${REDIS_*}` |
| `REDIS_PASSWORD` | **Secret** | `${REDIS_PASSWORD:}` |
| `AUTH_ISSUER_URI` | JWT `iss` + OIDC | `auth.issuer-uri` |
| `AUTH_VERIFICATION_BASE_URL` | Email links | `auth.verification.base-url` |
| `OAUTH2_CLIENT_ID`, `OAUTH2_REDIRECT_URI` | OAuth2 client | `auth.oauth2.*` |
| `OAUTH2_CLIENT_SECRET` | **Secret** | `auth.oauth2.client-secret` |
| `GCP_PROJECT_ID` | Pub/Sub, etc. | `spring.cloud.gcp.project-id` (also `${GCP_PROJECT_ID}` in yaml) |
| `GCP_CREDENTIALS_PATH` | Optional key file (prefer WI in GKE) | `spring.cloud.gcp.credentials.location` |
| `AUTH_PUBSUB_USER_SIGNUP_TOPIC` | Topic name | `auth.pubsub.user-signup-topic` |
| `SPRING_MAIL_HOST`, `SPRING_MAIL_PORT` | SMTP | `spring.mail.*` |
| `SPRING_MAIL_USERNAME`, `SPRING_MAIL_PASSWORD` | **Secret** (password) | `spring.mail.username/password` |
| `JWT_ACCESS_TTL_SECONDS`, `JWT_REFRESH_TTL_SECONDS` | Token TTL | `security.jwt.*` |
| `JWT_SECRET` | **Secret** (if used by config) | `security.jwt.secret` |
| `AUTH_COOKIE_SECURE` | Cookie `Secure` flag | `auth.cookie.secure` (optional; add to ConfigMap if needed) |
| `EMAIL_VERIFICATION_*`, `LOGIN_*` | Rate limits / lockout | Optional overrides for `auth.*` |

**Prod placeholders to fix in Git:** `CHANGEME_GCP_PROJECT_ID`, any leftover `*.example.com` URLs, Redis/Postgres hostnames if your cluster differs. Helm password files (`values-*.yaml`) are local — examples use **`MY_PASSWORD`** as the placeholder name.

---

### 3.2 `user`

**Sources:** `deploy/k8s/apps/user/configmap.yaml`, `user-secrets`, `user/src/main/resources/application.yaml`.

| Env var | Purpose | YAML / Spring binding |
|---------|---------|------------------------|
| `SERVER_PORT` | HTTP port | `server.port` |
| `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME` | PostgreSQL | `spring.datasource.*` (direct + yaml defaults) |
| `SPRING_DATASOURCE_PASSWORD` | **Secret** | `spring.datasource.password` |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | Validate JWTs | `spring.security.oauth2.resourceserver.jwt.issuer-uri` |
| `GCP_PROJECT_ID` / `SPRING_CLOUD_GCP_PROJECT_ID` | GCP | Project id |
| `SPRING_CLOUD_GCP_PUBSUB_ENABLED` | Pub/Sub client | `spring.cloud.gcp.pubsub.enabled` |
| `SPRING_CLOUD_GCP_CREDENTIALS_LOCATION` | Optional key path | Prefer Workload Identity in GKE |
| `USER_PUBSUB_ENABLED` | App subscriber | `user.pubsub.enabled` |
| `USER_PUBSUB_SUBSCRIPTION` | Subscription name | `user.pubsub.subscription` |

**Prod placeholders:** `CHANGEME_GCP_PROJECT_ID`, issuer URL, JDBC URL host if not `postgresql.user.svc`.

---

### 3.3 `product`

**Sources:** `deploy/k8s/apps/product/configmap.yaml`, optional `product-secrets`, `product/src/main/resources/application.yml`.

| Env var | Purpose | YAML / Spring binding |
|---------|---------|------------------------|
| `SERVER_PORT` | HTTP port | `server.port` |
| `SPRING_CLOUD_GCP_PROJECT_ID` | Firestore / GCP | `spring.cloud.gcp.project-id` |
| `SPRING_CLOUD_GCP_CREDENTIALS_LOCATION` | Optional SA JSON path | Prefer WI on GKE |
| `SPRING_CLOUD_GCP_FIRESTORE_ENABLED` | Firestore client | `spring.cloud.gcp.firestore.enabled` |
| `SPRING_CLOUD_GCP_FIRESTORE_HOST` | Emulator / custom host | `spring.cloud.gcp.firestore.host` (if used) |
| `SPRING_CLOUD_GCP_PUBSUB_ENABLED` | Outbox / Pub/Sub | `spring.cloud.gcp.pubsub.enabled` — `true` in sample ConfigMap for prod |
| `APP_SECURITY_ENABLED` | JWT on `/api/**` | `app.security.enabled` |
| `APP_SECURITY_REQUIRED_SCOPE` | e.g. `product.admin` | `app.security.required-scope` |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | JWT validation | `spring.security.oauth2.resourceserver.jwt.issuer-uri` |

Optional **Secret** keys (if you add an ExternalSecret later): anything your code expects (e.g. API keys) — `product-secrets` is optional in Git manifests.

**Prod placeholders:** `CHANGEME_GCP_PROJECT_ID`, issuer URL, Firestore enablement.

---

### 3.4 `search`

**Sources:** `deploy/k8s/apps/search/configmap.yaml`, optional `search-secrets`, `search/src/main/resources/application.yml`.

| Env var | Purpose | YAML / Spring binding |
|---------|---------|------------------------|
| `SERVER_PORT` | HTTP port | `server.port` |
| `SPRING_APPLICATION_NAME` | App name | `spring.application.name` |
| `SPRING_ELASTICSEARCH_URIS` | ES cluster URL | `spring.elasticsearch.uris` |
| `APP_SECURITY_ENABLED` | JWT on `/api/**` | `app.security.enabled` |
| `APP_SECURITY_REQUIRED_SCOPE` | Optional scope for mutating methods | `app.security.required-scope` (add to ConfigMap if used) |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | JWT validation | `spring.security.oauth2.resourceserver.jwt.issuer-uri` |
| `MANAGEMENT_*` | Actuator | Standard Spring management binding |

Elasticsearch credentials (if ES has auth): usually via **Secret** and `SPRING_ELASTICSEARCH_USERNAME` / `PASSWORD` or your app’s property names — align with `search` service code and optional `external-secret.yaml`.

**Prod placeholders:** ES URL (service DNS), issuer URL.

---

### 3.5 `product-indexer`

**Sources:** `deploy/k8s/apps/product-indexer/configmap.yaml`, optional `product-indexer-secrets`, `product-indexer/src/main/resources/application.yaml`.

| Env var | Purpose | YAML / Spring binding |
|---------|---------|------------------------|
| `SERVER_PORT` | HTTP port | `server.port` |
| `SPRING_APPLICATION_NAME` | App name | `spring.application.name` |
| `SPRING_CLOUD_GCP_PROJECT_ID` | Firestore / Pub/Sub | `spring.cloud.gcp.project-id` |
| `SPRING_CLOUD_GCP_FIRESTORE_ENABLED` | Firestore | `spring.cloud.gcp.firestore.enabled` |
| `SPRING_CLOUD_GCP_CREDENTIALS_LOCATION` | Optional key path | Prefer WI |
| `SPRING_ELASTICSEARCH_URIS` | ES for indexing | `spring.elasticsearch.uris` |
| `SPRING_DATA_ELASTICSEARCH_REPOSITORIES_ENABLED` | Repos off | `spring.data.elasticsearch.repositories.enabled` |
| `SPRING_DATA_ELASTICSEARCH_AUTO_INDEX_CREATION` | Index creation | `spring.data.elasticsearch.auto-index-creation` |
| `PRODUCT_INDEXER_PUBSUB_ENABLED` | Subscriber | `product-indexer.pubsub.enabled` |
| `PRODUCT_INDEXER_PUBSUB_SUBSCRIPTION` | Subscription id | `product-indexer.pubsub.subscription` |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` | JWT for `/product-indexer/admin/**` | `spring.security.oauth2.resourceserver.jwt.issuer-uri` |
| `MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED` | Probes | Management config |

**Prod placeholders:** GCP project, ES/Firestore/Pub/Sub endpoints, issuer URL.

---

### 3.6 `mcart-ui` (Node / SSR, not Spring)

**Sources:** `deploy/k8s/apps/mcart-ui/configmap.yaml`, optional `mcart-ui-secrets`.

| Env var | Purpose |
|---------|---------|
| `NODE_ENV` | e.g. `production` |
| `PORT` | Listen port (matches container `containerPort`) |
| `API_BASE_URL` | Public API / gateway URL for browser or SSR |

No `application.yml` in the JVM sense — the **Node** process reads **`process.env`**. Same Kubernetes rule: ConfigMap keys → env vars.

**Prod placeholders:** `API_BASE_URL`, `https://api.example.com` → your real API/gateway.

---

## 4. Quick diagram

```text
Git: deploy/k8s/apps/<svc>/configmap.yaml
        │
        ▼
Kubernetes ConfigMap  ──envFrom──►  Pod env vars  ──►  Spring Boot binds to properties
        │                                      │
Secret (ESO / manual)  ──envFrom──►  (same)     └──►  application.yaml defaults + ${VAR} overrides
```

---

## 5. Pending values checklist (copy for your runbook)

- [ ] All `CHANGEME_*` and `*.example.com` / `api.example.com` in ConfigMaps  
- [ ] `AUTH_ISSUER_URI` == `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` (same URL as JWT `iss`)  
- [ ] JDBC/Redis/Elasticsearch hostnames match cluster services  
- [ ] GSM secrets created; ExternalSecrets syncing; Secret keys match tables above  
- [ ] Images: `<ARTIFACT_REGISTRY_URL>` / `<VERSION>` in every `deployment.yaml`  
- [ ] Product: confirm `SPRING_CLOUD_GCP_PUBSUB_ENABLED` matches whether you use the outbox (sample is `true`)  
