#!/usr/bin/env bash
set -Eeuo pipefail

on_error() {
  local line="$1"
  echo "迁移包导出失败：脚本第 ${line} 行出错。"
  echo "工作目录：${WORK_DIR:-尚未创建}"
}
trap 'on_error $LINENO' ERR

APP_NAME="${APP_NAME:-wailearning-old-system}"
ENV_FILE="${ENV_FILE:-/opt/wailearning-old-system/current/.env.production}"
RELEASE_DIR="${RELEASE_DIR:-/opt/wailearning-old-system/current}"
MIGRATION_OUTPUT_DIR="${MIGRATION_OUTPUT_DIR:-/root/wailearning-migration}"
MIGRATION_LABEL="${MIGRATION_LABEL:-old-to-new-$(date +%Y%m%d%H%M%S)}"

load_env_file() {
  local env_file="$1"
  local line key value
  if [ ! -f "${env_file}" ]; then
    echo "找不到环境文件：${env_file}"
    exit 1
  fi
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key//[[:space:]]/}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    export "${key}=${value}"
  done < "${env_file}"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令：$1"
    exit 1
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 用户运行。"
  exit 1
fi

load_env_file "${ENV_FILE}"
DATABASE_URL="${DATABASE_URL:-}"
UPLOADS_DIR="${UPLOADS_DIR:-/opt/wailearning-old-system/uploads}"

if [ -z "${DATABASE_URL}" ]; then
  echo "环境文件中缺少 DATABASE_URL。"
  exit 1
fi

require_cmd pg_dump
require_cmd tar

WORK_DIR="${MIGRATION_OUTPUT_DIR}/${MIGRATION_LABEL}"
BUNDLE_PATH="${MIGRATION_OUTPUT_DIR}/${MIGRATION_LABEL}.tar.gz"
mkdir -p "${WORK_DIR}"

echo "导出 PostgreSQL 数据库。"
pg_dump -Fc "${DATABASE_URL}" -f "${WORK_DIR}/old-system.dump"

echo "打包上传附件目录。"
if [ -d "${UPLOADS_DIR}" ]; then
  tar -czf "${WORK_DIR}/old-uploads.tar.gz" -C "$(dirname "${UPLOADS_DIR}")" "$(basename "${UPLOADS_DIR}")"
else
  echo "附件目录不存在，创建空附件包：${UPLOADS_DIR}"
  tar -czf "${WORK_DIR}/old-uploads.tar.gz" --files-from /dev/null
fi

echo "保存运行配置快照。"
cp "${ENV_FILE}" "${WORK_DIR}/old-env.production"
systemctl cat "${APP_NAME}.service" > "${WORK_DIR}/old-systemd.service" 2>/dev/null || true
cp "/etc/nginx/conf.d/${APP_NAME}.conf" "${WORK_DIR}/old-nginx.conf" 2>/dev/null || true
git -C "${RELEASE_DIR}" rev-parse HEAD > "${WORK_DIR}/old-git-commit.txt" 2>/dev/null || true

cat > "${WORK_DIR}/README.txt" <<README_EOF
旧系统迁移包

数据库备份：old-system.dump
附件备份：old-uploads.tar.gz
旧环境文件快照：old-env.production

建议复制整个压缩包到新系统服务器，再按新系统仓库 docs/migration/ALIYUN_WORKBENCH_IMPORT_MIGRATION_BUNDLE.txt 执行导入。
README_EOF

tar -czf "${BUNDLE_PATH}" -C "${MIGRATION_OUTPUT_DIR}" "${MIGRATION_LABEL}"

echo "迁移包导出完成：${BUNDLE_PATH}"
echo "请把该文件复制到新系统服务器，例如：scp ${BUNDLE_PATH} root@<NEW_ECS_IP>:/root/"
