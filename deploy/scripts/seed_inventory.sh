#!/usr/bin/env bash
set -euo pipefail

# Seed inventory quantities for demo products.
#
# Required:
#   BASE_URL   e.g. https://mcart.space   (or http://localhost:8086 if port-forward)
#   TOKEN      Bearer access token with scope product.admin (platform admin)
#
# Usage:
#   BASE_URL="https://mcart.space" TOKEN="..." ./seed_inventory.sh PABC123=10 PDEF456=2

BASE_URL="${BASE_URL:-}"
TOKEN="${TOKEN:-}"

if [[ -z "${BASE_URL}" || -z "${TOKEN}" ]]; then
  echo "Set BASE_URL and TOKEN."
  exit 1
fi

authz="Authorization: Bearer ${TOKEN}"

if [[ $# -lt 1 ]]; then
  echo "Pass productId=qty pairs, e.g. PXXXX=5"
  exit 1
fi

for pair in "$@"; do
  pid="${pair%%=*}"
  qty="${pair#*=}"
  if [[ -z "${pid}" || -z "${qty}" ]]; then
    echo "Bad pair: ${pair} (expected productId=qty)"
    exit 1
  fi
  echo "Seeding inventory: ${pid} -> ${qty}"
  curl -fsS -X POST "${BASE_URL}/inventory/init" \
    -H "${authz}" \
    -H "Content-Type: application/json" \
    -d "{\"productId\":\"${pid}\",\"availableQty\":${qty}}"
  echo
done

echo "Done."

