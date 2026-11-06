# 运维

## 1. 每日

```bash
# 站点
curl -sI https://www.example.com | head -3

# 容器
docker ps --filter name=new-api
docker stats --no-stream

# 服务
systemctl is-active caddy turnstile-gate

# 健康检查
bash /root/lingqu-relay/scripts/health-check.sh
```

看日志：

```bash
docker logs --tail 100 new-api
journalctl -u caddy -n 50 --no-pager
journalctl -u turnstile-gate -n 50 --no-pager
tail -n 50 /var/log/lingqu-health.log
```

## 2. 每周

- 看磁盘：`df -h /`，超过 80% 处理。
- 看备份：`ls -lh /root/backups`，确认每天都有。
- 看模型：`python3 scripts/probe-models.py`，红的渠道处理。
- 看错误率：后台日志/上游账单。
- 看证书：`echo | openssl s_client -servername www.example.com -connect www.example.com:443 2>/dev/null | openssl x509 -noout -dates`

## 3. 每月

- 系统更新：`apt update && apt upgrade -y`（先备份）。
- 镜像更新：先备份，再拉新镜像，观察一天。
- 备份恢复演练：找一台测试机，按 README 8.2 恢复。
- 清理旧日志/镜像：
  ```bash
  docker system df
  docker image prune -f
  journalctl --vacuum-time=14d
  ```
  > 不要随便 `docker system prune -a`，会删掉回滚用的旧镜像。
- 检查管理员账号、令牌、分组、价格。

## 4. 升级 new-api

```bash
# 1. 备份
bash /root/lingqu-relay/scripts/backup.sh

# 2. 记录当前镜像
docker inspect new-api --format '{{.Config.Image}} {{.Image}}'

# 3. 拉新镜像
cd /opt/new-api
docker compose pull

# 4. 重启
docker compose up -d

# 5. 验证
docker logs --tail 100 new-api
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status
bash /root/lingqu-relay/scripts/health-check.sh
```

### 回滚

```bash
cd /opt/new-api
docker compose down
# 把 docker-compose.yml 的 image 改成旧 tag/digest
docker compose up -d
```

> 生产环境不要长期用 `latest`。第一次拉取后记录 digest，改成固定版本。

## 5. 恢复

```bash
# 停服务
cd /opt/new-api && docker compose stop new-api

# 解包配置
tar xzf /root/backups/ops-XXXX.tar.gz -C /

# 换数据库
cp /root/backups/one-api-XXXX.db /opt/new-api/data/one-api.db
rm -f /opt/new-api/data/one-api.db-wal /opt/new-api/data/one-api.db-shm

# 起服务
docker compose start new-api
systemctl daemon-reload
systemctl enable --now turnstile-gate caddy

# 验证
bash /root/lingqu-relay/scripts/health-check.sh
```

> 恢复会丢备份之后的用户/订单数据。先确认备份时间点。

## 6. 日志与磁盘

| 文件 | 内容 | 清理 |
|---|---|---|
| `/var/log/caddy/access.log` | 访问日志 | Caddy 自动滚动 5 份 |
| `docker logs new-api` | 容器日志 | compose 限制 10MB×3 |
| `/var/log/lingqu-*.log` | 脚本日志 | logrotate 或手动 |
| `/root/backups` | 备份 | 脚本自动保留 7/14 天 |
| `/var/lib/docker` | 镜像/容器 | `docker image prune` |

Caddy 日志如果太大，可以在 Caddyfile 调 `roll_size` / `roll_keep`，或改用 journald。

## 7. 容量估算

| 项 | 量级 |
|---|---|
| 系统 + Docker | 3–5GB |
| new-api 镜像 | 几百 MB |
| SQLite | 用户/日志增长，几 MB 到几 GB |
| 备份 | 每天 2 个文件，几十 MB 到几百 MB |
| 静态页 | 几 MB |

日志是主要增长源。日请求量大时，定期归档/清空，不要把日志无限堆在根分区。

## 8. 事故处理

### 8.1 站点 502

1. `docker ps` 看容器。
2. `docker logs --tail 200 new-api`。
3. `free -h` 看内存。
4. `curl http://127.0.0.1:3000/api/status`。
5. 起不来先回滚镜像/恢复 DB。

### 8.2 被刷

1. 看 Caddy 日志 top IP：
   ```bash
   awk '{print $1}' /var/log/caddy/access.log | sort | uniq -c | sort -nr | head
   ```
2. 临时封 IP（ufw/iptables/Cloudflare）。
3. 降额度/关注册/轮换 key。
4. 不要直接删用户数据，先留证据。

### 8.3 上游 key 泄露

1. 上游后台吊销 key。
2. new-api 渠道换新 key。
3. 查日志异常调用。
4. 评估账单，必要时停服。

### 8.4 数据库损坏

1. 停 new-api。
2. 保留坏文件（不要覆盖）。
3. 用最近备份恢复。
4. 起服务后检查用户/订单/渠道。
5. 复盘磁盘/断电/并发原因。

## 9. 变更管理

- 改 Caddyfile 前备份，`caddy validate` 后再 reload。
- 改 compose 前备份，`docker compose config` 检查。
- 改 crontab 前 `crontab -l > /tmp/crontab.bak`。
- 改数据库前备份，禁止手改余额。
- 每次变更记录：时间、改了什么、为什么、怎么回滚。

## 10. 证书

Caddy 自动续期。需要确认：

- 80 端口对公网可达（HTTP-01）。
- DNS 没换 IP。
- 系统时间正确：`timedatectl`。

强制重签（谨慎）：

```bash
systemctl reload caddy
journalctl -u caddy -n 100 --no-pager
```

> 不要删除 `/var/lib/caddy/.local/share/caddy` 里的证书，除非确认要重签。