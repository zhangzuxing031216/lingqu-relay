#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
探测 new-api 的模型列表和最小对话。

用法：
  NEWAPI_BASE=http://127.0.0.1:3000 NEWAPI_KEY=sk-xxx python3 scripts/probe-models.py
  NEWAPI_BASE=http://127.0.0.1:3000 NEWAPI_KEY=sk-xxx python3 scripts/probe-models.py --chat gpt-4o-mini

只依赖标准库。不会打印完整 key。
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


def api_url(base: str, path: str) -> str:
    base = base.rstrip("/")
    if base.endswith("/v1"):
        return base + path
    return base + "/v1" + path


def request(url: str, key: str, payload=None, timeout=30):
    data = None
    headers = {
        "Authorization": "Bearer " + key,
        "Accept": "application/json",
        "User-Agent": "lingqu-probe/1.0",
    }
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        return resp.status, body


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=os.environ.get("NEWAPI_BASE", "http://127.0.0.1:3000"))
    parser.add_argument("--key", default=os.environ.get("NEWAPI_KEY", ""))
    parser.add_argument("--chat", metavar="MODEL", help="额外发一条最小对话测试")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    if not args.key:
        print("ERROR: 没有 key。设置 NEWAPI_KEY 或传 --key。", file=sys.stderr)
        return 2

    masked = args.key[:4] + "..." + args.key[-4:] if len(args.key) > 8 else "***"
    print(f"base: {args.base}")
    print(f"key : {masked}")

    # 1. 模型列表
    url = api_url(args.base, "/models")
    t0 = time.time()
    try:
        status, body = request(url, args.key, timeout=args.timeout)
    except urllib.error.HTTPError as e:
        print(f"GET {url} -> HTTP {e.code}")
        print(e.read().decode("utf-8", "replace")[:500])
        return 1
    except Exception as exc:  # noqa: BLE001
        print(f"GET {url} -> ERROR {exc}")
        return 1

    elapsed = (time.time() - t0) * 1000
    print(f"GET {url} -> HTTP {status} ({elapsed:.0f} ms)")
    try:
        obj = json.loads(body)
        models = obj.get("data") or []
        print(f"模型数量：{len(models)}")
        for m in models[:20]:
            mid = m.get("id") if isinstance(m, dict) else str(m)
            print("  -", mid)
        if len(models) > 20:
            print(f"  ... 还有 {len(models) - 20} 个")
    except Exception:
        print(body.decode("utf-8", "replace")[:500])

    # 2. 可选对话
    if args.chat:
        url = api_url(args.base, "/chat/completions")
        payload = {
            "model": args.chat,
            "messages": [{"role": "user", "content": "Reply with the single word: ok"}],
            "max_tokens": 8,
            "temperature": 0,
        }
        t0 = time.time()
        try:
            status, body = request(url, args.key, payload=payload, timeout=args.timeout)
        except urllib.error.HTTPError as e:
            print(f"POST {url} -> HTTP {e.code}")
            print(e.read().decode("utf-8", "replace")[:500])
            return 1
        except Exception as exc:  # noqa: BLE001
            print(f"POST {url} -> ERROR {exc}")
            return 1
        elapsed = (time.time() - t0) * 1000
        print(f"POST {url} -> HTTP {status} ({elapsed:.0f} ms)")
        try:
            obj = json.loads(body)
            msg = obj["choices"][0]["message"]["content"]
            print("回复：", msg[:200])
        except Exception:
            print(body.decode("utf-8", "replace")[:500])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())