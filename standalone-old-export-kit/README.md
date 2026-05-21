# standalone-old-export-kit

主入口：

- `index.html`
- `exporter-pack/00_START_HERE_EXPORTER.html`

这是旧系统独立导出工具包。它的目标很简单：让旧系统维护者在 Workbench 里完成导出，把包下载到 Windows，再把包交给新系统导入和验证。

## 你先看什么

- 导出执行者先看 `exporter-pack/00_START_HERE_EXPORTER.html`
- 需要让编码Agents协助调试导出过程时，先看 `exporter-pack/10_COORDINATOR_NOTES.html`
- 出错时先看 `exporter-pack/90_DEEP_TROUBLESHOOTING_FOR_LLM.html`

## 这个包里有什么

- `01_WORKBENCH_DIRECT_PASTE.txt`：首选执行版，整段粘贴到 Workbench。
- `02_WORKBENCH_DOWNLOAD_SCRIPT.txt`：脚本下载版，适合后续复用最新版脚本。
- `03_standalone_old_export.sh`：真正导出旧系统的脚本。
- `04_verify_export_bundle.sh`：旧服务器导出后校验包完整性。
- `05_windows_verify_bundle.ps1`：Windows 本地校验下载包。
- `06_post_import_verify.sh`：新系统导入后的数据与附件对账。
- `10_COORDINATOR_NOTES.html`：如何向编码Agents发指令调试导出过程的问题。
- `20_WORKBENCH_DOWNLOAD_TO_WINDOWS_VISUAL_GUIDE.html`：只讲下载到 Windows。
- `90_DEEP_TROUBLESHOOTING_FOR_LLM.html`：给 LLM 的复杂排障说明。

## 主流程

1. 在旧服务器用 Workbench 执行 `01_WORKBENCH_DIRECT_PASTE.txt` 或 `02_WORKBENCH_DOWNLOAD_SCRIPT.txt`。
2. 旧服务器先跑 `04_verify_export_bundle.sh`。
3. 把 `.tar.gz` 和同名 `.sha256` 下载到 Windows。
4. 在 Windows 上跑 `05_windows_verify_bundle.ps1`。
5. 再把包交给新系统导入流程。
6. 导入后跑 `06_post_import_verify.sh`。

## 最低标准

- 旧服务器导出后能生成包和校验文件。
- Windows 本地校验通过。
- 新系统导入后，核心表计数和附件落盘检查通过。

## 注意

- `old-env-file` 可能包含密码、密钥和部署路径，不要外发。
- `attachment-references.tsv` 记录的是数据库里的 URL，不代表文件已经落盘。
- `course_enrollments` 这类派生数据，验证标准是“不少于旧库”，不是严格相等。
