#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE_PATH="${BUNDLE_PATH:-}"
DATABASE_URL="${DATABASE_URL:-}"
UPLOADS_DIR="${UPLOADS_DIR:-}"

if [ $# -gt 0 ] && [ -z "${BUNDLE_PATH}" ]; then
  BUNDLE_PATH="$1"
fi
if [ $# -gt 1 ] && [ -z "${DATABASE_URL}" ]; then
  DATABASE_URL="$2"
fi
if [ $# -gt 2 ] && [ -z "${UPLOADS_DIR}" ]; then
  UPLOADS_DIR="$3"
fi

if [ -z "${BUNDLE_PATH}" ] || [ -z "${DATABASE_URL}" ]; then
  echo "用法：BUNDLE_PATH=/path/to/old-to-new.tar.gz DATABASE_URL=postgres://... UPLOADS_DIR=/srv/app/uploads bash scripts/post_import_verify.sh"
  echo "也可以：bash scripts/post_import_verify.sh /path/to/old-to-new.tar.gz postgres://... /srv/app/uploads"
  exit 1
fi

if [ ! -f "${BUNDLE_PATH}" ]; then
  echo "找不到迁移包：${BUNDLE_PATH}"
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "缺少 tar。"
  exit 1
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "缺少 psql。"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

tar -xzf "${BUNDLE_PATH}" -C "${TMP_DIR}"
ROOT_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "${ROOT_DIR}" ]; then
  echo "无法找到迁移包根目录。"
  exit 1
fi

declare -A OLD_COUNTS=()
while IFS=$'\t' read -r table count; do
  [ -z "${table}" ] && continue
  OLD_COUNTS["${table}"]="${count:-0}"
done < "${ROOT_DIR}/db-table-counts.tsv"

query_count() {
  local table="$1"
  psql "${DATABASE_URL}" -Atc "SELECT COUNT(*) FROM public.${table}" 2>/dev/null
}

table_exists() {
  local table="$1"
  psql "${DATABASE_URL}" -Atc "SELECT to_regclass('public.${table}') IS NOT NULL" 2>/dev/null
}

status_fail=0

check_exact_tables=(
  "public.users"
  "public.students"
  "public.classes"
  "public.subjects"
  "public.homeworks"
  "public.homework_submissions"
  "public.course_materials"
  "public.notifications"
)

check_min_tables=(
  "public.course_enrollments"
)

echo "开始核对导入后的数据库。"

for full_name in "${check_exact_tables[@]}"; do
  short_name="${full_name#public.}"
  old_value="${OLD_COUNTS["${full_name}"]:-}"
  if [ -z "${old_value}" ]; then
    echo "跳过：旧包里没有表统计 ${full_name}"
    continue
  fi
  if [ "$(table_exists "${short_name}")" != "t" ]; then
    echo "失败：新库缺少表 ${full_name}"
    status_fail=1
    continue
  fi
  new_value="$(query_count "${short_name}")"
  if [ "${old_value}" != "${new_value}" ]; then
    echo "失败：${full_name} 行数不一致，旧=${old_value} 新=${new_value}"
    status_fail=1
  else
    echo "通过：${full_name} 行数一致，=${new_value}"
  fi
done

for full_name in "${check_min_tables[@]}"; do
  short_name="${full_name#public.}"
  old_value="${OLD_COUNTS["${full_name}"]:-}"
  if [ -z "${old_value}" ]; then
    echo "跳过：旧包里没有表统计 ${full_name}"
    continue
  fi
  if [ "$(table_exists "${short_name}")" != "t" ]; then
    echo "失败：新库缺少表 ${full_name}"
    status_fail=1
    continue
  fi
  new_value="$(query_count "${short_name}")"
  if [ "${new_value}" -lt "${old_value}" ]; then
    echo "失败：${full_name} 新库数量更少，旧=${old_value} 新=${new_value}"
    status_fail=1
  else
    echo "通过：${full_name} 新库数量不小于旧库，旧=${old_value} 新=${new_value}"
  fi
done

attachment_ref_count="$(grep -cve '^[[:space:]]*$' "${ROOT_DIR}/attachment-references.tsv" || true)"
echo "旧包附件引用行数：${attachment_ref_count}"

if [ -n "${UPLOADS_DIR}" ]; then
  uploads_parent="$(dirname "${UPLOADS_DIR}")"
  inventory_path="${ROOT_DIR}/upload-relative-inventory.txt"
  if [ ! -f "${inventory_path}" ]; then
    echo "失败：旧包缺少 upload-relative-inventory.txt"
    status_fail=1
  else
    total_files=0
    missing_files=0
    while IFS= read -r rel_path || [ -n "${rel_path}" ]; do
      [ -z "${rel_path}" ] && continue
      total_files=$((total_files + 1))
      if [ ! -f "${uploads_parent}/${rel_path}" ]; then
        missing_files=$((missing_files + 1))
        if [ "${missing_files}" -le 20 ]; then
          echo "缺失附件：${uploads_parent}/${rel_path}"
        fi
      fi
    done < "${inventory_path}"

    if [ "${missing_files}" -gt 0 ]; then
      echo "失败：附件文件缺失 ${missing_files}/${total_files}"
      status_fail=1
    else
      echo "通过：附件文件清单 ${total_files} 个全部存在。"
    fi
  fi
else
  echo "未提供 UPLOADS_DIR，跳过附件落盘核对。"
fi

if [ "${status_fail}" -ne 0 ]; then
  echo "迁移验证失败，请先修复上述差异。"
  exit 1
fi

echo "迁移验证通过。"
