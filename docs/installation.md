# 安装

> 这是 `README.md` 的精简命令版。第一次部署建议先完整读一遍 README 的“十步部署”。

## 0. 前置

- Ubuntu 22.04 / 24.04，root 或 sudo
- 2GB 内存 / 20GB+ 磁盘
- 域名，`@` 和 `www` 两条 A 记录指向服务器
- 80/443 对公网可达
- 上游 API 的 `base_url` / `key` / 模型列表
- 支付账号（可选）

## 1. DNS

```bash
dig +short example.com
dig +short www.example.com
```

都返回服务器 IP 再继续。

## 2. 一键初始化

```bash
git clone https://github.com/YOUR_NAME/lingqu-relay.git /root/lingqu-relay
cd /root/lingqu-relay

sudo bash scripts/bootstrap-ubuntu.sh \
  --domain example.com \
  --email admin@example.com
```

脚本会安装依赖、写 compose/Caddyfile、启动 new-api/Caddy/gate。

> 已经有 `/opt/new-api` 数据时，脚本默认不覆盖 compose。要覆盖加 `--force`，仍会先备份。

## 3. 手动安装（脚本失败时）

```bash
apt update
apt install -y docker.io caddy sqlite3 python3 curl rsync
systemctl enable --now docker

# compose
apt install -y docker-compose-v2 || apt install -y docker-compose-plugin || apt install -y docker-compose

mkdir -p /opt/new-api/data /opt/new-api/static /var/log/caddy
cp deploy/docker-compose.yml /opt/new-api/docker-compose.yml
cd /opt/new-api
docker compose up -d
```

验证：

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status
```

## 4. Caddy

```bash
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%F-%H%M) 2>/dev/null || true
cp deploy/Caddyfile.example /etc/caddy/Caddyfile

DOMAIN=example.com
EMAIL=admin@example.com
sed -i "s/YOUR_DOMAIN/$DOMAIN/g; s/YOUR_EMAIL/$EMAIL/g" /etc/caddy/Caddyfile

caddy validate --config /etc/caddy/Caddyfile
systemctl enable --now caddy
systemctl reload caddy
```

验证：

```bash
curl -sI https://www.example.com | head -5
```

## 5. 初始化后台

1. 打开 `https://www.example.com`
2. 创建管理员
3. 改强密码
4. 先关闭公开注册

## 6. 接渠道

后台 → 渠道 → 新建：

| 字段 | 值 |
|---|---|
| 类型 | 与上游匹配 |
| Base URL | 上游地址（通常以 `/v1` 结尾） |
| Key | 上游 key |
| 模型 | 只填真实存在的 |
| 分组 | 默认 |

验证：

```bash
NEWAPI_BASE=http://127.0.0.1:3000 \
NEWAPI_KEY=你的令牌 \
python3 scripts/probe-models.py --chat 你的模型名
```

## 7. 验证码网关

```bash
cp deploy/turnstile_gate.py /root/turnstile_gate.py
cp deploy/turnstile-gate.service /etc/systemd/system/turnstile-gate.service
systemctl daemon-reload
systemctl enable --now turnstile-gate

curl -s http://127.0.0.1:3100/healthz
curl -s http://127.0.0.1:3100/lq/captcha
```

Caddyfile 必须包含：

```text
handle /lq/captcha* {
    reverse_proxy 127.0.0.1:3100
}
handle /api/user/register {
    reverse_proxy 127.0.0.1:3100
}
```

> 前端需要把 `token|答案` 写入 `lq_cap` cookie，或放到 `X-LQ-Captcha` 请求头。
> 本仓库不包含定制前端；不会改前端就先用“关闭公开注册 + 邀请制”。

## 8. cron 与备份

```bash
crontab -l > /tmp/crontab.bak 2>/dev/null || true
crontab deploy/crontab.example
crontab -l

bash scripts/backup.sh
ls -lh /root/backups
```

恢复见 `README.md` 第 8.2 节。

## 9. 验收

```bash
bash scripts/health-check.sh
```

再按 README 附录 A 逐项打勾。

## 10. 常见安装失败

| 现象 | 处理 |
|---|---|
| `docker compose` 不存在 | 装 `docker-compose-v2` / `docker-compose-plugin` |
| 3000 端口占用 | `ss -lntp \| grep 3000`，停旧服务 |
| Caddy 证书失败 | DNS、80 端口、443 占用 |
| `caddy validate` 失败 | 看行号，多半是占位符没替换 |
| 内存不足 | 加 2GB swap |
| 拉镜像慢 | 配 Docker 镜像加速 |