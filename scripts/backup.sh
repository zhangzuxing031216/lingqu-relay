#!/usr/bin/env bash
# 灵渠 AI 中转站备份脚本
#
# 做什么：
#   1. SQLite 在线备份（自动合并 WAL，不用停容器）
#   2. 打包 compose / static / Caddyfile / systemd / 验证码网关 / crontab
#   3. 按天数清理旧备份
#   4. 可选 rsync 到异地
#
# 用法：
#   bash scripts/backup.sh
#   BACKUP_REMOTE=user@host:/backups/ bash scripts/backup.sh
#
# 注意：
#   - 备份包含用户/订单数据，权限设为 600。
#   - 不要把备份提交到 Git。
#   - 恢复前先停 new-api，避免 WAL 覆盖。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  . "$ENV_FILE"
  set +a
fi

BACKUP_DIR="${BACKUP_DIR:-/root/backups}"
DATA_DIR="${DATA_DIR:-/opt/new-api/data}"
STATIC_DIR="${STATIC_DIR:-/opt/new-api/static}"
KEEP_DB_DAYS="${BACKUP_KEEP_DB_DAYS:-7}"
KEEP_OPS_DAYS="${BACKUP_KEEP_OPS_DAYS:-14}"

DB="$DATA_DIR/one-api.db"
STAMP="$(date +%F_%H%M)"
DB_OUT="$BACKUP_DIR/one-api-$STAMP.db"
OPS_OUT="$BACKUP_DIR/ops-$STAMP.tar.gz"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR" 2>/dev/null || true

if [ ! -f "$DB" ]; then
  echo "[backup] ERROR: 找不到数据库 $DB" >&2
  exit 1
fi

# ── 1. SQLite 在线备份 ─────────────────────────────
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DB" ".backup '$DB_OUT'"
else
  echo "[backup] sqlite3 未安装，改用 Python"
  python3 - "$DB" "$DB_OUT" <<'PY'
import sqlite3
import sys

src, dst = sys.argv[1], sys.argv[2]
s = sqlite3.connect(src)
d = sqlite3.connect(dst)
try:
    s.backup(d)
finally:
    d.close()
    s.close()
PY
fi
chmod 600 "$DB_OUT"

# ── 2. 打包配置 ────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

crontab -l > "$TMP/crontab.txt" 2>/dev/null || true

TAR_PATHS=()
for p in \
  "opt/new-api/docker-compose.yml" \
  "opt/new-api/static" \
  "etc/caddy/Caddyfile" \
  "etc/systemd/system/turnstile-gate.service" \
  "root/turnstile_gate.py" \
  "root/ops" \
  "root/lingqu-relay"; do
  if [ -e "/$p" ]; then
    TAR_PATHS+=("$p")
  fi
done

if [ "${#TAR_PATHS[@]}" -eq 0 ]; then
  echo "[backup] ERROR: 没有找到可打包的配置" >&2
  exit 1
fi

tar czf "$OPS_OUT" \
  --exclude='root/lingqu-relay/.git' \
  --exclude='root/lingqu-relay/.env' \
  --exclude='root/lingqu-relay/__pycache__' \
  -C / "${TAR_PATHS[@]}" \
  -C "$TMP" crontab.txt
chmod 600 "$OPS_OUT"

# ── 3. 清理旧备份 ──────────────────────────────────
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'one-api-*.db' -mtime +"$KEEP_DB_DAYS" -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'ops-*.tar.gz' -mtime +"$KEEP_OPS_DAYS" -delete

# ── 4. 异地备份（可选） ────────────────────────────
if [ -n "${BACKUP_REMOTE:-}" ]; then
  if ! command -v rsync >/dev/null 2>&1; then
    echo "[backup] ERROR: 配置了 BACKUP_REMOTE 但没有 rsync" >&2
    exit 1
  fi
  rsync -az "$DB_OUT" "$OPS_OUT" "$BACKUP_REMOTE"
  echo "[backup] 已同步到 $BACKUP_REMOTE"
fi

echo "[backup] OK"
echo "  DB : $DB_OUT ($(du -h "$DB_OUT" | cut -f1))"
echo "  OPS: $OPS_OUT ($(du -h "$OPS_OUT" | cut -f1))"