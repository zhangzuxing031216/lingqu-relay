# 自定义前端 / 验证码接入

> 本仓库只带**静态页模板**和**验证码网关**，不带完整定制前端。
> 你可以用 new-api 自带前端，也可以自己写 HTML；下面说明怎么接。

## 1. 静态页放哪

```text
/opt/new-api/static/
├─ landing.html      落地页
├─ _app.html         前端外壳（可选）
├─ docs.html         文档
├─ price.html        价格
├─ wallet.html       钱包
├─ topups.html       充值记录
├─ vendor.html       上游/渠道说明
├─ price_watch.html  比价
├─ logo.png
└─ robots.txt
```

Caddy 直接读盘：

```text
handle /price {
    rewrite * /price.html
    root * /opt/new-api/static
    file_server
}
```

改 HTML 后不需要重启容器，刷新浏览器即可。

## 2. 页面最小骨架

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Example API</title>
  <link rel="stylesheet" href="/brand/style.css">
</head>
<body>
  <header>
    <a href="/">首页</a>
    <a href="/price">价格</a>
    <a href="/docs">文档</a>
    <a href="/wallet">钱包</a>
  </header>

  <main id="app"></main>

  <script src="/brand/app.js"></script>
</body>
</html>
```

> 不要把 API key、支付密钥、管理员路径写进静态 JS。

## 3. 验证码流程

```text
1. 页面加载 → GET /lq/captcha
2. 拿到 { token, q }
3. 显示 q，让用户填答案
4. 提交注册前，把 token|答案 写入 cookie: lq_cap
5. 浏览器 POST /api/user/register
6. Caddy → gate 校验 → 转发 new-api
```

### 3.1 最小 JS

```js
const cap = { token: "", answer: "" };

async function refreshCaptcha() {
  const res = await fetch("/lq/captcha", { cache: "no-store" });
  const json = await res.json();
  if (!json.success) throw new Error(json.message || "验证码加载失败");
  cap.token = json.data.token;
  cap.answer = "";
  document.querySelector("#cap-q").textContent = json.data.q;
  document.querySelector("#cap-a").value = "";
}

function writeCaptchaCookie() {
  // 网关读 lq_cap=<token>|<答案>
  const value = `${cap.token}|${cap.answer}`;
  document.cookie = `lq_cap=${encodeURIComponent(value)}; path=/; max-age=600; SameSite=Lax`;
}

document.querySelector("#cap-refresh").addEventListener("click", refreshCaptcha);
document.querySelector("#cap-a").addEventListener("input", (e) => {
  cap.answer = e.target.value.trim();
});

// 在注册表单提交前写入 cookie
document.querySelector("#register-form").addEventListener("submit", () => {
  writeCaptchaCookie();
}, true);

refreshCaptcha();
```

HTML：

```html
<form id="register-form" method="post" action="/api/user/register">
  <input name="username" autocomplete="username" required>
  <input name="password" type="password" autocomplete="new-password" required>

  <label>
    人机验证：<span id="cap-q">加载中…</span>
    <input id="cap-a" inputmode="numeric" required>
  </label>
  <button type="button" id="cap-refresh">换一题</button>

  <button type="submit">注册</button>
</form>
```

### 3.2 如果用的是 new-api 自带注册页

自带页面不会自动显示你的验证码。两种做法：

**A. 关闭公开注册（推荐给不会改前端的用户）**

- 后台关闭注册。
- 用邀请码/手动开号。
- 不需要验证码网关。

**B. 用 MutationObserver 注入**

在自定义 JS 里找到注册表单，插入验证码控件：

```js
function installCaptcha(form) {
  if (form.dataset.captchaInstalled) return;
  form.dataset.captchaInstalled = "1";

  const box = document.createElement("div");
  box.innerHTML = `
    <label>人机验证：<span class="cap-q">加载中…</span>
      <input class="cap-a" inputmode="numeric" required>
    </label>
    <button type="button" class="cap-refresh">换一题</button>
  `;
  form.prepend(box);

  let token = "";
  const qEl = box.querySelector(".cap-q");
  const aEl = box.querySelector(".cap-a");

  async function refresh() {
    const json = await fetch("/lq/captcha", { cache: "no-store" }).then(r => r.json());
    token = json.data.token;
    qEl.textContent = json.data.q;
    aEl.value = "";
  }

  box.querySelector(".cap-refresh").addEventListener("click", refresh);
  form.addEventListener("submit", () => {
    const value = `${token}|${aEl.value.trim()}`;
    document.cookie = `lq_cap=${encodeURIComponent(value)}; path=/; max-age=600; SameSite=Lax`;
  }, true);

  refresh();
}

// 选择器按你的实际页面改：input[name="username"] 所在的 form
new MutationObserver(() => {
  const form = document.querySelector('form:has(input[name="username"])');
  if (form) installCaptcha(form);
}).observe(document.body, { childList: true, subtree: true });
```

> `:has()` 在新浏览器可用；不支持就改成遍历 `form` 判断 `querySelector('input[name="username"]')`。
> 选择器因 new-api 版本而异，先在 DevTools 里确认再写死。

### 3.3 用请求头而不是 cookie

如果不想用 cookie，前端在注册请求里加：

```text
X-LQ-Captcha: <token>|<答案>
```

网关优先读 cookie，读不到再读这个头。

## 4. 错误提示

网关返回：

```json
{"success":false,"message":"人机验证失败：答案不正确"}
```

前端直接把 `message` 显示出来，不要只显示“注册失败”。

常见：

| message | 处理 |
|---|---|
| 请先完成人机验证 | 没带 cookie/header |
| 答案不正确 | 重填 |
| 题目已过期 | 刷新 |
| 注册太频繁 | 等几分钟 |
| 用户名已存在 | 换名/登录 |

## 5. 价格页

建议由脚本生成 `pricing_public.json`，页面只读 JSON，不手写价格。

```js
async function loadPrice() {
  const data = await fetch("/pricing_public.json", { cache: "no-store" }).then(r => r.json());
  // 渲染表格
}
```

> 价格单位、倍率、货币符号要和后台一致。不要前端写死“1 元 = 1 美元”。

## 6. 安全

- 静态页不放 key。
- 不在前端做“支付成功”判断。
- 不在前端暴露管理员接口。
- 用户输入要转义，防止 XSS。
- 外部链接加 `rel="noopener noreferrer"`。
- 自定义 JS 尽量同源，少引第三方 CDN。

## 7. 测试

```text
[ ] /lq/captcha 返回 token/q
[ ] 页面能显示题目
[ ] 答案错 → 400 + 中文提示
[ ] 答案对 → 注册成功
[ ] 刷新后旧 token 仍可用到过期
[ ] 过期 token → 提示过期
[ ] 同 IP 高频 → 限流
[ ] 登录不经过验证码
[ ] 手机端布局正常
```