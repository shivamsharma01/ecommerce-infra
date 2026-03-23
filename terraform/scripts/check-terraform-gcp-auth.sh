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

echo "=== Application Default Credentials (used by Terraform Google provider) ==="
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "  GOOGLE_APPLICATION_CREDENTIALS is SET → Terraform uses this key file:"
  echo "    ${GOOGLE_APPLICATION_CREDENTIALS}"
  echo "  That service account must have roles on **${PROJECT_ID}** (e.g. Editor)."
else
  echo "  GOOGLE_APPLICATION_CREDENTIALS unset → Terraform uses ADC (usually ~/.config/gcloud/application_default_credentials.json)"
fi

ADC="${HOME}/.config/gcloud/application_default_credentials.json"
if [[ -f "${ADC}" ]]; then
  if command -v jq >/dev/null 2>&1; then
    QP="$(jq -r '.quota_project_id // empty' "${ADC}" 2>/dev/null || true)"
    echo "  ADC quota_project_id: ${QP:-<missing>}"
    if [[ -n "${QP}" && "${QP}" != "${PROJECT_ID}" ]]; then
      echo ""
      echo "  *** MISMATCH: quota project is '${QP}' but Terraform uses project_id '${PROJECT_ID}'."
      echo "  IAM/Compute calls may hit the wrong project → enable IAM API / IAM errors on another number."
      echo "  Fix (user ADC):"
      echo "    gcloud auth application-default set-quota-project ${PROJECT_ID}"
    fi
  else
    echo "  (install jq to show quota_project_id from ADC JSON)"
  fi
else
  echo "  No ADC file at ${ADC} — run: gcloud auth application-default login"
fi

echo ""
echo "=== If errors mention a different project NUMBER ==="
echo "  Compare that number to '${PN}' above."
echo "  If they differ, fix ADC quota project (see above) or stop using a key from another project."
echo ""
echo "=== IAM role check ==="
echo "  The principal Terraform uses needs **roles/editor** (or Owner) on **${PROJECT_ID}**."
echo "  The account that ran ./scripts/enable-apis.sh is NOT necessarily the same as ADC — align them."
