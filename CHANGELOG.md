# 更新记录 / Changelog

版本号遵循 SemVer；当前版本见 `VERSION`，发布和对比流程见 `VERSIONING.md`。

## v0.1.0 · 2026-11-06 · 首次发布

### 新增

- 脱敏的 OpenAI 兼容中转站模板：Docker + new-api + Caddy + SQLite。
- 中英双语人看文档：`README.md` / `README.en.md`，顶部可切换。
- 中英双语 AI 协议：`AI-DEPLOY.md` / `AI-DEPLOY.en.md`。
- 部署文件：
  - `deploy/docker-compose.yml`
  - `deploy/Caddyfile.example`
  - `deploy/turnstile_gate.py`
  - `deploy/turnstile-gate.service`
  - `deploy/crontab.example`
- 脚本：
  - `scripts/bootstrap-ubuntu.sh`
  - `scripts/backup.sh`
  - `scripts/health-check.sh`
  - `scripts/probe-models.py`
- 文档：
  - `docs/architecture.md`
  - `docs/installation.md`
  - `docs/operations.md`
  - `docs/troubleshooting.md`
  - `docs/security.md`
  - `docs/payment.md`
  - `docs/custom-frontend.md`
- 图片：架构图、部署流程图、后台/价格页/验证码 mockup。
- 真实截图：`docs/images/newapi-setup.png`、`docs/images/newapi-dashboard.png`（new-api `v1.0.0-rc.48`）。

### 说明

- 这是第一个公开版本，作为后续版本对比的基线。
- 与下一版本比较：`git diff v0.1.0..v0.2.0`。
- 所有域名、邮箱、密钥、支付账号均为占位符；真实值不得写入 Git。
- 合规、上游条款、支付和退款责任由部署者承担。

## 未发布 / Unreleased

- [ ] 补 new-api 版本固定 / digest 示例。
- [ ] 补 MySQL / 多机方案。
- [ ] 补 Cloudflare / CDN 场景。
- [ ] 补完整定制前端模板（可选）。
- [ ] 定期检查 Caddy / new-api 配置字段是否随版本变化。