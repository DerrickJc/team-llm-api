# 完整部署

## 1. 准备主机

推荐 Ubuntu 24.04 LTS、2 vCPU、2～4 GB 内存、20 GB 以上磁盘。按 [Docker Engine 官方文档](https://docs.docker.com/engine/install/) 安装 Docker Engine 和 Compose v2。不要使用发行版仓库中过旧的 `docker-compose` v1。

云安全组只需要：

- SSH 端口：仅允许管理员固定 IP 或 VPN 网段。
- TCP 80/443：用于 Cloudflare 回源。

不要开放 3000、5432、6379、8317。Compose 中的 CPA 8317 仅绑定 `127.0.0.1`，云安全组也无需配置。

## 2. 初始化仓库

```bash
git clone https://github.com/DerrickJc/team-llm-api.git
cd team-llm-api
./scripts/setup.sh api.example.com
```

如果脚本中途失败，它不会覆盖已生成的秘密。检查失败原因后，确认 `.env` 和 `cpa/config.yaml` 是否需要保留；需要重新生成时先手动移走这两个文件。

## 3. 安装 Cloudflare Origin 证书

在 Cloudflare 控制台进入 **SSL/TLS → Origin Server → Create Certificate**：

- Hostname 包含实际 API 域名。
- 私钥类型可选择 ECC。
- 证书有效期根据团队的轮换制度选择。

复制到服务器：

```text
nginx/ssl/origin.pem
nginx/ssl/origin.key
```

然后设置权限：

```bash
chmod 600 nginx/ssl/origin.key
```

Origin CA 证书只能用于 Cloudflare 到源站，浏览器直接访问源站 IP 时不会信任它，这是预期行为。

## 4. 配置 Cloudflare

按顺序完成：

1. DNS 记录开启 Proxy。
2. SSL/TLS 模式设置为 **Full (strict)**。
3. 开启 Global Authenticated Origin Pulls。
4. Cache Rule：Hostname 等于 API 域名，Cache eligibility 设为 **Bypass cache**。
5. Network → WebSockets 设为 On。

Nginx 默认强制校验 AOP 客户端证书。如果 Cloudflare 没有开启 AOP，访问会得到 400/525 类错误。

安全组只允许 Cloudflare IP 回源可以作为第二道防线。Cloudflare 会维护其网络列表；硬编码规则必须同步更新，否则可能中断服务。官方当前 IP 列表和 API 见 [Cloudflare IP addresses](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/)。

## 5. 启动与初始化

```bash
./scripts/doctor.sh
./scripts/start.sh
```

`start.sh` 默认从公网域名执行最终健康检查。DNS 尚未生效时可先启动并只检查容器：

```bash
PUBLIC_CHECK=0 ./scripts/start.sh
```

公网生效后再次运行普通健康检查。

首次访问域名会进入 New API 初始化页。创建 Root 后，按照 [团队管理](team-management.md) 完成安全基线和成员配置。

## 6. 接入 CPA

在管理员电脑执行：

```bash
ssh -L 8317:127.0.0.1:8317 YOUR_SSH_USER@YOUR_VPS_IP
```

保持 SSH 会话，浏览器打开：

```text
http://127.0.0.1:8317/management.html
```

从服务器 `.env` 获取 `CPA_MANAGEMENT_KEY`。完成 OAuth 或 Provider 配置后，New API 的渠道地址使用 `http://cpa:8317`，渠道密钥使用 `CPA_API_KEY`。

## 7. 部署验收

```bash
./scripts/healthcheck.sh
docker compose --env-file .env ps
ss -lnt
```

验收要求：

- 公网可见 80/443，8317 只显示 `127.0.0.1:8317`。
- 3000、5432、6379 不在宿主机监听。
- 直接访问源站 IP 的 TLS 握手失败或被拒绝。
- 每位成员能用自己的 Token 调用允许的模型并查看自己的使用日志。
- `./scripts/backup.sh` 成功，并在测试环境验证恢复流程。
