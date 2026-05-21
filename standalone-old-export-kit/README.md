# wailearning migration kit

优先入口：

- `index.html`
- `exporter-pack/00_START_HERE_EXPORTER.html`

旧系统独立导出工具包。

这个工具包不要求旧系统仓库更新。旧系统维护者只要能在阿里云 Workbench
用 `root` 登录旧服务器，就可以导出数据库、上传附件和部署配置快照，
然后把迁移包下载到 Windows，再上传到新系统服务器做导入和核对。

## 文件说明

- `01_WORKBENCH_COPY_PASTE_EXPORT.txt`
  - 完整复制粘贴版。
  - 不依赖 GitHub 下载脚本。
  - 适合第一次交给旧系统维护者执行。

- `02_WORKBENCH_DOWNLOAD_SCRIPT_EXPORT.txt`
  - 下载脚本版。
  - 会从公开 GitHub raw 下载 `scripts/standalone_old_export.sh` 后执行。
  - 适合后续修订脚本后快速复用。

- `scripts/standalone_old_export.sh`
  - 独立导出脚本。
  - 会从 `.env.production` / `.env` 读取 `DATABASE_URL`。
  - 会尽量收集 `uploads` 附件目录、systemd/nginx/git 快照和表统计。
  - 会额外生成 `upload-relative-inventory.txt`、`checksums.sha256` 和外层包的 `.sha256`。

- `scripts/verify_export_bundle.sh`
  - 在旧服务器校验导出包是否完整、是否可解压、内部关键文件是否匹配 SHA256。

- `scripts/windows_verify_bundle.ps1`
  - 在 Windows 上校验下载后的 `tar.gz` 是否完整。
  - 可读取同目录 `.sha256` 文件，也可以直接传入期望 SHA256。

- `scripts/post_import_verify.sh`
  - 在新系统服务器导入后做迁移验证。
  - 对账旧包里的 `db-table-counts.tsv` 与新库实际数据量。
  - 可选检查 `old-uploads.tar.gz` 内文件是否都已落到新系统 `UPLOADS_DIR`。

- `docs/old_export_guide.html`
  - 导出、下载、导入后校验的一体化说明文档。
  - 如果迁移失败，可以把该 HTML、操作流 txt 和终端报错交给 LLM 排错。

## 推荐执行方式

优先使用 `01_WORKBENCH_COPY_PASTE_EXPORT.txt`。
它把脚本完整内嵌在操作流里，不要求旧系统服务器能访问本仓库。

如果后续要用脚本版，再使用 `02_WORKBENCH_DOWNLOAD_SCRIPT_EXPORT.txt`。
该方式只是从公开 GitHub 下载独立脚本，不要求旧系统服务器更新本地仓库。

## 完整流程

1. 在旧服务器执行导出，生成迁移包：

```text
/root/wailearning-migration/old-to-new-YYYYMMDDHHMMSS.tar.gz
```

同时会生成同目录校验文件：

```text
/root/wailearning-migration/old-to-new-YYYYMMDDHHMMSS.tar.gz.sha256
```

2. 在旧服务器先做一次导出包校验：

```bash
bash scripts/verify_export_bundle.sh /root/wailearning-migration/old-to-new-YYYYMMDDHHMMSS.tar.gz
```

3. 从旧服务器把这两个文件下载到 Windows：

- `old-to-new-....tar.gz`
- `old-to-new-....tar.gz.sha256`

如果使用阿里云 Workbench，优先直接在文件管理器里下载。
如果 Workbench 不方便下载，再用 `scp` / `sftp` 拉到 Windows。

4. 在 Windows 上校验下载文件：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows_verify_bundle.ps1 `
  -BundlePath C:\Users\you\Downloads\old-to-new-20260521120000.tar.gz `
  -Sha256File C:\Users\you\Downloads\old-to-new-20260521120000.tar.gz.sha256
```

5. 把 `tar.gz` 上传到新系统服务器并执行新系统导入流程。

6. 导入后在新系统服务器执行迁移验证：

```bash
BUNDLE_PATH=/path/to/old-to-new-20260521120000.tar.gz \
DATABASE_URL=postgres://... \
UPLOADS_DIR=/srv/wailearning/uploads \
bash scripts/post_import_verify.sh
```

## 导出成功的最低标准

- Workbench 最后输出 `导出完成`
- 给出一个 `迁移包：/root/wailearning-migration/...tar.gz`
- `verify_export_bundle.sh` 通过
- Windows 下载后 `windows_verify_bundle.ps1` 通过

## 迁移验证的最低标准

- `post_import_verify.sh` 对 `users`、`students`、`classes`、`subjects`、
  `homeworks`、`homework_submissions`、`course_materials`、`notifications`
  的表计数校验通过
- 如果提供了 `UPLOADS_DIR`，旧包里的附件清单全部存在于新系统落盘目录

## 注意事项

- `old-env-file` 可能包含数据库密码、密钥和部署路径，不能随意外发。
- `attachment-references.tsv` 记录的是数据库里的附件 URL，不代表这些文件一定已成功落盘。
- `course_enrollments` 这类新系统可能补齐或重建的数据，验证脚本采用“不少于旧库”的标准，而不是完全相等。
