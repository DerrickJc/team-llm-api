# 原教程与扩展方案审查

## 结论

原教程已经打通了 CPA → New API → Nginx → Cloudflare 的主链路，适合个人学习和短期自用。面向 3～10 人、持续运行、公开仓库复用时，核心系统无需重写，但必须补齐安全默认值、数据恢复、版本管理和团队账号流程。

完成本仓库的工程化后，可以称为“小团队自托管网关”，不能称为企业级或生产级高可用平台。主要原因是单机架构和 New API 当前仍处于 release candidate 阶段。

## 已确认正确的判断

| 项目 | 审查结论 |
| --- | --- |
| `ports: - "3000"` | 会发布随机宿主机端口，且未指定 Host IP 时绑定所有接口。正式配置应删除；同一 Compose 网络内无需 `ports` 或 `expose` 也能互通。 |
| CentOS 7 | 已 EOL，不应作为新项目默认系统。 |
| 团队共用 Token | 不合适。应使用一人一账号、一人一 Token。 |
| 公开注册 | 小团队默认关闭，由管理员创建成员。 |
| Root 安全 | Root 启用 2FA，另建 Admin 做日常管理。 |
| 明文秘密入库 | `.env`、CPA 配置、OAuth 文件和 TLS 私钥必须忽略。 |
| `latest` | 不适合可重复部署，应使用明确版本。 |
| 备份恢复 | 是长期运行的必要条件，且恢复演练与备份同样重要。 |
| Cloudflare 源站保护 | 只开橙色云朵不足，应使用 AOP 或源站防火墙限制。 |

Docker Compose 对 `ports` 和 `expose` 的定义可查阅 [Docker Compose services](https://docs.docker.com/reference/compose-file/services/)。Cloudflare 也明确说明，攻击者知道源站 IP 后可以绕过普通代理，因此建议阻断非 Cloudflare 流量或启用 AOP，参见 [Cloudflare IP addresses](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/) 与 [AOP 原理](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/explanation/)。

## 需要修正或补充的部分

### 1. `expose` 可以省略

把 `ports: - "3000"` 改成 `expose: - "3000"` 是安全的，但不是必需。容器加入同一 Compose 网络后，可以直接通过服务名和容器端口通信。本仓库直接省略 New API 和数据库的 `ports/expose`。

### 2. CPA 需要一个受控管理入口

完全不发布 CPA 端口会让 Web 管理面和 OAuth 操作变得困难。本仓库将 `8317` 只绑定到宿主机 `127.0.0.1`，管理员通过 SSH 隧道访问。它不会从公网网卡监听，也不经 New API 透传管理接口。

### 3. 不应承诺“升级失败自动完整回滚”

镜像标签可以自动退回，数据库迁移未必可逆。`update.sh` 会先备份、失败后恢复旧标签；如果新版修改了数据库结构且旧版不能读取，必须恢复升级前数据库。任何自动更新方案都应保留这个边界。

### 4. 固定版本仍需要主动升级

版本固定保证可复现，不代表版本永远安全。维护者应定期阅读 New API、CPA、PostgreSQL、Redis 和 Nginx 的发布说明，在测试环境验证后更新固定标签。PostgreSQL 跨大版本升级不应交给通用更新脚本处理。

### 5. 本地保留 7 天不是完整灾备

本机磁盘损坏会同时丢失服务和本机备份。正式使用至少应把加密后的备份同步到另一台主机或对象存储，制定 RPO/RTO，并定期在空环境执行恢复演练。本仓库只负责生成权限为 `600` 的完整本地归档。

### 6. Cloudflare 对 LLM 长请求有行为限制

应关闭 API 缓存、开启 WebSocket、优先使用流式响应。Cloudflare 当前默认 Proxy Read Timeout 为 125 秒；非流式模型响应长时间不返回数据时可能出现 524。CPA 的流式 keepalive 和 Nginx 的 `proxy_buffering off` 可减少此类问题，但不能改变 Cloudflare 平台限制。

### 7. Token IP 白名单不应作为统一强制项

固定办公出口适合使用 IP 白名单；远程成员、移动网络和动态住宅 IP 会频繁变化。默认做法应是独立 Token、额度、模型范围和过期时间，IP 白名单按成员网络条件启用。

### 8. 管理员不应依赖查看成员 Token 明文

安全的离职流程是禁用用户或撤销其 Token，而不是读取和复用成员 Token。管理功能在不同 New API 版本中仍有变化，教程不应承诺 Admin 能查看所有 Token 密钥。

### 9. OAuth 凭据有上游条款风险

CPA 能把不同 Provider 的 OAuth 凭据转换为 API，但技术可用不等于上游允许共享、转售或自动化访问。公开教程应明确要求使用者自行确认账号、地区、组织和 Provider 服务条款。本项目的默认定位是内部自用，不包含公开售卖、支付或开放注册。

## 本仓库采用的明确假设

- 3～10 名已知成员，单一团队，单一 VPS。
- 允许维护窗口和分钟级停机，不要求高可用。
- Cloudflare 是必选入口，AOP 默认启用。
- 公开注册、充值、支付、签到默认不使用。
- 每位成员有独立 User 和 API Token。
- 每日备份、保留 7 天只是默认起点；生产数据另做异地加密副本。
- 一个 Root 只做系统配置，一个或多个 Admin 做日常管理。

如果未来需要公开注册、商业售卖、多个组织租户、审计合规、零停机或跨区域灾备，应另立需求并重新设计，不能继续在当前单机方案上无边界叠加功能。
