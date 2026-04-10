#!/usr/bin/env bash
# Run Flyway locally using the same SQL as the mcart-bootstrap Helm chart (Docker required).
# Connection comes ONLY from env vars below — editing comments in this file does nothing.
#
# Flyway runs INSIDE a throwaway Docker container. "localhost" there is NOT your machine and
# NOT your Postgres container — use host.docker.internal (this script maps it on Linux).
#
# 1) One-time: create DB + app user (Postgres superuser is usually postgres — adjust container name):
#    docker exec -i postgres-db psql -U postgres <<'SQL'
#    CREATE USER auth_user WITH PASSWORD 'auth_password';
#    CREATE DATABASE auth OWNER auth_user;
#    GRANT ALL PRIVILEGES ON DATABASE auth TO auth_user;
#    SQL
#
# 1b) User service DB (same container; "user" is quoted — reserved word in SQL):
#    docker exec -i postgres-db psql -U postgres <<'SQL'
#    CREATE USER user_user WITH PASSWORD 'user_password';
#    CREATE DATABASE "user" OWNER user_user;
#    GRANT ALL PRIVILEGES ON DATABASE "user" TO user_user;
#    SQL
#    If user_user already exists but the password is wrong: ALTER USER user_user WITH PASSWORD 'user_password';
#
# 2) Run migrations (example: Postgres published as host 5433 -> container 5432):
#    export FLYWAY_URL='jdbc:postgresql://host.docker.internal:5433/auth'
#    export FLYWAY_USER='auth_user'
#    export FLYWAY_PASSWORD='auth_password'
#    ./scripts/run-flyway-local.sh auth
#
#    export FLYWAY_URL='jdbc:postgresql://host.docker.internal:5433/user'
#    export FLYWAY_USER='user_user'
#    export FLYWAY_PASSWORD='user_password'
#    ./scripts/run-flyway-local.sh user
#
#    Same pattern for: inventory, cart, payment, order (see values-postgresql for DB names and users).
#
# If Flyway is ever run on the host JVM (not this script), use localhost instead of host.docker.internal.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$(cd "$SCRIPT_DIR/.." && pwd)"
DB="${1:?usage: $0 auth|user|inventory|cart|payment|order}"
case "$DB" in auth|user|inventory|cart|payment|order) ;; *) echo "Invalid DB: $DB"; exit 1;; esac
SQL_DIR="$DEPLOY/helm/mcart-bootstrap/files/$DB"
test -d "$SQL_DIR" || { echo "Missing $SQL_DIR"; exit 1; }
: "${FLYWAY_URL:?Set FLYWAY_URL (jdbc:postgresql://...)}"
: "${FLYWAY_USER:?Set FLYWAY_USER}"
: "${FLYWAY_PASSWORD:?Set FLYWAY_PASSWORD}"
echo "Flyway using FLYWAY_URL=$FLYWAY_URL" >&2
# Keep in sync with deploy/helm/mcart-bootstrap/values.yaml flyway.tag
TAG="10.21.0-alpine"
docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  -v "$SQL_DIR:/flyway/sql:ro" \
  -e "FLYWAY_URL=$FLYWAY_URL" \
  -e "FLYWAY_USER=$FLYWAY_USER" \
  -e "FLYWAY_PASSWORD=$FLYWAY_PASSWORD" \
  "flyway/flyway:$TAG" migrate
