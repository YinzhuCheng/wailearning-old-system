# wailearning migration kit

旧系统独立导出工具包。

这个工具包不要求旧系统仓库更新。旧系统维护者只要能在阿里云 Workbench
用 root 登录旧服务器，就可以导出数据库、上传附件和部署配置快照。

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

- `docs/old_export_guide.html`
  - 导出说明文档。
  - 如果导出失败，可以把该 HTML、操作流 txt 和终端报错交给 LLM 排错。

## 推荐执行方式

优先使用 `01_WORKBENCH_COPY_PASTE_EXPORT.txt`。
它把脚本完整内嵌在操作流里，不要求旧系统服务器能访问本仓库。

如果后续要用脚本版，再使用 `02_WORKBENCH_DOWNLOAD_SCRIPT_EXPORT.txt`。
该方式只是从公开 GitHub 下载独立脚本，不要求旧系统服务器更新本地仓库。

## 默认输出

脚本默认把迁移包输出到旧服务器：

```text
/root/wailearning-migration/old-to-new-YYYYMMDDHHMMSS.tar.gz
```

把这个 tar.gz 复制到新系统服务器后，再执行新系统导入流程。
