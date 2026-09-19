# 安全基线

## 网络边界

- 公网入口只有 Nginx 80/443。
- New API、PostgreSQL 和 Redis 只在 Docker 网络内通信。
- CPA 8317 仅绑定宿主机 loopback，通过 SSH 隧道访问。
- Cloudflare 使用 Proxy、Full (strict) 和 AOP。
- SSH 只允许管理员 IP/VPN，并优先使用公钥登录。

AOP 已在 Nginx 中设为强制校验。启用前应先在 Cloudflare 打开对应功能，否则正常流量也会被拒绝。全局 AOP 只能证明请求来自 Cloudflare 网络；更严格的隔离应使用 zone/hostname 级自有 AOP 证书，或同时在云安全组/主机防火墙只允许 [Cloudflare IP ranges](https://www.cloudflare.com/ips/) 访问 443。

## 身份与权限

- Root、Admin 必须启用 2FA。
- Root 不用于日常操作。
- 禁止公开注册，成员由管理员创建。
- 一人一账号，一设备/用途可进一步拆分 Token。
- Token 设置额度、模型范围和过期时间。
- 离职时禁用账号并撤销会话，不轮换全团队 Token。

## 秘密

以下文件不得提交 Git：

- `.env`
- `cpa/config.yaml`
- `cpa/auths/*`
- `nginx/ssl/*`
- `backups/*`

提交前执行：

```bash
git status --short
git diff --cached
```

如果秘密曾经进入 Git 历史，仅删除文件不够；应先轮换密钥和 OAuth 凭据，再清理历史。

`.env` 仅支持脚本生成的十六进制/安全字符秘密。手工修改数据库或 Redis 密码时，不要使用换行、空格、`#`、URL 保留字符或 Shell 表达式；它们可能需要 URL 编码并会破坏 DSN。

## 备份安全

备份包含所有核心秘密和用户数据：

- 本机权限设为 `600`。
- 异地副本必须加密。
- 对象存储使用独立账号、最小写入权限和生命周期策略。
- 定期验证归档校验和与恢复流程。
- 按团队隐私要求设置 New API 日志保留时间。

## Cloudflare 与 API 行为

- 对整个 API 主机名设置 Bypass cache，避免授权响应或管理页面被缓存。
- 开启 WebSockets；Cloudflare 在所有计划支持代理 WebSocket，但网络发布时可能断开现有连接，客户端需要重连。参见 [Cloudflare WebSockets](https://developers.cloudflare.com/network/websockets/)。
- 不把 CPA 管理页代理到公网。
- WAF 和速率限制应从观察模式开始，避免阻断流式调用或 SDK 重试。

## 容器与版本

- 镜像使用明确版本标签，不使用 `latest`。
- 所有服务启用 `no-new-privileges`。
- 数据库不发布宿主机端口。
- 更新前查看 Release Notes 并备份。
- 定期更新宿主机内核、Docker 与安全补丁。

明确版本标签仍可能被上游重新推送。需要供应链级不可变部署时，应把镜像固定到多架构 manifest digest，并为 `amd64`/`arm64` 分别验证。
