#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/root/dd-class}"
BRANCH="${BRANCH:-main}"

cd "${REPO_DIR}"

git fetch --all --prune
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

bash scripts/deploy_all.sh
