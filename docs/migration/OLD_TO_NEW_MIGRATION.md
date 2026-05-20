# 旧系统到新系统迁移说明

本仓库是旧系统发布副本。迁移目标仓库建议使用 `YinzhuCheng/wailearning-new-system`。

## 迁移前准备

- 在旧系统服务器停止写入类操作，避免迁移窗口内继续产生新数据。
- 备份 PostgreSQL 数据库、上传附件目录、Nginx 配置和 systemd 服务文件。
- 记录旧系统的公网访问地址、管理员账号、前端 API 地址和上传文件保存路径。
- 在新系统服务器完成基础部署，但不要开放给最终用户写入。

## 推荐迁移顺序

1. 旧系统执行数据库备份：`pg_dump -Fc "$DATABASE_URL" -f old-system.dump`。
2. 备份附件目录：`tar -czf old-uploads.tar.gz <OLD_UPLOAD_DIR>`。
3. 将备份文件复制到新系统服务器。
4. 按新系统仓库的 `docs/migration/OLD_TO_NEW_MIGRATION.md` 执行导入、字段核对和 smoke test。
5. 核对管理员、教师、学生、家长入口和附件下载。
6. 切换域名解析或 Nginx upstream 到新系统。

## 回滚策略

- 域名切换前保留旧系统服务器和数据库。
- 如果新系统 smoke test 失败，保持旧系统继续对外服务。
- 如果域名已切换，先把 DNS 或 Nginx upstream 切回旧系统，再排查新系统迁移问题。
