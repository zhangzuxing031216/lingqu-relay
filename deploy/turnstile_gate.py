#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
注册验证码网关（自建算术题，不依赖 Cloudflare Turnstile）。

工作方式：
  GET  /lq/captcha          -> {"success": true, "data": {"token": "...", "q": "3 + 4"}}
  POST /api/user/register   -> 校验 Cookie: lq_cap=<token>|<答案>
                               或请求头 X-LQ-Captcha: <token>|<答案>
                               通过后原样转发给 new-api (127.0.0.1:3000)

环境变量：
  UPSTREAM      new-api 地址，默认 http://127.0.0.1:3000
  BIND          监听地址，默认 127.0.0.1
  PORT          监听端口，默认 3100
  SECRET_FILE   签名密钥文件，默认 /root/lq_captcha.secret（首次自动生成）
  CAPTCHA_TTL   题目有效期秒数，默认 600
  RATE_MAX      每 IP 每小时注册提交上限，默认 120
  NO_CAP_QUOTA  每 IP 每小时无验证码兜底次数，默认 5（0 = 关闭兜底）

安全：
  - 只监听 127.0.0.1，由 Caddy 反代。
  - 密钥文件权限建议 600。
  - 不记录请求体、密码、token。
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("UPSTREAM", "http://127.0.0.1:3000").rstrip("/")
BIND = os.environ.get("BIND", "127.0.0.1")
PORT = int(os.environ.get("PORT", "3100"))
SECRET_FILE = os.environ.get("SECRET_FILE", "/root/lq_captcha.secret")
TTL = int(os.environ.get("CAPTCHA_TTL", "600"))
RATE_MAX = int(os.environ.get("RATE_MAX", "120"))
RATE_WINDOW = 3600
NO_CAP_QUOTA = int(os.environ.get("NO_CAP_QUOTA", "5"))

RATE = {}
NOCAP = {}


def secret() -> bytes:
    if not os.path.exists(SECRET_FILE):
        parent = os.path.dirname(SECRET_FILE)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(SECRET_FILE, "w", encoding="utf-8") as f:
            f.write(secrets.token_hex(32))
        try:
            os.chmod(SECRET_FILE, 0o600)
        except OSError:
            pass
    with open(SECRET_FILE, "r", encoding="utf-8") as f:
        return f.read().strip().encode()


def b64e(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def b64d(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def make_token(ans: int) -> str:
    payload = json.dumps(
        {"a": ans, "e": int(time.time()) + TTL, "n": secrets.token_hex(8)},
        separators=(",", ":"),
    ).encode()
    body = b64e(payload)
    sig = hmac.new(secret(), body.encode(), hashlib.sha256).hexdigest()[:32]
    return body + "." + sig


def check_token(tok: str, ans: str):
    try:
        body, sig = tok.split(".", 1)
        want = hmac.new(secret(), body.encode(), hashlib.sha256).hexdigest()[:32]
        if not hmac.compare_digest(sig, want):
            return False, "签名不正确"
        d = json.loads(b64d(body))
        if d.get("e", 0) < time.time():
            return False, "题目已过期，请刷新重试"
        if str(d.get("a")) != str(ans).strip():
            return False, "答案不正确"
        return True, ""
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def rate_ok(ip: str) -> bool:
    now = time.time()
    arr = [t for t in RATE.get(ip, []) if now - t < RATE_WINDOW]
    RATE[ip] = arr
    if len(arr) >= RATE_MAX:
        return False
    arr.append(now)
    return True


def cookie_val(header: str, name: str) -> str:
    if not header:
        return ""
    for part in header.split(";"):
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        if k.strip() == name:
            return urllib.parse.unquote(v.strip())
    return ""


def client_ip(handler) -> str:
    cf = handler.headers.get("CF-Connecting-IP")
    if cf:
        return cf.strip()
    xff = handler.headers.get("X-Forwarded-For") or ""
    if xff:
        # Caddy 会把真实客户端追加到末尾；取最后一个，避免客户端伪造开头。
        return xff.split(",")[-1].strip()
    return handler.client_address[0]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "lingqu-captcha/1.0"

    def log_message(self, fmt, *args):
        # 不打印 query/body，避免泄露
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

    def _json(self, code: int, obj: dict):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        if self.path.startswith("/healthz"):
            self._json(200, {"ok": True})
            return
        if self.path.startswith("/lq/captcha"):
            a = secrets.randbelow(8) + 2
            b = secrets.randbelow(8) + 2
            if secrets.randbelow(2):
                q, ans = f"{a} + {b}", a + b
            else:
                if a < b:
                    a, b = b, a
                q, ans = f"{a} - {b}", a - b
            self._json(200, {"success": True, "data": {"token": make_token(ans), "q": q}})
            return
        self._json(404, {"success": False, "message": "not found"})

    def do_POST(self):  # noqa: N802
        if not self.path.startswith("/api/user/register"):
            self._json(404, {"success": False, "message": "not found"})
            return

        length = int(self.headers.get("Content-Length") or 0)
        if length > 1_000_000:
            self._json(413, {"success": False, "message": "请求体过大"})
            return
        raw = self.rfile.read(length) if length else b""

        ip = client_ip(self)
        if not rate_ok(ip):
            # 用 400 而不是 429：部分前端只对 400 展示后端的中文提示。
            self._json(400, {"success": False, "message": "注册太频繁，请过几分钟再试"})
            return

        cap = (
            cookie_val(self.headers.get("Cookie"), "lq_cap")
            or self.headers.get("X-LQ-Captcha")
            or ""
        )
        if "|" in cap:
            tok, ans = cap.rsplit("|", 1)
            if ans.strip() == "":
                self._json(400, {"success": False, "message": "请先填写人机验证答案"})
                return
            ok, why = check_token(tok, ans)
            if not ok:
                self._json(400, {"success": False, "message": "人机验证失败：" + why})
                return
        else:
            # 兜底：验证码组件没挂出来时，同 IP 每小时仍允许少量注册。
            # 不想保留这个口子就把 NO_CAP_QUOTA 设为 0。
            now = time.time()
            arr = [t for t in NOCAP.get(ip, []) if now - t < RATE_WINDOW]
            NOCAP[ip] = arr
            if NO_CAP_QUOTA > 0 and len(arr) < NO_CAP_QUOTA:
                arr.append(now)
                print("no-captcha fallback allowed for", ip, flush=True)
            else:
                self._json(
                    400,
                    {
                        "success": False,
                        "message": "请先完成人机验证（未检测到验证结果，请刷新页面重试）",
                    },
                )
                return

        req = urllib.request.Request(UPSTREAM + self.path, data=raw, method="POST")
        for k, v in self.headers.items():
            if k.lower() in (
                "host",
                "content-length",
                "connection",
                "cookie",
                "x-lq-captcha",
                "accept-encoding",
            ):
                continue
            req.add_header(k, v)
        # 强制上游返回明文，避免浏览器带 gzip 时前端拿到压缩字节。
        req.add_header("Accept-Encoding", "identity")

        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read()
                try:
                    text = body.decode("utf-8")
                    if r.status == 429:
                        self._json(400, {"success": False, "message": "请求太频繁，请 1 分钟后再试"})
                        return
                    if "Username already exists" in text:
                        body = json.dumps(
                            {"success": False, "message": "用户名已存在，请直接登录，或换一个用户名"},
                            ensure_ascii=False,
                        ).encode()
                    elif "Password" in text and "at least" in text:
                        body = json.dumps(
                            {"success": False, "message": "密码长度不够，请至少 8 位"},
                            ensure_ascii=False,
                        ).encode()
                except UnicodeDecodeError:
                    pass
                self.send_response(r.status)
                self.send_header("Content-Type", r.headers.get("Content-Type", "application/json"))
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as e:
            body = e.read()
            if e.code == 429:
                self._json(400, {"success": False, "message": "请求太频繁，请 1 分钟后再试"})
                return
            try:
                text = body.decode("utf-8")
                if "Username already exists" in text:
                    self._json(400, {"success": False, "message": "用户名已存在，请直接登录，或换一个用户名"})
                    return
                if "Password" in text and "at least" in text:
                    self._json(400, {"success": False, "message": "密码长度不够，请至少 8 位"})
                    return
            except UnicodeDecodeError:
                pass
            self.send_response(e.code)
            self.send_header("Content-Type", e.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:  # noqa: BLE001
            self._json(502, {"success": False, "message": "注册服务暂时不可用：%s" % exc})


class Server(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    print(f"captcha gate listening on {BIND}:{PORT} -> {UPSTREAM}", flush=True)
    Server((BIND, PORT), Handler).serve_forever()