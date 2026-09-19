# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；正式 release 使用语义化版本。

## [Unreleased]

### Added

- 固定版本的 New API、CLIProxyAPI、PostgreSQL、Redis 与 Nginx Compose 架构。
- Cloudflare Origin CA、Full (strict) 和强制 AOP 的 Nginx 配置。
- 初始化、诊断、健康检查、备份、恢复、升级和 Cloudflare IP 同步脚本。
- 团队账号、安全、部署、运维和故障排查文档。
- PR 静态校验工作流。
- 从原博客迁移的完整 README 图文部署教程和 43 张本地截图。

### Security

- New API、PostgreSQL 与 Redis 不发布宿主机端口。
- CPA 管理端口仅绑定宿主机 loopback。
- 所有本地秘密、OAuth 凭据、私钥和备份默认不进入 Git。
