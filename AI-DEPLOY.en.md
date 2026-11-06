# AI-DEPLOY.md · Lingqu AI Relay Deployment Protocol (for AI to read)

> **Language / 语言**: [中文](AI-DEPLOY.md) | English

> Target machine: Ubuntu 22.04 / 24.04, root or sudo.
> Target outcome: `https://www.<domain>` opens, `/api/status` returns 200, the new-api admin panel can be logged into, the registration captcha gateway works, and backups run.
> Template version: 2026-11
>
> This document is a **sanitized template**. Every `YOUR_DOMAIN` / `YOUR_EMAIL` / `YOUR_KEY` must be replaced with a real value, and real values **must not be written into Git**.

---

## 0. Your role

You are the deployment operator. Work under the following protocol:

1. **Gather evidence before acting**: OS version, memory, disk, ports, DNS, and whether anything is already installed.
2. **One step at a time**: execute → paste the raw output → decide → next step.
3. **Do not fabricate**: do not call a command finished if you did not run it; do not call output normal if you did not see it.
4. **Do not overwrite**: if `/opt/new-api`, `/etc/caddy/Caddyfile`, or crontab already exist, back them up before changing anything.
5. **Do not touch secrets**: never write keys, passwords, or payment secrets into the repo, logs, or chat history.
6. **Fall back on failure**: follow the fallback paths in this document; do not get stuck on a single source.
7. **Acceptance requires evidence**: command text + output + HTTP status code.

---

## 1. Six things you must clarify before starting

If the answer can be found on the system, do not ask.

1. What is the domain? Does the `A` record already point to this machine?
2. Server IP, OS version, memory, disk?
3. Do you have the upstream API's `base_url` / `key` / model list?
4. Will payments be connected? If so, are the `pid` / `key` / callback URL all available?
5. Is new-api / Caddy / another service on 80/443 already running on this machine?
6. Am I permitted to modify `/etc/caddy/Caddyfile`, crontab, and systemd?

> When the information is incomplete, do the parts that do not depend on the upstream/payment first: DNS, Docker, new-api, Caddy, admin panel. The upstream and payment can be added later.

---

## 2. Hard constraints

- Only Ubuntu 22.04/24.04 x86_64 is supported.
- You must be able to change DNS; if you cannot, do not continue.
- 80/443 must be reachable from the public internet; otherwise the certificate will fail.
- new-api must listen only on `127.0.0.1:3000`; `0.0.0.0:3000` is forbidden.
- The gateway must listen only on `127.0.0.1:3100`.
- Do not commit `/root/lq_captcha.secret`, `.env`, the database, or payment secrets to Git.
- Do not paste full keys in public chat; show only the last 4 characters when necessary.
- Do not disable the firewall in order to "troubleshoot".
- Do not run a `latest` upgrade directly on a production machine; back up first.

---

## 3. Phase 0 · Environment evidence

```bash
# 3.1 System
cat /etc/os-release
uname -m
free -h
df -h /

# 3.2 Port usage
ss -lntp | grep -E ':(80|443|3000|3100)\b' || true

# 3.3 Installed services
systemctl is-active docker caddy 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || true

# 3.4 DNS
dig +short YOUR_DOMAIN
dig +short www.YOUR_DOMAIN

# 3.5 Public IP
curl -s https://api.ipify.org; echo
```

### Decision table

| Result | Branch |
|---|---|
| Memory < 1.5GB | Warning: possible OOM; add swap or change machines |
| Disk < 15GB | Stop; expand the disk first |
| 80/443 occupied | Identify what service it is first; do not kill it directly |
| `/opt/new-api` already exists | Back up first; do not overwrite |
| DNS does not point to this machine | Stop; wait for DNS to take effect |
| `docker` not installed | Install in Phase 1 |
| new-api already installed and running | Skip Phase 2; go straight to acceptance/rework |

**Evidence format**:

```text
[Phase 0]
Command: free -h
Output: Mem: 1.9Gi ...
Decision: 2GB, may continue
```

---

## 4. Phase 1 · Install dependencies

### 4.1 Preferred: bootstrap script

```bash
sudo bash scripts/bootstrap-ubuntu.sh \
  --domain example.com \
  --email admin@example.com
```

The script will:

1. Check root / Ubuntu / memory / disk.
2. `apt update` + install docker, compose, caddy, sqlite3, python3, curl, rsync.
3. Create `/opt/new-api/{data,static}`.
4. Back up the existing Caddyfile, write the template, and substitute the domain/email.
5. Install the captcha gateway and the systemd unit.
6. Start docker / caddy / turnstile-gate.
7. Print the acceptance commands.

> If the script fails, install manually per 4.2; do not re-run it over and over and overwrite things.

### 4.2 Manual installation

```bash
apt update
apt install -y docker.io docker-compose-v2 caddy sqlite3 python3 curl rsync
systemctl enable --now docker
```

If `docker-compose-v2` does not exist:

```bash
apt install -y docker-compose-plugin || apt install -y docker-compose
```

Verify:

```bash
docker --version
docker compose version || docker-compose --version
caddy version
sqlite3 --version
```

---

## 5. Phase 2 · new-api

### 5.1 Prepare directories

```bash
mkdir -p /opt/new-api/data /opt/new-api/static
cd /opt/new-api
```

### 5.2 Write the compose file

Copy the template from the repo:

```bash
cp /root/lingqu-relay/deploy/docker-compose.yml /opt/new-api/docker-compose.yml
```

> If the repo is not at `/root/lingqu-relay`, use the actual path.

### 5.3 Start

```bash
cd /opt/new-api
docker compose up -d
docker ps --filter name=new-api
```

### 5.4 Verify

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status
```

Expect `200`.

### 5.5 Failure handling

| Symptom | Handling |
|---|---|
| `port is already allocated` | 3000 is taken; check `ss -lntp` and stop the old container |
| Container starts and then exits | `docker logs new-api` |
| Image pull fails | Configure a Docker registry mirror; or switch networks |
| Insufficient memory | Add swap: `fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile` |
| `/api/status` 502 | The container is not up; check the logs |

---

## 6. Phase 3 · Caddy + HTTPS

### 6.1 Write the Caddyfile

```bash
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%F-%H%M) 2>/dev/null || true
cp /root/lingqu-relay/deploy/Caddyfile.example /etc/caddy/Caddyfile
```

Edit `/etc/caddy/Caddyfile` and replace:

- `YOUR_DOMAIN` → your domain (without `www`)
- `YOUR_EMAIL` → your email

### 6.2 Validate

```bash
caddy validate --config /etc/caddy/Caddyfile
```

It must say `Valid configuration`.

### 6.3 Reload

```bash
systemctl reload caddy
systemctl status caddy --no-pager
```

### 6.4 Verify

```bash
curl -sI https://www.YOUR_DOMAIN | head -5
curl -s https://www.YOUR_DOMAIN/api/status | head -c 300; echo
```

Expect:

- `HTTP/2 200` or 301/302
- `/api/status` returns JSON

### 6.5 Certificate failure troubleshooting

```text
Certificate failure
├─ DNS not propagated → dig +short
├─ 80 unreachable → allow it in the security group/firewall
├─ 443 occupied → ss -lntp
├─ Caddy logs → journalctl -u caddy -n 100
└─ domain misspelled → check the Caddyfile
```

> Do not tell the user to "turn off HTTPS". Certificates are mandatory.

---

## 7. Phase 4 · Initialize the admin panel

1. Open `https://www.YOUR_DOMAIN`.
2. Create the administrator as prompted.
3. Change to a strong password immediately.
4. Turn off public registration first.
5. Record the administrator username (do not record the password in the repo).

Verify:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://www.YOUR_DOMAIN/
```

---

## 8. Phase 5 · Channels and models

### 8.1 Admin panel configuration

Channels → New:

- Type: matching the upstream
- Base URL: upstream address
- Key: upstream key
- Models: only fill in ones that actually exist
- Group: default

### 8.2 Command-line probe

```bash
NEWAPI_BASE=http://127.0.0.1:3000 \
NEWAPI_KEY=你的令牌 \
python3 scripts/probe-models.py
```

Expect:

- `GET /v1/models` 200
- Models are listed
- Optional `--chat <model>` returns 200

### 8.3 Common failures

| Symptom | Cause |
|---|---|
| 401 | Wrong key / missing Bearer |
| 403 | Group/model permission |
| 404 | `base_url` is missing `/v1` |
| 429 | Upstream rate limit/quota |
| 502 | Upstream unreachable |

> Do not put the upstream key into terminal history. Use environment variables or interactive input.

---

## 9. Phase 6 · Registration captcha gateway

### 9.1 Install

```bash
cp /root/lingqu-relay/deploy/turnstile_gate.py /root/turnstile_gate.py
cp /root/lingqu-relay/deploy/turnstile-gate.service /etc/systemd/system/turnstile-gate.service
systemctl daemon-reload
systemctl enable --now turnstile-gate
```

### 9.2 Verify

```bash
systemctl status turnstile-gate --no-pager
curl -s http://127.0.0.1:3100/lq/captcha
```

Expect JSON: `{"success":true,"data":{"token":"...","q":"3 + 4"}}`

### 9.3 Caddy routing

Confirm the Caddyfile contains:

```text
handle /lq/captcha* {
    reverse_proxy 127.0.0.1:3100
}
handle /api/user/register {
    reverse_proxy 127.0.0.1:3100
}
```

Reload:

```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

### 9.4 Notes

- The secret file `/root/lq_captcha.secret` is generated automatically.
- Do not copy it into the repo.
- The gateway protects registration only; login does not go through it.
- There is a rate limit per IP; do not click wildly when testing.

---

## 10. Phase 7 · Billing and payments (optional)

### 10.1 Do not connect payments yet

- Add quota / redemption codes manually in the admin panel.
- Verify that users, tokens, and deduction work correctly.
- Then connect payments.

### 10.2 Connect payments

1. Get the `pid` / `key` from the payment provider's admin panel.
2. Fill in the payment configuration in the new-api admin panel.
3. The callback URL must be the `notify_url` shown in the new-api admin panel.
4. Test with a 1 yuan top-up.
5. Check: crediting, deduction, refunds, callback retries.

### 10.3 Prohibited

- Do not write payment secrets into the Caddyfile / frontend JS.
- Do not expose "test mode" directly to the public internet.
- Do not accept large amounts when there are no refund rules.

---

## 11. Phase 8 · Scheduled tasks and backups

### 11.1 Install cron

```bash
crontab -l > /tmp/crontab.bak 2>/dev/null || true
crontab /root/lingqu-relay/deploy/crontab.example
crontab -l
```

### 11.2 Run a backup manually once

```bash
bash /root/lingqu-relay/scripts/backup.sh
ls -lh /root/backups
```

Expect:

- `one-api-YYYY-MM-DD_HHMM.db`
- `ops-YYYY-MM-DD_HHMM.tar.gz`

### 11.3 Verify the DB is readable

```bash
sqlite3 /root/backups/one-api-*.db 'select count(*) from users;'
```

### 11.4 Off-site backup

```bash
BACKUP_REMOTE=user@host:/backups/ bash /root/lingqu-relay/scripts/backup.sh
```

> No off-site backup = no backup.

---

## 12. Phase 9 · Acceptance

### 12.1 Automated

```bash
bash /root/lingqu-relay/scripts/health-check.sh
```

Expect exit code 0.

### 12.2 Manual

| Item | Command | Pass criterion |
|---|---|---|
| Homepage | `curl -sI https://www.YOUR_DOMAIN` | 200/301/302 |
| Status | `curl -s https://www.YOUR_DOMAIN/api/status` | JSON |
| Models | `curl -s -H "Authorization: Bearer $KEY" https://www.YOUR_DOMAIN/v1/models` | has data |
| Captcha | `curl -s https://www.YOUR_DOMAIN/lq/captcha` | token/q |
| Login | Browser | can enter the admin panel |
| Channels | Admin panel test | passes |
| Backup | `ls /root/backups` | file from today |
| cron | `crontab -l` | tasks present |

### 12.3 Delivery report

```text
[Conclusion] Success / Partial success / Failure

[Environment]
- OS:
- Memory/Disk:
- Domain:
- new-api image:
- Caddy version:

[Execution]
1. Dependencies:
2. compose:
3. Caddy:
4. Gateway:
5. cron/backup:

[Acceptance]
- /api/status:
- /v1/models:
- Registration captcha:
- Backup files:
- health-check:

[Unresolved/Risks]
- ...

[Next steps]
- ...
```

---

## 13. Fault tree

### 13.1 502

```text
502
├─ docker ps shows no new-api → docker compose up -d
├─ container restarting → docker logs new-api
├─ insufficient memory → free -h / add swap
└─ wrong port → confirm 127.0.0.1:3000
```

### 13.2 Certificate

```text
Certificate failure
├─ DNS → dig
├─ 80 → security group/ufw
├─ 443 → ss -lntp
├─ Caddy logs → journalctl -u caddy
└─ rate limited → wait for Let's Encrypt to retry
```

### 13.3 Registration failure

```text
Registration 400
├─ captcha expired → refresh
├─ wrong answer → re-enter
├─ bad signature → check whether the secret was replaced
└─ upstream returns English → check the gateway logs

Registration 429
├─ same-IP rate → wait
└─ adjust RATE_MAX
```

### 13.4 Top-up not credited

```text
Not credited
├─ wrong callback URL → match the admin panel notify_url
├─ wrong key → re-enter
├─ payment provider did not call back → check the payment provider logs
├─ duplicate order number → check the DB
└─ test with a small amount first
```

---

## 14. Rollback

### 14.1 Roll back Caddy

```bash
cp /etc/caddy/Caddyfile.bak.YYYY-MM-DD-HHMM /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

### 14.2 Roll back the new-api image

```bash
cd /opt/new-api
docker compose down
# Change the image in docker-compose.yml to the old tag
docker compose up -d
```

### 14.3 Roll back the database

```bash
docker compose stop new-api
cp /root/backups/one-api-YYYY-MM-DD.db /opt/new-api/data/one-api.db
rm -f /opt/new-api/data/one-api.db-wal /opt/new-api/data/one-api.db-shm
docker compose start new-api
```

> Rolling back the DB loses user/order data created after the backup. Confirm first.

---

## 15. Prohibitions

1. Do not expose 3000/3100 to the public internet.
2. Do not write keys/passwords into Git, the frontend, or the Caddyfile.
3. Do not upgrade/change the database without a backup.
4. Do not use `latest` for a production upgrade.
5. Do not disable HTTPS / certificate validation.
6. Do not fabricate acceptance output.
7. Do not run build + backup + heavy traffic simultaneously on a 1.5GB machine.
8. Do not help users resell in violation of the upstream terms.

---

## 16. Quick command card

```bash
# Status
docker ps
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/status
curl -sI https://www.YOUR_DOMAIN | head -3

# Logs
docker logs --tail 100 new-api
journalctl -u caddy -n 50 --no-pager
journalctl -u turnstile-gate -n 50 --no-pager

# Restart
cd /opt/new-api && docker compose restart
systemctl reload caddy

# Backup/acceptance
bash scripts/backup.sh
bash scripts/health-check.sh
python3 scripts/probe-models.py
```