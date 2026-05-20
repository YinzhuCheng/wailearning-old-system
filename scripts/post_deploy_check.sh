#!/usr/bin/env bash
set -euo pipefail

APP_URL="${APP_URL:-https://wailearning.xyz}"
API_HEALTH_URL="${API_HEALTH_URL:-${APP_URL}/health}"
BACKEND_SERVICE="${BACKEND_SERVICE:-ddclass-backend}"

echo "==> systemd status"
systemctl --no-pager --full status "${BACKEND_SERVICE}" || true

echo "==> local backend health"
curl -fsS http://127.0.0.1:8001/health
echo

echo "==> public health"
curl -fsS "${API_HEALTH_URL}"
echo

echo "==> nginx config test"
nginx -t

echo "==> recent backend logs"
journalctl -u "${BACKEND_SERVICE}" -n 30 --no-pager || true
