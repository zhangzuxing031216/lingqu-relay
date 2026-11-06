# 架构

## 1. 组件

| 组件 | 作用 | 监听 | 备注 |
|---|---|---|---|
| Caddy | TLS、反代、静态页、rewrite | `:80`, `:443` | 自动申请证书 |
| new-api | 用户/令牌/渠道/计费/API | `127.0.0.1:3000` | Docker |
| captcha-gate | 注册算术题校验 | `127.0.0.1:3100` | systemd + Python |
| SQLite | 用户、渠道、日志、配置 | 文件 | `/opt/new-api/data/one-api.db` |
| 静态前端 | 落地/价格/文档/钱包 | 文件 | Caddy 直读 `/opt/new-api/static` |
| 上游 | 真正提供模型 | 外网 | 1 个或多个 |

## 2. 请求路径

### 2.1 普通 API

```text
客户端
  → https://www.example.com/v1/chat/completions
  → Caddy (443)
  → 127.0.0.1:3000
  → new-api 选渠道
  → 上游 API
  → 原路返回（流式时 flush_interval -1）
```

### 2.2 漏写 `/v1`

```text
客户端 → https://www.example.com/chat/completions
Caddy handle /chat/completions:
  rewrite * /v1/chat/completions
  reverse_proxy 127.0.0.1:3000
```

`/responses`、`/messages` 同理。

### 2.3 注册

```text
浏览器 GET /lq/captcha
  → Caddy → 127.0.0.1:3100
  → 生成题目 + 签名 token

浏览器 POST /api/user/register
  → Caddy → 127.0.0.1:3100
  → 校验 token/答案/频率
  → 通过后转发 127.0.0.1:3000
```

登录**不经过**网关，避免登录也被验证码拖慢。

### 2.4 静态页

```text
浏览器 GET /price
  → Caddy handle /price
  → rewrite /price.html
  → root /opt/new-api/static
  → file_server
```

改 HTML 不需要重启 new-api。

## 3. 数据流

```text
users ──< tokens
  │
  └──< logs ──> channels ──> upstream
  │
  └──< topups（如果接支付）
```

关键表（以 new-api 实际结构为准）：

- `users`：账号、额度、分组
- `tokens`：API key、额度、过期
- `channels`：上游地址/key/模型
- `logs`：请求、消耗、错误
- `options`：站点配置
- `topups`：充值订单（如果启用）

> 不要手改数据库余额。用后台/兑换码/支付回调。

## 4. 故障域

| 故障 | 影响 | 恢复 |
|---|---|---|
| Caddy 挂 | 全站 502/无法访问 | `systemctl restart caddy` |
| new-api 挂 | API/后台不可用 | `docker compose up -d` |
| gate 挂 | 注册失败，登录/API 不受影响 | `systemctl restart turnstile-gate` |
| 上游挂 | 对应模型失败 | 多渠道/切渠道 |
| DB 损坏 | 全站数据风险 | 停容器 + 恢复备份 |
| 磁盘满 | 写入失败/容器崩 | 清日志/备份/镜像 |
| 证书过期 | HTTPS 失败 | 检查 80/443/DNS，reload Caddy |

## 5. 扩展

- **多机**：SQLite 不适合多写；要水平扩展需换 MySQL/PostgreSQL（new-api 支持时），并做共享存储。
- **多上游**：一个模型配多个渠道，设置优先级/权重。
- **对象存储**：静态页/备份放 R2/OSS/S3，减少服务器磁盘。
- **监控**：`health-check.sh` + 外部 uptime 监控；日志集中化可选 Loki。
- **CDN**：可前置 Cloudflare（注意真实 IP、限流、证书模式）。

## 6. 安全边界

```text
公网
  │ 只允许 22/80/443
  ▼
Caddy ── 127.0.0.1:3000 ── new-api
  │
  └──── 127.0.0.1:3100 ── gate

本机文件：
  /root/lq_captcha.secret     600
  /opt/new-api/data/*.db      仅 root/容器可读
  /root/backups/*             600
```

- new-api 和 gate 都不直接暴露公网。
- 支付密钥只放后台/环境变量，不进前端。
- 备份含用户数据，按敏感数据管理。

## 7. 设计取舍

| 选择 | 原因 | 代价 |
|---|---|---|
| SQLite | 单机简单、零运维 | 不适合高并发多写 |
| Caddy | 自动 HTTPS、配置短 | 插件生态不如 Nginx |
| 静态页直读 | 改页面不用重启 | 需要自己维护 HTML |
| 自建算术题 | 无第三方依赖 | 防不了高级真人打码 |
| Docker | 升级/回滚方便 | 占内存，需学一点 Docker |