#!/usr/bin/env bash
# 灵渠 AI 中转站 · Ubuntu 初始化脚本
#
# 做什么：
#   1. 检查 root / 系统 / 内存 / 磁盘
#   2. 安装 docker、compose、caddy、sqlite3、python3、curl、rsync
#   3. 创建 /opt/new-api/{data,static}
#   4. 写入 docker-compose.yml（不覆盖已有文件，除非 --force）
#   5. 写入 Caddyfile（先备份旧文件）
#   6. 安装注册验证码网关和 systemd 单元
#   7. 启动 docker / caddy / turnstile-gate
#
# 用法：
#   sudo bash scripts/bootstrap-ubuntu.sh --domain api.example.com --email admin@example.com
#   sudo bash scripts/bootstrap-ubuntu.sh --domain api.example.com --email admin@example.com --force
#
# 注意：
#   - 不会自动改 DNS，也不会自动填上游 key / 支付密钥。
#   - 不会自动装 crontab；装完后按 README 第 9 步手动装。
#   - 已有 /opt/new-api 数据时，默认不覆盖 compose。

set -euo pipefail

DOMAIN=""
EMAIL=""
FORCE=0
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
用法：
  sudo bash scripts/bootstrap-ubuntu.sh --domain <域名> [--email <邮箱>] [--force]

参数：
  --domain   主域名，不带 www，例如 api.example.com
  --email    ACME 通知邮箱，默认 admin@<域名>
  --force    覆盖已有 docker-compose.yml / Caddyfile（仍会先备份）
  --repo     仓库路径，默认脚本上一级
  -h, --help 显示帮助
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --repo) REPO_DIR="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1"; usage; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: 请用 root 或 sudo 运行。" >&2
  exit 1
fi

if [ -z "$DOMAIN" ]; then
  echo "ERROR: 必须传 --domain，例如 --domain api.example.com" >&2
  exit 2
fi
DOMAIN="${DOMAIN#www.}"
EMAIL="${EMAIL:-admin@$DOMAIN}"

if [ ! -f "$REPO_DIR/deploy/docker-compose.yml" ] || [ ! -f "$REPO_DIR/deploy/Caddyfile.example" ]; then
  echo "ERROR: 找不到 $REPO_DIR/deploy/*，请从仓库根目录运行。" >&2
  exit 1
fi

# ── 0. 环境检查 ────────────────────────────────────
echo "== 0. 环境检查 =="
. /etc/os-release
echo "系统：$PRETTY_NAME"
case "${ID:-}" in
  ubuntu|debian) ;;
  *) echo "WARN: 只在 Ubuntu/Debian 上测试过，继续可能有差异。" ;;
esac

MEM_MB="$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
AVAIL_KB="$(df -Pk / | awk 'NR==2 {print $4}')"
echo "内存：${MEM_MB}MB"
echo "根分区可用：$((AVAIL_KB / 1024))MB"
if [ "$MEM_MB" -lt 1400 ]; then
  echo "WARN: 内存低于 1.5GB，Docker + 备份可能 OOM。建议加 swap。"
fi
if [ "$AVAIL_KB" -lt 15000000 ]; then
  echo "ERROR: 根分区可用低于 15GB，先扩盘。" >&2
  exit 1
fi

if ss -lntp 2>/dev/null | grep -qE ':(80|443)[[:space:]]'; then
  echo "WARN: 80/443 已被占用："
  ss -lntp 2>/dev/null | grep -E ':(80|443)[[:space:]]' || true
  if ! systemctl is-active --quiet caddy 2>/dev/null; then
    echo "ERROR: 占用者不是 caddy。先停掉旧服务（nginx/apache）再运行。" >&2
    exit 1
  fi
fi

# ── 1. 安装依赖 ────────────────────────────────────
echo "== 1. 安装依赖 =="
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y docker.io caddy sqlite3 python3 curl rsync
systemctl enable --now docker

if ! docker compose version >/dev/null 2>&1; then
  apt install -y docker-compose-v2 2>/dev/null \
    || apt install -y docker-compose-plugin 2>/dev/null \
    || apt install -y docker-compose 2>/dev/null \
    || true
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "ERROR: 没有可用的 docker compose。" >&2
  exit 1
fi

echo "docker: $(docker --version)"
echo "compose: $("${COMPOSE[@]}" version | head -n1)"
echo "caddy: $(caddy version | head -n1)"

# ── 2. 目录 ────────────────────────────────────────
echo "== 2. 创建目录 =="
mkdir -p /opt/new-api/data /opt/new-api/static /var/log/caddy
cd /opt/new-api

# ── 3. compose ─────────────────────────────────────
echo "== 3. docker-compose.yml =="
if [ -f /opt/new-api/docker-compose.yml ] && [ "$FORCE" -ne 1 ]; then
  echo "已存在 /opt/new-api/docker-compose.yml，跳过（--force 可覆盖，仍会备份）"
else
  if [ -f /opt/new-api/docker-compose.yml ]; then
    cp /opt/new-api/docker-compose.yml "/opt/new-api/docker-compose.yml.bak.$(date +%F-%H%M)"
  fi
  cp "$REPO_DIR/deploy/docker-compose.yml" /opt/new-api/docker-compose.yml
  echo "已写入 /opt/new-api/docker-compose.yml"
fi

echo "启动 new-api ..."
"${COMPOSE[@]}" up -d

# ── 4. Caddy ───────────────────────────────────────
echo "== 4. Caddyfile =="
if [ -f /etc/caddy/Caddyfile ]; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%F-%H%M)"
fi
sed "s/YOUR_DOMAIN/$DOMAIN/g; s/YOUR_EMAIL/$EMAIL/g" \
  "$REPO_DIR/deploy/Caddyfile.example" > /etc/caddy/Caddyfile.new
mv /etc/caddy/Caddyfile.new /etc/caddy/Caddyfile

if caddy validate --config /etc/caddy/Caddyfile; then
  systemctl enable --now caddy
  systemctl reload caddy
  echo "Caddy 已加载：https://www.$DOMAIN"
else
  echo "ERROR: Caddyfile 校验失败。旧文件已备份为 /etc/caddy/Caddyfile.bak.*" >&2
  exit 1
fi

# ── 5. 验证码网关 ──────────────────────────────────
echo "== 5. 注册验证码网关 =="
if [ -f /root/turnstile_gate.py ]; then
  cp /root/turnstile_gate.py "/root/turnstile_gate.py.bak.$(date +%F-%H%M)"
fi
cp "$REPO_DIR/deploy/turnstile_gate.py" /root/turnstile_gate.py
cp "$REPO_DIR/deploy/turnstile-gate.service" /etc/systemd/system/turnstile-gate.service
systemctl daemon-reload
systemctl enable --now turnstile-gate
systemctl restart turnstile-gate
if [ -f /root/lq_captcha.secret ]; then
  chmod 600 /root/lq_captcha.secret
fi

# ── 6. 验收提示 ────────────────────────────────────
echo
echo "== 完成 =="
echo "站点：https://www.$DOMAIN"
echo "本机状态：curl -s -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:3000/api/status"
echo "验证码：curl -s http://127.0.0.1:3100/healthz"
echo
echo "下一步："
echo "  1. 打开 https://www.$DOMAIN 初始化管理员"
echo "  2. 后台接渠道（上游 key 不要写进 Git）"
echo "  3. 安装 cron：crontab $REPO_DIR/deploy/crontab.example"
echo "  4. 手动备份：bash $REPO_DIR/scripts/backup.sh"
echo "  5. 健康检查：bash $REPO_DIR/scripts/health-check.sh"
echo
echo "如果证书没下来：确认 DNS 已生效、80 端口对公网可达，然后："
echo "  journalctl -u caddy -n 100 --no-pager"