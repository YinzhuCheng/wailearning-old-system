# 旧系统到新系统迁移说明

本仓库是旧系统发布副本。迁移目标仓库建议使用 `YinzhuCheng/wailearning-new-system`。

## 推荐方式

优先使用短启动器导出迁移包，避免在 Workbench 里手写多行 `pg_dump`、`tar`、`scp` 命令时出现换行、缩进或参数截断问题。

1. 在旧系统服务器执行 `docs/migration/ALIYUN_WORKBENCH_EXPORT_MIGRATION_BUNDLE.txt`。
2. 得到 `/root/wailearning-migration/<label>.tar.gz`。
3. 将压缩包复制到新系统服务器，例如：`scp /root/wailearning-migration/<label>.tar.gz root@<NEW_ECS_IP>:/root/`。
4. 在新系统服务器执行新系统仓库的 `docs/migration/ALIYUN_WORKBENCH_IMPORT_MIGRATION_BUNDLE.txt`。

## 迁移前准备

- 在旧系统服务器停止写入类操作，避免迁移窗口内继续产生新数据。
- 确认旧系统后端服务健康：`curl -fsS http://127.0.0.1:8001/api/health`。
- 确认旧系统 `.env.production` 存在，默认路径是 `/opt/wailearning-old-system/current/.env.production`。
- 在新系统服务器完成基础部署，但不要开放给最终用户写入。

## 手动导出参考

如果不使用启动器，手动导出至少包含以下内容：

```bash
pg_dump -Fc "$DATABASE_URL" -f old-system.dump
tar -czf old-uploads.tar.gz <OLD_UPLOAD_DIR>
```

手动方式容易遗漏环境文件、服务配置和附件目录，生产迁移建议使用启动器导出完整 bundle。

## 回滚策略

- 域名切换前保留旧系统服务器和数据库。
- 如果新系统 smoke test 失败，保持旧系统继续对外服务。
- 如果域名已切换，先把 DNS 或 Nginx upstream 切回旧系统，再排查新系统迁移问题。
