# Contributing

## 分支与 PR

- 一个 PR 只处理一个明确主题。
- 不提交 `.env`、OAuth 凭据、TLS 私钥、日志、数据库或备份。
- 配置行为变化必须同步更新 README 或 `docs/`。
- 镜像版本变化必须更新 `.env.example` 和 `CHANGELOG.md`。

## 提交前检查

```bash
make validate
git status --short
git diff --check
git diff --cached
```

涉及备份、恢复或升级脚本时，还应在隔离环境完成以下人工验收：

1. 从空卷启动。
2. 创建测试用户、Token 和 CPA 测试凭据。
3. 生成备份。
4. 修改测试数据。
5. 从备份恢复并验证数据和调用。
6. 执行一次升级失败回退演练。

## 版本策略

仓库 release 表示一组已一起验证的组件版本。不要在 release 分支使用 `latest` 或只更新一个运行组件而不记录兼容性。
