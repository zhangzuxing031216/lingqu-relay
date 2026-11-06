# 更新记录

## 2026-11-06 · 预览图

- 新增 `docs/images/admin-dashboard.svg`：后台运营概览示意。
- 新增 `docs/images/price-page.svg`：对外价格页示意。
- 新增 `docs/images/registration-captcha.svg`：注册验证码网关示意。
- 新增 `docs/images/newapi-setup.png`、`newapi-dashboard.png`：new-api v1.0.0-rc.48 真实截图。
- `README.md` 增加“效果预览”和首屏徽章/简介/新手 3 步。

## 2026-11-06 · v0.1

- 初版脱敏模板。
- 架构：Docker + new-api + Caddy + SQLite。
- 文档：
  - `README.md`：人看，十步部署。
  - `AI-DEPLOY.md`：AI 看，取证/分支/验收/故障树。
  - `docs/architecture.md`：组件、请求路径、故障域。
  - `docs/installation.md`：命令版安装。
  - `docs/operations.md`：日常/升级/恢复/事故。
  - `docs/troubleshooting.md`：502/证书/401/429/注册/支付。
  - `docs/security.md`：威胁模型与检查清单。
  - `docs/payment.md`：可选充值接入。
  - `docs/custom-frontend.md`：静态页与验证码接入。
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
- 图示：
  - `docs/images/architecture.svg`
  - `docs/images/deploy-flow.svg`

## 待办

- [ ] 补真实截图（后台、渠道、Caddy 证书、验证码）。
- [ ] 补 new-api 版本固定/digest 示例。
- [ ] 补 MySQL/多机方案。
- [ ] 补 Cloudflare/CDN 场景。
- [ ] 补完整定制前端模板（可选）。
- [ ] 定期检查 Caddy/new-api 配置字段是否随版本变化。