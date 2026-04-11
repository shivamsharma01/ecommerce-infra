#!/usr/bin/env bash
# Idempotent: creates Kubernetes Secret auth-jwt-rsa only if it does not exist.
# Run once per cluster (or after intentional key rotation). Normal app deploys do not repeat this.
set -euo pipefail

NS="${K8S_NAMESPACE:-mcart}"
SECRET_NAME="${AUTH_JWT_RSA_SECRET_NAME:-auth-jwt-rsa}"
KEY_FILE="${AUTH_JWT_RSA_KEY_FILENAME:-rsa-private.pem}"

if kubectl -n "$NS" get secret "$SECRET_NAME" &>/dev/null; then
  echo "Secret $NS/$SECRET_NAME already exists — nothing to do."
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
openssl genrsa -out "$tmp" 2048
kubectl -n "$NS" create secret generic "$SECRET_NAME" --from-file="${KEY_FILE}=$tmp"
echo "Created $NS/$SECRET_NAME (one-time per cluster; redeployments reuse it)."
