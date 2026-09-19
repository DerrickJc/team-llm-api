# 运维手册

## 状态与日志

```bash
make status
make health
docker compose --env-file .env logs --tail=200 new-api
docker compose --env-file .env logs --tail=200 cpa
docker compose --env-file .env logs --tail=200 nginx
```

健康检查验证容器状态、New API 自身健康、New API 到 CPA 的内部认证，以及公网域名。只检查本机容器时：

```bash
PUBLIC_CHECK=0 ./scripts/healthcheck.sh
```

## 备份

```bash
./scripts/backup.sh
```

备份包含：

- PostgreSQL 自定义格式 dump：用户、Token、渠道、配额、系统配置和日志。
- CPA `config.yaml` 与 `auths/`：内部密钥和 OAuth 凭据。
- New API `/data`：可能存在的本地资源和运行数据。
- `.env`：数据库、Redis、New API 和 CPA 秘密。
- Nginx SSL 目录：Origin CA 私钥、证书和 AOP CA。
- 当前镜像版本清单。

归档和校验文件权限为 `600`。它们包含可直接接管系统的秘密，离机保存前应使用 `age`、GPG 或对象存储服务端加密。

每天 03:00 备份的 cron 示例：

```cron
0 3 * * * cd /opt/team-llm-gateway && ./scripts/backup.sh >> /var/log/team-llm-gateway-backup.log 2>&1
```

默认保留 7 天，可在 `.env` 修改 `BACKUP_RETENTION_DAYS`。这只清理 `BACKUP_DIR` 顶层、符合项目命名规则的归档和校验文件。

## 恢复到当前主机

```bash
./scripts/restore.sh backups/team-llm-gateway-20260919T030000Z.tar.gz --confirm
```

脚本会：

1. 校验同目录 `.sha256`（如果存在）。
2. 在覆盖前创建一份当前状态备份。
3. 停止 Nginx、New API 和 CPA。
4. 保留带时间戳的 CPA/TLS 原目录。
5. 恢复 OAuth、配置、证书和 PostgreSQL。
6. 重新启动并执行健康检查。

恢复会从备份合并 `SESSION_SECRET`、`CRYPTO_SECRET`、`CPA_API_KEY` 和 `CPA_MANAGEMENT_KEY`，因为它们与数据库及 CPA 配置耦合。当前主机的域名、数据库密码和 Redis 密码保持不变，避免已经初始化的 PostgreSQL 卷失去访问能力。

## 新主机灾难恢复

1. 克隆与备份版本相同的仓库 release/tag。
2. 检查归档的 SHA-256。
3. 手动解压归档，把 `payload/.env` 复制到仓库根目录。
4. 将 `payload/cpa/config.yaml`、`payload/cpa/auths/` 和 `payload/nginx/ssl/` 放回对应目录。
5. 执行 `docker compose --env-file .env up -d postgres redis`，等待 PostgreSQL 健康。
6. 运行 `./scripts/restore.sh <归档> --confirm`。
7. 更新 DNS 到新主机并验证公网健康检查。

恢复演练应在隔离主机进行。不要等故障发生后第一次验证备份。

## 升级

先阅读两个上游项目的 Release Notes：

- [New API releases](https://github.com/QuantumNous/new-api/releases)
- [CLIProxyAPI releases](https://github.com/router-for-me/CLIProxyAPI/releases)

然后执行：

```bash
./scripts/update.sh --new-api v1.0.0-rc.39 --cpa v7.3.8
```

脚本会备份、修改 `.env` 固定版本、拉取镜像、重建服务和检查健康。失败时恢复旧版本标签并重建。New API 启动时可能执行数据库迁移，所以镜像回退不能保证数据库兼容；出现旧版无法启动时，使用升级前生成的归档恢复数据库。

PostgreSQL 大版本升级不在该脚本范围内。应按 PostgreSQL 官方流程使用 `pg_upgrade` 或逻辑 dump/restore，并单独安排维护窗口。

## Cloudflare 网络列表

Nginx 只信任 Cloudflare 官方网络提供的 `CF-Connecting-IP`。刷新列表：

```bash
./scripts/sync-cloudflare-ips.sh
```

脚本从 Cloudflare 官方 `ips-v4`/`ips-v6` 地址获取列表，至少验证条目数量，Nginx 运行时会先执行 `nginx -t` 再 reload。建议每月运行或在 Cloudflare 公告网络变更后运行。

## 版本发布建议

每次仓库 release 应记录：

- New API 与 CPA 固定版本。
- PostgreSQL、Redis、Nginx 固定版本。
- 数据库迁移或兼容性提示。
- 备份恢复演练结果。
- 从上一 release 升级和回退的方法。
