#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-$DEPLOY_DIR/catalog/bootstrap.env}"
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy $DEPLOY_DIR/catalog/bootstrap.env.example -> $DEPLOY_DIR/catalog/bootstrap.env and edit values."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${PROJECT_ID:?Set PROJECT_ID in env file}"
: "${BUCKET:?Set BUCKET in env file}"

python3 "$DEPLOY_DIR/scripts/bootstrap_catalog.py" "$@"

