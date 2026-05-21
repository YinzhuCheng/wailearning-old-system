#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE_PATH="${1:-${BUNDLE_PATH:-}}"

if [ -z "${BUNDLE_PATH}" ]; then
  echo "用法：bash scripts/verify_export_bundle.sh /root/wailearning-migration/old-to-new-20260521120000.tar.gz"
  exit 1
fi

if [ ! -f "${BUNDLE_PATH}" ]; then
  echo "找不到迁移包：${BUNDLE_PATH}"
  exit 1
fi

compute_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
    return 0
  fi
  return 1
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "校验迁移包：${BUNDLE_PATH}"

if ! tar -tzf "${BUNDLE_PATH}" >/dev/null 2>&1; then
  echo "失败：外层 tar.gz 无法读取。"
  exit 1
fi

tar -xzf "${BUNDLE_PATH}" -C "${TMP_DIR}"
ROOT_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "${ROOT_DIR}" ]; then
  echo "失败：无法找到迁移包根目录。"
  exit 1
fi

required_files=(
  "manifest.txt"
  "README.txt"
  "old-system.dump"
  "old-uploads.tar.gz"
  "upload-roots-included.txt"
  "upload-relative-inventory.txt"
  "attachment-references.tsv"
  "attachment-reference-warnings.txt"
  "attachment-files-found.tsv"
  "attachment-files-missing.tsv"
  "db-table-counts.tsv"
  "runtime.txt"
)

missing=0
for rel in "${required_files[@]}"; do
  if [ ! -f "${ROOT_DIR}/${rel}" ]; then
    echo "缺失文件：${rel}"
    missing=1
  fi
done
if [ "${missing}" -ne 0 ]; then
  exit 1
fi

if [ ! -s "${ROOT_DIR}/old-system.dump" ]; then
  echo "失败：old-system.dump 是空文件。"
  exit 1
fi

if ! tar -tzf "${ROOT_DIR}/old-uploads.tar.gz" >/dev/null 2>&1; then
  echo "失败：old-uploads.tar.gz 无法读取。"
  exit 1
fi

if [ -f "${ROOT_DIR}/checksums.sha256" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "${ROOT_DIR}"
      sha256sum -c checksums.sha256
    )
  elif command -v shasum >/dev/null 2>&1; then
    while IFS= read -r line || [ -n "${line}" ]; do
      [ -z "${line}" ] && continue
      expected="$(printf '%s' "${line}" | awk '{print $1}')"
      file_name="$(printf '%s' "${line}" | awk '{print $2}')"
      actual="$(compute_sha256 "${ROOT_DIR}/${file_name}")"
      if [ "${expected}" != "${actual}" ]; then
        echo "失败：内部文件 SHA256 不匹配：${file_name}"
        exit 1
      fi
    done < "${ROOT_DIR}/checksums.sha256"
  fi
fi

if [ -f "${BUNDLE_PATH}.sha256" ]; then
  expected_bundle="$(awk '{print $1}' "${BUNDLE_PATH}.sha256")"
  actual_bundle="$(compute_sha256 "${BUNDLE_PATH}" || true)"
  if [ -n "${expected_bundle}" ] && [ -n "${actual_bundle}" ] && [ "${expected_bundle}" != "${actual_bundle}" ]; then
    echo "失败：外层迁移包 SHA256 与同目录 .sha256 文件不一致。"
    exit 1
  fi
fi

bundle_sha256="$(compute_sha256 "${BUNDLE_PATH}" || true)"
bundle_size="$(du -h "${BUNDLE_PATH}" | awk '{print $1}')"
upload_count="$(wc -l < "${ROOT_DIR}/upload-relative-inventory.txt" | tr -d ' ')"
attachment_ref_count="$(grep -cve '^[[:space:]]*$' "${ROOT_DIR}/attachment-references.tsv" || true)"
attachment_found_count="$(grep -cve '^[[:space:]]*$' "${ROOT_DIR}/attachment-files-found.tsv" || true)"
attachment_missing_count="$(grep -cve '^[[:space:]]*$' "${ROOT_DIR}/attachment-files-missing.tsv" || true)"

echo "通过：迁移包结构和内部压缩包可读取。"
echo "大小：${bundle_size}"
if [ -n "${bundle_sha256}" ]; then
  echo "SHA256：${bundle_sha256}"
fi
echo "附件文件数：${upload_count}"
echo "附件引用行数：${attachment_ref_count}"
echo "附件引用已找到并打包：${attachment_found_count}"
echo "附件引用未找到真实文件：${attachment_missing_count}"
if [ "${attachment_missing_count}" != "0" ]; then
  echo "注意：attachment-files-missing.tsv 中的附件没有真正下载/打包，只记录了数据库引用。"
fi
echo "根目录：${ROOT_DIR##*/}"
