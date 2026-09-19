# 故障排查

## 从这里开始

```bash
./scripts/doctor.sh
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=200
PUBLIC_CHECK=0 ./scripts/healthcheck.sh
```

## Cloudflare 525 / 526

检查：

- `origin.pem` 是否包含当前域名。
- `origin.key` 是否与证书配对。
- Cloudflare 是否设为 Full (strict)。
- 源站 443 是否能从 Cloudflare 网络访问。

可以在源站验证证书和私钥公钥摘要是否一致：

```bash
openssl x509 -in nginx/ssl/origin.pem -pubkey -noout | openssl sha256
openssl pkey -in nginx/ssl/origin.key -pubout | openssl sha256
```

## Nginx 返回 400，日志提示客户端证书问题

Nginx 已开启 `ssl_verify_client on`。确认 Cloudflare Dashboard 的 Authenticated Origin Pulls 已启用，并确认 `nginx/ssl/cloudflare-origin-pull-ca.pem` 存在。不要通过关闭 AOP 长期绕过问题。

## 直接访问源站 IP 失败

这是预期行为。Origin CA 不受普通浏览器信任，AOP 还要求 Cloudflare 客户端证书。应用应只通过配置的 Cloudflare 域名访问。

## 524 或长请求中断

Cloudflare 默认回源读取超时当前为 125 秒。优先：

1. 客户端开启流式响应。
2. 确认 Nginx 的 `proxy_buffering off` 没有被覆盖。
3. 确认 CPA `streaming.keepalive-seconds` 为 15。
4. 检查 Provider 是否在首个 token 前长时间无响应。

Nginx 的 600 秒 timeout 不能覆盖 Cloudflare 自身的限制。

## CPA 管理页打不开

在服务器检查：

```bash
docker compose --env-file .env ps cpa
ss -lnt | grep 8317
```

监听地址应为 `127.0.0.1:8317`。本地 SSH 命令应保持运行：

```bash
ssh -L 8317:127.0.0.1:8317 YOUR_SSH_USER@YOUR_VPS_IP
```

本地 8317 已占用时，可把左侧端口改为其他值，例如 `-L 18317:127.0.0.1:8317`，然后访问 `http://127.0.0.1:18317/management.html`。

## New API 渠道测试 401

检查渠道 API Key 是否等于 `.env` 的 `CPA_API_KEY`，Base URL 是否为 `http://cpa:8317`。成员 Token 与 CPA API Key 是两套不同凭据，不能混用。

如果在 CPA 管理页保存配置后出现问题，确认 `cpa/config.yaml` 中 `api-keys` 没有被掩码文本替换，并从最近备份恢复原值。

## PostgreSQL 不健康

```bash
docker compose --env-file .env logs --tail=200 postgres
docker compose --env-file .env exec postgres pg_isready -U newapi -d newapi
```

初始化后的 PostgreSQL 密码保存在数据库卷中。只改 `.env` 不会修改已有数据库用户密码；应在数据库中同步修改，或恢复原 `.env`。

## 脚本公网健康检查失败

先运行：

```bash
PUBLIC_CHECK=0 ./scripts/healthcheck.sh
```

如果本机检查通过，依次检查 DNS 代理状态、Full (strict)、AOP、云安全组和域名证书。DNS 还未传播时等待生效后重试。
