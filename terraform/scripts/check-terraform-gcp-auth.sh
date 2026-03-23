#!/usr/bin/env bash
# Diagnose why Terraform gets 403 or "IAM API disabled" on a *different* project number than your tfvars project.
set -euo pipefail

PROJECT_ID="${1:-ecommerce-491019}"
echo "=== Target Terraform project ==="
echo "  project_id: ${PROJECT_ID}"
PN="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || echo '(cannot describe — check gcloud auth)')"
echo "  project number: ${PN}"
echo ""

echo "=== gcloud CLI (used by enable-apis.sh) ==="
echo "  active account(s):"
gcloud auth list --filter=status:ACTIVE --format='  - %(account)s' 2>/dev/null || true
echo "  gcloud core/project: $(gcloud config get-value project 2>/dev/null || echo '(unset)')"
echo ""

echo "=== Credentials Terraform actually uses (Google provider) ==="
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  KEY="${GOOGLE_APPLICATION_CREDENTIALS}"
  echo "  GOOGLE_APPLICATION_CREDENTIALS is SET — Terraform uses ONLY this key (ADC file is ignored):"
  echo "    ${KEY}"
  if [[ -f "${KEY}" ]] && command -v jq >/dev/null 2>&1; then
    SA_EMAIL="$(jq -r '.client_email // empty' "${KEY}" 2>/dev/null || true)"
    KEY_PROJECT="$(jq -r '.project_id // empty' "${KEY}" 2>/dev/null || true)"
    echo "  Service account in key: ${SA_EMAIL:-<parse failed>}"
    echo "  Key file project_id field: ${KEY_PROJECT:-<none>}"
    echo ""
    echo "  >>> Fix A (keep this key): grant that SA access to **${PROJECT_ID}** (run as Owner on ${PROJECT_ID}):"
    echo "      gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
    echo "        --member=\"serviceAccount:${SA_EMAIL}\" \\"
    echo "        --role=\"roles/editor\""
    echo ""
    echo "  >>> Fix B (use your user instead): unset the env var, then user ADC:"
    echo "      unset GOOGLE_APPLICATION_CREDENTIALS"
    echo "      gcloud auth application-default login"
    echo "      gcloud auth application-default set-quota-project ${PROJECT_ID}"
  else
    echo "  Install jq and ensure the file exists to print the service account email."
    echo "  That service account still needs roles/editor on **${PROJECT_ID}**."
  fi
else
  echo "  GOOGLE_APPLICATION_CREDENTIALS unset → Terraform uses ADC:"
  echo "    ${HOME}/.config/gcloud/application_default_credentials.json"
  ADC="${HOME}/.config/gcloud/application_default_credentials.json"
  if [[ -f "${ADC}" ]] && command -v jq >/dev/null 2>&1; then
    QP="$(jq -r '.quota_project_id // empty' "${ADC}" 2>/dev/null || true)"
    echo "  ADC quota_project_id: ${QP:-<missing>}"
    if [[ -n "${QP}" && "${QP}" != "${PROJECT_ID}" ]]; then
      echo ""
      echo "  *** MISMATCH: set quota project to Terraform project:"
      echo "      gcloud auth application-default set-quota-project ${PROJECT_ID}"
    fi
  elif [[ ! -f "${ADC}" ]]; then
    echo "  No ADC file — run: gcloud auth application-default login"
  fi
fi

echo ""
echo "=== If errors mention a different project NUMBER ==="
echo "  Compare to '${PN}' for ${PROJECT_ID}. Wrong number often means wrong SA key or quota project."
echo ""
echo "=== IAM role check ==="
echo "  Whoever Terraform authenticates as needs **roles/editor** (or Owner) on **${PROJECT_ID}**."
