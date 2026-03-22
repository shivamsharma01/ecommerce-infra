#!/usr/bin/env bash
# Run Flyway locally using the same SQL as the mcart-bootstrap Helm chart (Docker required).
# Example (auth DB):
#   export FLYWAY_URL='jdbc:postgresql://localhost:5432/auth'
#   export FLYWAY_USER='auth_user'
#   export FLYWAY_PASSWORD='your-password'
#   ./scripts/run-flyway-local.sh auth
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$(cd "$SCRIPT_DIR/.." && pwd)"
DB="${1:?usage: $0 auth|user}"
case "$DB" in auth|user) ;; *) echo "Argument must be auth or user"; exit 1;; esac
SQL_DIR="$DEPLOY/helm/mcart-bootstrap/files/$DB"
test -d "$SQL_DIR" || { echo "Missing $SQL_DIR"; exit 1; }
: "${FLYWAY_URL:?Set FLYWAY_URL (jdbc:postgresql://...)}"
: "${FLYWAY_USER:?Set FLYWAY_USER}"
: "${FLYWAY_PASSWORD:?Set FLYWAY_PASSWORD}"
# Keep in sync with deploy/helm/mcart-bootstrap/values.yaml flyway.tag
TAG="10.21.0-alpine"
docker run --rm \
  -v "$SQL_DIR:/flyway/sql:ro" \
  -e "FLYWAY_URL=$FLYWAY_URL" \
  -e "FLYWAY_USER=$FLYWAY_USER" \
  -e "FLYWAY_PASSWORD=$FLYWAY_PASSWORD" \
  "flyway/flyway:$TAG" migrate
