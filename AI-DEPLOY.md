# AI-DEPLOY.md · 灵渠 AI 中转站部署指令（给 AI 读）

> **Language / 语言**: 中文 | [English](AI-DEPLOY.en.md)

> 目标机器：Ubuntu 22.04 / 24.04，root 或 sudo。
> 目标结果：`https://www.<域名>` 能打开，`/api/status` 返回 200，new-api 后台能登录，注册验证码网关工作，备份能跑。
> 模板版本：2026-11
>
> 本文是**脱敏模板**。所有 `YOUR_DOMAIN` / `YOUR_EMAIL` / `YOUR_KEY` 都必须替换成真实值，且真实值**不得写入 Git**。

---

## 0. 你的角色

你是部署执行者。按以下协议工作：

1. **先取证再动手**：系统版本、内存、磁盘、端口、DNS、是否已装过。
2. **一次一步**：执行 → 贴原始输出 → 判定 → 下一步。
3. **不编造**：没跑的命令不说完成；没看到的输出不说正常。
4. **不覆盖**：已有 `/opt/new-api`、`/etc/caddy/Caddyfile`、crontab，先备份再改。
5. **不碰密钥**：不把 key、密码、支付密钥写进仓库、日志、聊天记录。
6. **失败降级**：按本文备用路径走，不卡在一个源。
7. **验收有证据**：命令原文 + 输出 + HTTP 状态码。

---

## 1. 开工前必须问清的 6 件事

如果系统里能查到，就不要问。

1. 域名是什么？`A` 记录是否已指向这台机器？
2. 服务器 IP、系统版本、内存、磁盘？
3. 是否有上游 API 的 `base_url` / `key` / 模型列表？
4. 是否接支付？如果接，`pid` / `key` / 回调地址是否齐全？
5. 这台机器是否已经跑着 new-api / Caddy / 其他 80/443 服务？
6. 是否允许我修改 `/etc/caddy/Caddyfile`、crontab、systemd？

> 信息不全时，先做“不依赖上游/支付”的部分：DNS、Docker、new-api、Caddy、后台。上游和支付可以后补。

---

## 2. 硬约束

- 只支持 Ubuntu 22.04/24.04 x86_64。
- 必须能改 DNS；不能改就不要继续。
- 80/443 必须对公网可达；否则证书失败。
- new-api 只监听 `127.0.0.1:3000`，禁止 `0.0.0.0:3000`。
- 网关只监听 `127.0.0.1:3100`。
- 不把 `/root/lq_captcha.secret`、`.env`、数据库、支付密钥提交到 Git。
- 不在公开聊天里贴完整 key；必要时只显示后 4 位。
- 不关闭防火墙来“排错”。
- 不在生产机上直接跑 `latest` 升级；先备份。

---

## 3. 阶段 0 · 环境取证

```bash
# 3.1 系统
cat /etc/os-release
uname -m
free -h
df -h /

# 3.2 端口占用
ss -lntp | grep -E ':(80|443|3000|3100)\b' || true

# 3.3 已装服务
systemctl is-active docker caddy 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || true

# 3.4 DNS
dig +short YOUR_DOMAIN
dig +short www.YOUR_DOMAIN

# 3.5 公网 IP
curl -s https://api.ipify.org; echo
```

### 判定表

| 结果 | 分支 |
|---|---|
| 内存 < 1.5GB | 警告：可能 OOM；建议加 swap 或换机器 |
| 磁盘 < 15GB | 停止，先扩盘 |
| 80/443 被占用 | 先查清是什么服务；不要直接杀 |
| `/opt/new-api` 已存在 | 先备份，不要覆盖 |
| DNS 不指向本机 | 停止，等 DNS 生效 |
| `docker` 未装 | 阶段 1 安装 |
| 已装 new-api 且能跑 | 跳过阶段 2，直接验收/改造 |

**证据格式**：

```text
[阶段 0]
命令：free -h
输出：Mem: 1.9Gi ...
判定：2GB，可继续
```

---

## 4. 阶段 1 · 安装依赖

### 4.1 首选：bootstrap 脚本

```bash
sudo bash scripts/bootstrap-ubuntu.sh \
  --domain example.com \
  --email admin@example.com
```

脚本会：

1. 检查 root / Ubuntu / 内存 / 磁盘。
2. `apt update` + 安装 docker、compose、caddy、sqlite3、python3、curl、rsync。
3. 创建 `/opt/new-api/{data,static}`。
4. 备份已有 Caddyfile，写入模板并替换域名/邮箱。
5. 安装验证码网关和 systemd 单元。
6. 启动 docker / caddy / turnstile-gate。
7. 打印验收命令。

> 如果脚本失败，按 4.2 手动执行，不要反复重跑覆盖。

### 4.2 手动安装

```bash
apt update
apt install -y docker.io docker-compose-v2 caddy sqlite3 python3 curl rsync
systemctl enable --now docker
```

如果 `docker-compose-v2` 不存在：

```bash
apt install -y docker-compose-plugin || apt install -y docker-compose
```

验证：

```bash
docker --version
docker compose version || docker-compose --version
caddy version
sqlite3 --version
```

---

## 5. 阶段 2 · new-api

### 5.1 准备目录

```bash
mkdir -p /opt/new-api/data /opt/new-api/static
cd /opt/new-api
```

### 5.2 写 compose

复制仓库模板：

```bash
cp /root/lingqu-relay/deploy/docker-compose.yml /opt/new-api/docker-compose.yml
```

> 如果仓库不在 `/root/lingqu-relay`，换成实际路径。

### 5.3 启动

```bash
cd /opt/new-api
docker compose up -d
docker ps --filter name=new-api
```

### 5.4 验证

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status
```

期望 `200`。

### 5.5 失败处理

| 现象 | 处理 |
|---|---|
| `port is already allocated` | 3000 被占；查 `ss -lntp`，停旧容器 |
| 容器起来又退出 | `docker logs new-api` |
| 拉镜像失败 | 配 Docker 镜像加速；或换网络 |
| 内存不足 | 加 swap：`fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile` |
| `/api/status` 502 | 容器没起；看日志 |

---

## 6. 阶段 3 · Caddy + HTTPS

### 6.1 写 Caddyfile

```bash
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%F-%H%M) 2>/dev/null || true
cp /root/lingqu-relay/deploy/Caddyfile.example /etc/caddy/Caddyfile
```

编辑 `/etc/caddy/Caddyfile`，把：

- `YOUR_DOMAIN` → 你的域名（不带 `www`）
- `YOUR_EMAIL` → 你的邮箱

### 6.2 校验

```bash
caddy validate --config /etc/caddy/Caddyfile
```

必须 `Valid configuration`。

### 6.3 重载

```bash
systemctl reload caddy
systemctl status caddy --no-pager
```

### 6.4 验证

```bash
curl -sI https://www.YOUR_DOMAIN | head -5
curl -s https://www.YOUR_DOMAIN/api/status | head -c 300; echo
```

期望：

- `HTTP/2 200` 或 301/302
- `/api/status` 返回 JSON

### 6.5 证书失败排查

```text
证书失败
├─ DNS 没生效 → dig +short
├─ 80 不通 → 安全组/防火墙放行
├─ 443 被占 → ss -lntp
├─ Caddy 日志 → journalctl -u caddy -n 100
└─ 域名拼错 → 检查 Caddyfile
```

> 不要让用户“关掉 HTTPS”。证书是必须的。

---

## 7. 阶段 4 · 初始化后台

1. 打开 `https://www.YOUR_DOMAIN`。
2. 按提示创建管理员。
3. 立即改强密码。
4. 先关闭公开注册。
5. 记录管理员用户名（不要记录密码到仓库）。

验证：

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://www.YOUR_DOMAIN/
```

---

## 8. 阶段 5 · 渠道与模型

### 8.1 后台配置

渠道 → 新建：

- 类型：与上游匹配
- Base URL：上游地址
- Key：上游 key
- 模型：只填真实存在的
- 分组：默认

### 8.2 命令行探测

```bash
NEWAPI_BASE=http://127.0.0.1:3000 \
NEWAPI_KEY=你的令牌 \
python3 scripts/probe-models.py
```

期望：

- `GET /v1/models` 200
- 列出模型
- 可选 `--chat <model>` 返回 200

### 8.3 常见失败

| 现象 | 原因 |
|---|---|
| 401 | key 错 / 没带 Bearer |
| 403 | 分组/模型权限 |
| 404 | base_url 少了 `/v1` |
| 429 | 上游限流/额度 |
| 502 | 上游不可达 |

> 不要把上游 key 打到终端历史里。用环境变量或交互输入。

---

## 9. 阶段 6 · 注册验证码网关

### 9.1 安装

```bash
cp /root/lingqu-relay/deploy/turnstile_gate.py /root/turnstile_gate.py
cp /root/lingqu-relay/deploy/turnstile-gate.service /etc/systemd/system/turnstile-gate.service
systemctl daemon-reload
systemctl enable --now turnstile-gate
```

### 9.2 验证

```bash
systemctl status turnstile-gate --no-pager
curl -s http://127.0.0.1:3100/lq/captcha
```

期望 JSON：`{"success":true,"data":{"token":"...","q":"3 + 4"}}`

### 9.3 Caddy 路由

确认 Caddyfile 有：

```text
handle /lq/captcha* {
    reverse_proxy 127.0.0.1:3100
}
handle /api/user/register {
    reverse_proxy 127.0.0.1:3100
}
```

重载：

```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

### 9.4 注意

- 密钥文件 `/root/lq_captcha.secret` 自动生成。
- 不要把它复制进仓库。
- 网关只保护注册，登录不走。
- 同 IP 有频率限制，测试时别狂点。

---

## 10. 阶段 7 · 计费与支付（可选）

### 10.1 先不接支付

- 后台手动加额度 / 兑换码。
- 验证用户、令牌、扣费正常。
- 再接支付。

### 10.2 接支付

1. 在支付商后台拿 `pid` / `key`。
2. 在 new-api 后台填支付配置。
3. 回调地址以 new-api 后台显示的 `notify_url` 为准。
4. 小额充值 1 元测试。
5. 检查：到账、扣费、退款、回调重试。

### 10.3 禁止

- 不要把支付密钥写进 Caddyfile / 前端 JS。
- 不要用“测试模式”直接对公网开放。
- 不要在没有退款规则时收大额。

---

## 11. 阶段 8 · 定时任务与备份

### 11.1 安装 cron

```bash
crontab -l > /tmp/crontab.bak 2>/dev/null || true
crontab /root/lingqu-relay/deploy/crontab.example
crontab -l
```

### 11.2 手动跑一次备份

```bash
bash /root/lingqu-relay/scripts/backup.sh
ls -lh /root/backups
```

期望：

- `one-api-YYYY-MM-DD_HHMM.db`
- `ops-YYYY-MM-DD_HHMM.tar.gz`

### 11.3 验证 DB 可读

```bash
sqlite3 /root/backups/one-api-*.db 'select count(*) from users;'
```

### 11.4 异地备份

```bash
BACKUP_REMOTE=user@host:/backups/ bash /root/lingqu-relay/scripts/backup.sh
```

> 没有异地备份 = 没有备份。

---

## 12. 阶段 9 · 验收

### 12.1 自动

```bash
bash /root/lingqu-relay/scripts/health-check.sh
```

期望退出码 0。

### 12.2 手动

| 项 | 命令 | 通过标准 |
|---|---|---|
| 首页 | `curl -sI https://www.YOUR_DOMAIN` | 200/301/302 |
| 状态 | `curl -s https://www.YOUR_DOMAIN/api/status` | JSON |
| 模型 | `curl -s -H "Authorization: Bearer $KEY" https://www.YOUR_DOMAIN/v1/models` | 有 data |
| 验证码 | `curl -s https://www.YOUR_DOMAIN/lq/captcha` | token/q |
| 登录 | 浏览器 | 能进后台 |
| 渠道 | 后台测试 | 通过 |
| 备份 | `ls /root/backups` | 当天文件 |
| cron | `crontab -l` | 有任务 |

### 12.3 交付报告

```text
【结论】成功 / 部分成功 / 失败

【环境】
- 系统：
- 内存/磁盘：
- 域名：
- new-api 镜像：
- Caddy 版本：

【执行】
1. 依赖：
2. compose：
3. Caddy：
4. 网关：
5. cron/备份：

【验收】
- /api/status：
- /v1/models：
- 注册验证码：
- 备份文件：
- health-check：

【未解决/风险】
- ...

【下一步】
- ...
```

---

## 13. 故障树

### 13.1 502

```text
502
├─ docker ps 没有 new-api → docker compose up -d
├─ 容器重启 → docker logs new-api
├─ 内存不足 → free -h / 加 swap
└─ 端口不对 → 确认 127.0.0.1:3000
```

### 13.2 证书

```text
证书失败
├─ DNS → dig
├─ 80 → 安全组/ufw
├─ 443 → ss -lntp
├─ Caddy 日志 → journalctl -u caddy
└─ 限流 → 等 Let's Encrypt 重试
```

### 13.3 注册失败

```text
注册 400
├─ 验证码过期 → 刷新
├─ 答案错 → 重填
├─ 签名错 → 检查 secret 是否被换
└─ 上游返回英文 → 看网关日志

注册 429
├─ 同 IP 频率 → 等
└─ 调 RATE_MAX
```

### 13.4 充值不到账

```text
不到账
├─ 回调地址不对 → 对后台 notify_url
├─ 密钥不对 → 重填
├─ 支付商没回调 → 看支付商日志
├─ 订单号重复 → 查 DB
└─ 先用小额测试
```

---

## 14. 回滚

### 14.1 回滚 Caddy

```bash
cp /etc/caddy/Caddyfile.bak.YYYY-MM-DD-HHMM /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

### 14.2 回滚 new-api 镜像

```bash
cd /opt/new-api
docker compose down
# 修改 docker-compose.yml 的 image 为旧 tag
docker compose up -d
```

### 14.3 回滚数据库

```bash
docker compose stop new-api
cp /root/backups/one-api-YYYY-MM-DD.db /opt/new-api/data/one-api.db
rm -f /opt/new-api/data/one-api.db-wal /opt/new-api/data/one-api.db-shm
docker compose start new-api
```

> 回滚 DB 会丢备份之后的用户/订单数据。先确认。

---

## 15. 禁止事项

1. 不要把 3000/3100 开到公网。
2. 不要把 key/密码写进 Git、前端、Caddyfile。
3. 不要在没备份时升级/改库。
4. 不要用 `latest` 直接生产升级。
5. 不要关闭 HTTPS / 证书校验。
6. 不要伪造验收输出。
7. 不要在 1.5GB 机器上同时跑构建 + 备份 + 大流量。
8. 不要帮用户做违反上游条款的转卖。

---

## 16. 快速命令卡

```bash
# 状态
docker ps
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status
curl -sI https://www.YOUR_DOMAIN | head -3

# 日志
docker logs --tail 100 new-api
journalctl -u caddy -n 50 --no-pager
journalctl -u turnstile-gate -n 50 --no-pager

# 重启
cd /opt/new-api && docker compose restart
systemctl reload caddy

# 备份/验收
bash scripts/backup.sh
bash scripts/health-check.sh
python3 scripts/probe-models.py
```