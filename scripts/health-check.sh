#!/usr/bin/env bash
# 灵渠 AI 中转站健康检查
#
# 用法：
#   bash scripts/health-check.sh
#   HEALTH_URL=https://www.example.com/api/status bash scripts/health-check.sh
#
# 退出码：0 = 全部通过；1 = 有失败项。
# 适合 cron 每 10 分钟跑一次，输出追加到 /var/log/lingqu-health.log。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  . "$ENV_FILE"
  set +a
fi

if [ -z "${HEALTH_URL:-}" ]; then
  DOMAIN="${DOMAIN:-www.example.com}"
  HEALTH_URL="https://$DOMAIN/api/status"
fi

DATA_DIR="${DATA_DIR:-/opt/new-api/data}"
FAIL=0

ok()   { echo "[ OK ] $*"; }
bad()  { echo "[FAIL] $*"; FAIL=1; }
warn() { echo "[WARN] $*"; }

echo "=== $(date '+%F %T') health-check ==="

# 1. 站点状态
CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTH_URL" 2>/dev/null || true)"
if [ "$CODE" = "200" ]; then
  ok "站点 $HEALTH_URL -> 200"
else
  bad "站点 $HEALTH_URL -> ${CODE:-无响应}"
fi

# 2. new-api 容器
if command -v docker >/dev/null 2>&1; then
  STATUS="$(docker ps --filter 'name=new-api' --format '{{.Status}}' 2>/dev/null | head -n1)"
  if [ -n "$STATUS" ]; then
    ok "new-api 容器：$STATUS"
  else
    bad "new-api 容器未运行"
  fi
else
  bad "docker 未安装"
fi

# 3. Caddy
if systemctl is-active --quiet caddy 2>/dev/null; then
  ok "caddy 运行中"
else
  bad "caddy 未运行"
fi

# 4. 验证码网关
if systemctl is-active --quiet turnstile-gate 2>/dev/null; then
  GATE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:3100/healthz 2>/dev/null || true)"
  if [ "$GATE" = "200" ]; then
    ok "验证码网关 /healthz -> 200"
  else
    bad "验证码网关无响应（HTTP ${GATE:-?}）"
  fi
else
  bad "turnstile-gate 未运行"
fi

# 5. 数据库
if [ -f "$DATA_DIR/one-api.db" ]; then
  ok "数据库存在：$DATA_DIR/one-api.db"
else
  bad "数据库不存在：$DATA_DIR/one-api.db"
fi

# 6. 磁盘（/ 使用率 >= 85% 报警）
DISK="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
if [ -n "${DISK:-}" ] && [ "$DISK" -ge 85 ] 2>/dev/null; then
  warn "根分区使用率 ${DISK}%"
else
  ok "根分区使用率 ${DISK:-?}%"
fi

# 7. 内存（可用 < 80MB 报警）
if command -v free >/dev/null 2>&1; then
  AVAIL="$(free -m | awk '/^Mem:/ {print $7}')"
  if [ -n "${AVAIL:-}" ] && [ "$AVAIL" -lt 80 ] 2>/dev/null; then
    warn "可用内存 ${AVAIL}MB，偏低"
  else
    ok "可用内存 ${AVAIL:-?}MB"
  fi
fi

# 8. 最近备份（超过 36 小时报警）
LATEST="$(find "${BACKUP_DIR:-/root/backups}" -maxdepth 1 -type f -name 'one-api-*.db' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f1)"
if [ -n "${LATEST:-}" ]; then
  AGE_H=$(( ( $(date +%s) - ${LATEST%.*} ) / 3600 ))
  if [ "$AGE_H" -gt 36 ]; then
    warn "最近备份在 ${AGE_H} 小时前"
  else
    ok "最近备份在 ${AGE_H} 小时前"
  fi
else
  warn "没有找到备份文件"
fi

echo "=== 结果：$([ "$FAIL" -eq 0 ] && echo PASS || echo FAIL) ==="
exit "$FAIL"