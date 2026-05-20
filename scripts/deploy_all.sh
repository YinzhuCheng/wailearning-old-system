#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

for script in deploy_backend.sh deploy_frontend.sh deploy_parent_portal.sh; do
  echo "==> Running ${script}"
  bash "${SCRIPT_DIR}/${script}"
done

echo "==> Deployment finished."
echo "Run bash ${SCRIPT_DIR}/post_deploy_check.sh to verify the stack."
