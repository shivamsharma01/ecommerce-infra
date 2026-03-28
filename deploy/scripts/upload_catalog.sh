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

PYTHON=python3
if ! python3 -c "import google.cloud.firestore, google.cloud.storage" 2>/dev/null; then
  VENV="${DEPLOY_DIR}/.venv-catalog"
  if [[ ! -x "${VENV}/bin/python" ]]; then
    echo "Creating Python venv for catalog bootstrap at ${VENV}..."
    python3 -m venv "${VENV}"
  fi
  PYTHON="${VENV}/bin/python"
  if ! "${PYTHON}" -c "import google.cloud.firestore, google.cloud.storage" 2>/dev/null; then
    echo "Installing google-cloud-firestore and google-cloud-storage into venv..."
    "${VENV}/bin/pip" install -q -r "${DEPLOY_DIR}/catalog/requirements-bootstrap.txt"
  fi
fi

"${PYTHON}" "$DEPLOY_DIR/scripts/bootstrap_catalog.py" "$@"

