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

print_file_count() {
  local dir="$1"
  if [ ! -d "${dir}" ]; then
    echo 0
    return
  fi
  find "${dir}" -type f 2>/dev/null | wc -l | tr -d ' '
}

copy_upload_root() {
  local source_dir="$1"
  local stage_dir="$2"
  if [ -z "${source_dir}" ] || [ ! -d "${source_dir}" ]; then
    return 0
  fi

  local count
  count="$(print_file_count "${source_dir}")"
  if [ "${count}" = "0" ]; then
    echo "跳过空附件目录：${source_dir}" | tee -a "${WORK_DIR}/upload-roots-included.txt"
    return 0
  fi

  echo "收集附件目录：${source_dir}，文件数：${count}" | tee -a "${WORK_DIR}/upload-roots-included.txt"
  mkdir -p "${stage_dir}"
  cp -a "${source_dir}/." "${stage_dir}/"
}

append_attachment_refs() {
  local table="$1"
  local has_url
  local has_name
  local name_expr

  has_url="$(psql "${DATABASE_URL}" -Atc "
SELECT 1 FROM information_schema.columns
WHERE table_schema='public'
  AND table_name='${table}'
  AND column_name='attachment_url'
LIMIT 1" 2>/dev/null || true)"

  if [ "${has_url}" != "1" ]; then
    echo "跳过附件引用表：${table}，缺少 attachment_url 字段" \
      >> "${WORK_DIR}/attachment-references.tsv"
    return 0
  fi

  has_name="$(psql "${DATABASE_URL}" -Atc "
SELECT 1 FROM information_schema.columns
WHERE table_schema='public'
  AND table_name='${table}'
  AND column_name='attachment_name'
LIMIT 1" 2>/dev/null || true)"

  if [ "${has_name}" = "1" ]; then
    name_expr="COALESCE(attachment_name, '')"
  else
    name_expr="''"
  fi

  psql "${DATABASE_URL}" -Atc "
SELECT '${table}', id::text, ${name_expr}, COALESCE(attachment_url, '')
FROM ${table}
WHERE attachment_url IS NOT NULL AND attachment_url <> ''
ORDER BY id" >> "${WORK_DIR}/attachment-references.tsv" || true
}

echo "导出 PostgreSQL 数据库。"
pg_dump -Fc "${DATABASE_URL}" -f "${WORK_DIR}/old-system.dump"

echo "收集并打包上传附件目录。"
UPLOADS_STAGE="${WORK_DIR}/uploads-stage/uploads"
: > "${WORK_DIR}/upload-roots-included.txt"
copy_upload_root "${UPLOADS_DIR}" "${UPLOADS_STAGE}"
copy_upload_root "${RELEASE_DIR}/uploads" "${UPLOADS_STAGE}"
copy_upload_root "$(dirname "${RELEASE_DIR}")/uploads" "${UPLOADS_STAGE}"
copy_upload_root "$(dirname "${RELEASE_DIR}")/shared/uploads" "${UPLOADS_STAGE}"
copy_upload_root "/opt/${APP_NAME}/uploads" "${UPLOADS_STAGE}"
copy_upload_root "/opt/${APP_NAME}/shared/uploads" "${UPLOADS_STAGE}"

if [ -d "${UPLOADS_STAGE}" ]; then
  tar -czf "${WORK_DIR}/old-uploads.tar.gz" -C "${WORK_DIR}/uploads-stage" uploads
else
  echo "未发现可打包的附件目录，创建空附件包。"
  mkdir -p "${WORK_DIR}/uploads-stage/uploads"
  tar -czf "${WORK_DIR}/old-uploads.tar.gz" -C "${WORK_DIR}/uploads-stage" uploads
fi

if command -v psql >/dev/null 2>&1; then
  echo "导出数据库内附件引用清单。"
  : > "${WORK_DIR}/attachment-references.tsv"
  append_attachment_refs "homeworks"
  append_attachment_refs "homework_submissions"
  append_attachment_refs "course_materials"
  append_attachment_refs "notifications"
else
  echo "psql 不存在，跳过附件引用清单。" > "${WORK_DIR}/attachment-references.tsv"
fi

echo "保存运行配置快照。"
cp "${ENV_FILE}" "${WORK_DIR}/old-env.production"
systemctl cat "${APP_NAME}.service" > "${WORK_DIR}/old-systemd.service" 2>/dev/null || true
cp "/etc/nginx/conf.d/${APP_NAME}.conf" "${WORK_DIR}/old-nginx.conf" 2>/dev/null || true
git -C "${RELEASE_DIR}" rev-parse HEAD > "${WORK_DIR}/old-git-commit.txt" 2>/dev/null || true

cat > "${WORK_DIR}/manifest.txt" <<MANIFEST_EOF
exported_at=$(date -Is)
app_name=${APP_NAME}
env_file=${ENV_FILE}
release_dir=${RELEASE_DIR}
migration_label=${MIGRATION_LABEL}
database_dump=old-system.dump
uploads_archive=old-uploads.tar.gz
upload_roots_list=upload-roots-included.txt
attachment_references=attachment-references.tsv
MANIFEST_EOF

cat > "${WORK_DIR}/README.txt" <<README_EOF
旧系统迁移包

数据库备份：old-system.dump
附件备份：old-uploads.tar.gz
旧环境文件快照：old-env.production
导出清单：manifest.txt
实际收集到的附件目录：upload-roots-included.txt
数据库内附件引用：attachment-references.tsv

建议复制整个压缩包到新系统服务器。
再按新系统仓库 docs/migration/ALIYUN_WORKBENCH_IMPORT_MIGRATION_BUNDLE.txt 执行导入。
README_EOF

tar -czf "${BUNDLE_PATH}" -C "${MIGRATION_OUTPUT_DIR}" "${MIGRATION_LABEL}"

echo "迁移包导出完成：${BUNDLE_PATH}"
echo "请把该文件复制到新系统服务器，例如：scp ${BUNDLE_PATH} root@<NEW_ECS_IP>:/root/"
