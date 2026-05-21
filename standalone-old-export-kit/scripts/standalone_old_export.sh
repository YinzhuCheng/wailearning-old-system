#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# 旧系统独立导出脚本。
# 不要求旧系统仓库更新；只要求在旧服务器 root 登录后运行。
# 如果不记得数据库密码，本脚本会从 .env.production / .env 读取 DATABASE_URL。
###############################################################################

APP_NAME="${APP_NAME:-wailearning-old-system}"
ENV_FILE="${ENV_FILE:-/opt/wailearning-old-system/current/.env.production}"
RELEASE_DIR="${RELEASE_DIR:-/opt/wailearning-old-system/current}"
OUT_DIR="${OUT_DIR:-/root/wailearning-migration}"
LABEL="${LABEL:-old-to-new-$(date +%Y%m%d%H%M%S)}"
EXTRA_UPLOAD_DIRS="${EXTRA_UPLOAD_DIRS:-}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-0}"

WORK_DIR="${OUT_DIR}/${LABEL}"
BUNDLE_PATH="${OUT_DIR}/${LABEL}.tar.gz"

on_error() {
  local code="$?"
  local line="$1"
  echo "导出失败：脚本第 ${line} 行出错，退出码 ${code}。"
  echo "如需排查，请保留 Workbench 最近 200 行输出。"
}
trap 'on_error $LINENO' ERR

if [ "$(id -u)" -ne 0 ] && [ "${ALLOW_NON_ROOT}" != "1" ]; then
  echo "请用 root 用户运行。Workbench 请确认已经 root 登录。"
  exit 1
fi

install_pkg() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
  else
    echo "未识别包管理器，无法自动安装：$*"
    exit 1
  fi
}

ensure_tools() {
  if ! command -v tar >/dev/null 2>&1; then
    install_pkg tar
  fi
  if ! command -v pg_dump >/dev/null 2>&1; then
    echo "未找到 pg_dump，尝试安装 PostgreSQL client。"
    if command -v apt-get >/dev/null 2>&1; then
      install_pkg postgresql-client
    else
      install_pkg postgresql
    fi
  fi
  if ! command -v psql >/dev/null 2>&1; then
    echo "警告：未找到 psql，将跳过附件引用清单和表统计。"
  fi
}

first_existing_file() {
  for path in "$@"; do
    if [ -n "${path}" ] && [ -f "${path}" ]; then
      echo "${path}"
      return 0
    fi
  done
  return 1
}

find_env_file() {
  local found
  found="$(first_existing_file \
    "${ENV_FILE}" \
    "/opt/wailearning-old-system/current/.env.production" \
    "/opt/wailearning-old-system/current/.env" \
    "/opt/dd-class/shared/.env.production" \
    "/opt/dd-class/current/.env.production" \
    "/opt/dd-class/.env.production" || true)"
  if [ -n "${found}" ]; then
    echo "${found}"
    return 0
  fi

  find /opt /root \
    \( -name ".env.production" -o -name ".env" \) \
    -type f 2>/dev/null | head -n 1
}

load_env_file() {
  local env_file="$1"
  local key
  local value

  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    raw_line="${raw_line%$'\r'}"
    raw_line="${raw_line#$'\ufeff'}"
    raw_line="${raw_line#"${raw_line%%[![:space:]]*}"}"
    raw_line="${raw_line%"${raw_line##*[![:space:]]}"}"
    if [ -z "${raw_line}" ] || [[ "${raw_line}" == \#* ]]; then
      continue
    fi
    if [[ "${raw_line}" != *=* ]]; then
      continue
    fi
    key="${raw_line%%=*}"
    value="${raw_line#*=}"
    key="${key//[[:space:]]/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    case "${key}" in
      DATABASE_URL|UPLOADS_DIR|SECRET_KEY|APP_NAME)
        export "${key}=${value}"
        ;;
    esac
  done < "${env_file}"
}

find_database_url_in_files() {
  grep -Rhs "DATABASE_URL=" /opt /etc/systemd/system /root 2>/dev/null \
    | head -n 1 \
    | sed 's/^.*DATABASE_URL=//' \
    | sed 's/[[:space:]]*$//' \
    | sed 's/^"//' \
    | sed 's/"$//'
}

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

  if ! command -v psql >/dev/null 2>&1; then
    return 0
  fi

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

write_table_counts() {
  if ! command -v psql >/dev/null 2>&1; then
    echo "psql 不存在，跳过表统计。" > "${WORK_DIR}/db-table-counts.tsv"
    return 0
  fi

  psql "${DATABASE_URL}" -At > "${WORK_DIR}/db-table-counts.tsv" <<'SQL_EOF' || true
SELECT schemaname || '.' || relname || E'\t' || n_live_tup::text
FROM pg_stat_user_tables
ORDER BY relname;
SQL_EOF
}

snapshot_runtime() {
  {
    echo "date=$(date -Is)"
    echo "host=$(hostname 2>/dev/null || true)"
    echo "user=$(id 2>/dev/null || true)"
    echo "pwd=$(pwd)"
    echo "kernel=$(uname -a 2>/dev/null || true)"
    echo "pg_dump=$(pg_dump --version 2>/dev/null || true)"
    echo "psql=$(psql --version 2>/dev/null || true)"
    echo "python=$(python3 --version 2>/dev/null || true)"
    echo "node=$(node --version 2>/dev/null || true)"
    echo "git=$(git --version 2>/dev/null || true)"
  } > "${WORK_DIR}/runtime.txt"
}

snapshot_configs() {
  if [ -f "${ENV_FILE}" ]; then
    cp "${ENV_FILE}" "${WORK_DIR}/old-env-file"
  fi

  mkdir -p "${WORK_DIR}/systemd" "${WORK_DIR}/nginx"
  for svc in \
    "${APP_NAME}.service" \
    "wailearning-old-system.service" \
    "ddclass-backend.service"
  do
    systemctl cat "${svc}" > "${WORK_DIR}/systemd/${svc}.txt" 2>/dev/null || true
  done

  if [ -d /etc/nginx/conf.d ]; then
    cp -a /etc/nginx/conf.d "${WORK_DIR}/nginx/" 2>/dev/null || true
  fi
  if [ -d /etc/nginx/sites-enabled ]; then
    cp -a /etc/nginx/sites-enabled "${WORK_DIR}/nginx/" 2>/dev/null || true
  fi

  if [ -d "${RELEASE_DIR}/.git" ] || git -C "${RELEASE_DIR}" rev-parse >/dev/null 2>&1; then
    git -C "${RELEASE_DIR}" rev-parse HEAD > "${WORK_DIR}/old-git-commit.txt" 2>/dev/null || true
    git -C "${RELEASE_DIR}" remote -v > "${WORK_DIR}/old-git-remotes.txt" 2>/dev/null || true
  fi
}

collect_upload_dirs() {
  local stage_dir="$1"
  local parent_dir
  parent_dir="$(dirname "${RELEASE_DIR}")"

  : > "${WORK_DIR}/upload-roots-included.txt"
  copy_upload_root "${UPLOADS_DIR:-}" "${stage_dir}"
  copy_upload_root "${RELEASE_DIR}/uploads" "${stage_dir}"
  copy_upload_root "${parent_dir}/uploads" "${stage_dir}"
  copy_upload_root "${parent_dir}/shared/uploads" "${stage_dir}"
  copy_upload_root "/opt/${APP_NAME}/uploads" "${stage_dir}"
  copy_upload_root "/opt/${APP_NAME}/shared/uploads" "${stage_dir}"
  copy_upload_root "/opt/dd-class/uploads" "${stage_dir}"
  copy_upload_root "/opt/dd-class/shared/uploads" "${stage_dir}"

  if [ -n "${EXTRA_UPLOAD_DIRS}" ]; then
    IFS=':' read -r -a extra_dirs <<< "${EXTRA_UPLOAD_DIRS}"
    for extra_dir in "${extra_dirs[@]}"; do
      copy_upload_root "${extra_dir}" "${stage_dir}"
    done
  fi

  while IFS= read -r auto_dir; do
    copy_upload_root "${auto_dir}" "${stage_dir}"
  done < <(find /opt /root -type d -name uploads 2>/dev/null || true)
}

write_manifest() {
  cat > "${WORK_DIR}/manifest.txt" <<MANIFEST_EOF
exported_at=$(date -Is)
app_name=${APP_NAME}
env_file=${ENV_FILE}
release_dir=${RELEASE_DIR}
out_dir=${OUT_DIR}
label=${LABEL}
database_dump=old-system.dump
uploads_archive=old-uploads.tar.gz
upload_roots_list=upload-roots-included.txt
attachment_references=attachment-references.tsv
table_counts=db-table-counts.tsv
MANIFEST_EOF
}

write_readme() {
  cat > "${WORK_DIR}/README.txt" <<'README_EOF'
旧系统独立导出包

这个包由 standalone_old_export.sh 生成，不要求旧系统仓库更新。

核心文件：
- old-system.dump：PostgreSQL 自定义格式备份，可用 pg_restore 导入。
- old-uploads.tar.gz：尽量收集到的 uploads 文件。
- old-env-file：旧系统环境变量文件快照，可能包含密码，请妥善保管。
- upload-roots-included.txt：实际被扫描/收集的附件目录。
- attachment-references.tsv：数据库里记录的附件引用。
- db-table-counts.tsv：导出时的表统计，用于迁移后粗略核对。
- runtime.txt：导出机器和工具版本。
- systemd/、nginx/：旧部署配置快照。

建议：
1. 把整个 tar.gz 复制到新系统服务器。
2. 用新系统迁移导入脚本恢复 old-system.dump。
3. 解压 old-uploads.tar.gz 到新系统 UPLOADS_DIR 的父目录。
4. 新系统启动后，核对学生、用户、课程、作业、通知和附件。
README_EOF
}

ENV_FILE_FOUND="$(find_env_file || true)"
if [ -n "${ENV_FILE_FOUND}" ]; then
  ENV_FILE="${ENV_FILE_FOUND}"
  echo "使用环境文件：${ENV_FILE}"
  load_env_file "${ENV_FILE}"
else
  echo "未自动找到 .env.production / .env。"
fi

if [ ! -d "${RELEASE_DIR}" ] && [ -f "${ENV_FILE:-}" ]; then
  RELEASE_DIR="$(dirname "${ENV_FILE}")"
  echo "RELEASE_DIR 不存在，改用环境文件所在目录：${RELEASE_DIR}"
fi

if [ -z "${DATABASE_URL:-}" ]; then
  DATABASE_URL="$(find_database_url_in_files || true)"
fi
if [ -z "${DATABASE_URL:-}" ]; then
  echo "找不到 DATABASE_URL。请在脚本开头设置 DATABASE_URL 后重跑。"
  exit 1
fi
export DATABASE_URL

mkdir -p "${WORK_DIR}"
ensure_tools

echo "开始导出旧系统数据库。"
pg_dump -Fc -f "${WORK_DIR}/old-system.dump" "${DATABASE_URL}"

echo "开始收集旧系统 uploads/附件文件。"
UPLOADS_STAGE="${WORK_DIR}/uploads-stage/uploads"
mkdir -p "${WORK_DIR}/uploads-stage"
collect_upload_dirs "${UPLOADS_STAGE}"
if [ ! -d "${UPLOADS_STAGE}" ]; then
  mkdir -p "${UPLOADS_STAGE}"
fi
tar -czf "${WORK_DIR}/old-uploads.tar.gz" -C "${WORK_DIR}/uploads-stage" uploads
find "${UPLOADS_STAGE}" -type f > "${WORK_DIR}/upload-file-inventory.txt" 2>/dev/null || true

echo "开始导出附件引用和表统计。"
: > "${WORK_DIR}/attachment-references.tsv"
append_attachment_refs "homeworks"
append_attachment_refs "homework_submissions"
append_attachment_refs "course_materials"
append_attachment_refs "materials"
append_attachment_refs "notifications"
write_table_counts

echo "保存旧系统运行配置快照。"
snapshot_runtime
snapshot_configs
write_manifest
write_readme

rm -rf "${WORK_DIR}/uploads-stage"
tar -czf "${BUNDLE_PATH}" -C "${OUT_DIR}" "${LABEL}"

echo
echo "导出完成。"
echo "迁移包：${BUNDLE_PATH}"
ls -lh "${BUNDLE_PATH}" 2>/dev/null || true
echo "请把这个 tar.gz 复制到新系统服务器后执行导入。"
