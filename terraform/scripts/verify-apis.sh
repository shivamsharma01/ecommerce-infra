#!/usr/bin/env bash
# Quick check that expected APIs are enabled (run after enable-apis.sh).
set -euo pipefail
PROJECT_ID="${1:-}"
[[ -z "${PROJECT_ID}" ]] && PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "Usage: $0 <PROJECT_ID>"
  exit 1
fi

need=(iam.googleapis.com compute.googleapis.com container.googleapis.com pubsub.googleapis.com apigateway.googleapis.com)
echo "Checking enabled APIs on ${PROJECT_ID}..."
enabled="$(gcloud services list --enabled --project="${PROJECT_ID}" --format='value(config.name)' 2>/dev/null || true)"
missing=()
for s in "${need[@]}"; do
  if echo "${enabled}" | grep -qx "${s}"; then
    echo "  OK  ${s}"
  else
    echo "  MISSING ${s}"
    missing+=("${s}")
  fi
done
if ((${#missing[@]})); then
  echo ""
  echo "Run: ./scripts/enable-apis.sh ${PROJECT_ID}"
  exit 1
fi
echo "All checked APIs are enabled."
