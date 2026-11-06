# 排错

## 1. 先做三件事

```bash
# 1. 容器
docker ps -a --filter name=new-api
docker logs --tail 200 new-api

# 2. 本机 API
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status

# 3. 外部 HTTPS
curl -sI https://www.example.com | head -5
```

根据结果走：

```text
外部 502 / 000
├─ 本机 3000 正常 → Caddy/证书/防火墙
└─ 本机 3000 也失败 → new-api 容器

本机 3000 502/000
├─ docker ps 没容器 → compose up -d
├─ 容器重启 → logs
├─ 内存不足 → free -h / swap
└─ 端口占用 → ss -lntp
```

## 2. 502 Bad Gateway

| 检查 | 命令 | 处理 |
|---|---|---|
| 容器在不在 | `docker ps -a --filter name=new-api` | `docker compose up -d` |
| 容器为什么退出 | `docker logs --tail 200 new-api` | 看报错 |
| 端口对不对 | `curl http://127.0.0.1:3000/api/status` | 确认 3000 |
| 内存 | `free -h` | 加 swap/换机器 |
| Caddy 反代 | `journalctl -u caddy -n 100` | 看 upstream 错误 |

加 swap：

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## 3. 证书 / HTTPS

| 现象 | 原因 | 处理 |
|---|---|---|
| `ERR_CONNECTION_REFUSED` | 443 没监听 | `ss -lntp \| grep 443`、`systemctl status caddy` |
| `ERR_CERT_AUTHORITY_INVALID` | 证书没签/自签 | 看 Caddy 日志，确认 80 可达 |
| `ERR_SSL_PROTOCOL_ERROR` | 端口被别的服务占 | 停 nginx/apache |
| 一直 `pending` | ACME 失败/限流 | 查 DNS、80、Let's Encrypt 限流 |
| 域名指向旧 IP | DNS 没改 | `dig +short` |

```bash
dig +short www.example.com
ss -lntp | grep -E ':(80|443)\b'
journalctl -u caddy -n 100 --no-pager
curl -sI http://www.example.com
```

> 80 端口必须能从公网访问。Cloudflare 代理开启时，确认 SSL 模式与源站证书匹配。

## 4. API 401 / 403 / 404 / 429

| 状态 | 常见原因 | 处理 |
|---|---|---|
| 401 | 没带 key / key 错 / 过期 | `Authorization: Bearer sk-...` |
| 403 | 分组/模型无权限 | 后台检查令牌分组、渠道分组 |
| 404 | base_url 少 `/v1` / 模型名错 | 用 `https://www.example.com/v1` |
| 429 | 本地限流 / 上游限流 | 调 `GLOBAL_API_RATE_LIMIT`；查上游额度 |
| 500 | 上游错误 / 渠道配置 | 看 new-api 日志、换渠道 |
| 502 | 上游不可达 | 测上游 `curl` |

排查命令：

```bash
NEWAPI_BASE=http://127.0.0.1:3000 NEWAPI_KEY=sk-xxx \
  python3 scripts/probe-models.py --chat 模型名
```

> 不要把完整 key 贴到公开聊天。只显示前后 4 位。

## 5. 模型页一片红

1. 渠道里填了上游没有的模型。
2. 上游 key 失效。
3. 上游 base_url 错。
4. 上游限流/欠费。
5. 探测脚本用的 key 没权限。

处理：

- 删掉不存在的模型。
- 后台点“测试”。
- 看 `docker logs new-api` 的上游响应。
- 只用真实模型，不要凑数。

## 6. 注册失败

| 现象 | 原因 | 处理 |
|---|---|---|
| 页面没有验证码 | 前端没接 `/lq/captcha` | 按 `docs/custom-frontend.md` 接 |
| `请先完成人机验证` | cookie/header 没带 | 检查 `lq_cap` 或 `X-LQ-Captcha` |
| `答案不正确` | 用户填错 | 刷新重填 |
| `题目已过期` | 超过 10 分钟 | 刷新 |
| `签名不正确` | 密钥被换/多实例不一致 | 确认 `SECRET_FILE` 一致 |
| `注册太频繁` | 同 IP 超 120 次/小时 | 等或调 `RATE_MAX` |
| 502 | gate 挂了 | `systemctl restart turnstile-gate` |

```bash
systemctl status turnstile-gate --no-pager
journalctl -u turnstile-gate -n 100 --no-pager
curl -s http://127.0.0.1:3100/healthz
curl -s http://127.0.0.1:3100/lq/captcha
```

> 网关只保护注册，登录不经过它。登录失败不要查网关。

## 7. 充值不到账

1. 支付商后台看订单状态。
2. new-api 后台看充值记录。
3. 对回调地址：以 new-api 显示的 `notify_url` 为准。
4. 对密钥：`pid` / `key` 是否一致。
5. 看回调日志/容器日志。
6. 小额 1 元重测。

| 现象 | 处理 |
|---|---|
| 支付成功但没订单 | 回调没到/地址错 |
| 订单 pending | 回调验签失败 |
| 重复到账 | 检查订单号去重 |
| 金额不对 | 汇率/手续费/单位配置 |

> 不要用手改数据库补单，除非你完全清楚表结构并已备份。

## 8. 数据库锁 / 损坏

| 现象 | 原因 | 处理 |
|---|---|---|
| `database is locked` | 备份/大事务/多进程 | 重试；避免高峰期备份 |
| 容器反复重启 | DB 损坏/磁盘满 | 停容器，保留文件，恢复备份 |
| 备份文件 0 字节 | 备份时磁盘满/权限 | 检查磁盘/权限，重跑 |
| WAL 很大 | 长事务/未 checkpoint | 正常备份会合并；必要时重启 |

```bash
ls -lh /opt/new-api/data/
sqlite3 /opt/new-api/data/one-api.db 'pragma integrity_check;'
df -h /
```

## 9. 磁盘满

```bash
df -h /
du -sh /var/lib/docker /root/backups /var/log 2>/dev/null
docker system df
```

清理顺序：

1. 旧备份（确认有异地副本）。
2. `journalctl --vacuum-time=14d`。
3. 旧 Docker 镜像（保留一个回滚版本）。
4. Caddy 日志（确认已归档）。
5. 不要删数据库/WAL。

## 10. SSH 连不上

- 可能被 fail2ban 封了，等 10–15 分钟。
- 用云厂商 VNC 控制台进。
- 检查安全组 22 端口。
- 不要连续试密码，会加重封禁。

## 11. 升级后崩

```bash
cd /opt/new-api
docker compose down
# 改回旧 image
docker compose up -d
```

如果 DB 迁移失败：

1. 停容器。
2. 恢复升级前备份。
3. 回滚镜像。
4. 再验证。

## 12. 日志关键词

```bash
docker logs new-api 2>&1 | grep -iE 'error|panic|failed|timeout|refused' | tail -50
journalctl -u caddy -n 200 --no-pager | grep -iE 'error|tls|acme|upstream'
journalctl -u turnstile-gate -n 200 --no-pager
```

## 13. 还不行

收集以下信息再求助（**不要带 key/密码**）：

```text
系统版本：
内存/磁盘：
docker ps：
docker logs 最后 50 行：
curl -sI https://域名：
caddy validate 输出：
最近改了什么：
```

> 贴日志前先删掉 `sk-`、`Bearer`、支付密钥、真实域名/IP（如需要）。