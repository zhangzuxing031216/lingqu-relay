# 图片说明

本目录放 **SVG 示意图 + new-api 真实截图**。示意图用来展示“有数据后”的样子，真实截图用来证明当前版本能跑。

| 文件 | 内容 |
|---|---|
| `architecture.svg` | 组件与请求路径 |
| `deploy-flow.svg` | 十步部署流程 |
| `admin-dashboard.svg` | 后台运营概览示意（请求、收入、渠道健康、日志） |
| `price-page.svg` | 对外价格页示意（套餐、模型倍率、占位价格） |
| `registration-captcha.svg` | 注册页与算术验证码网关示意 |
| `newapi-setup.png` | **真实截图**：new-api v1.0.0-rc.48 初始化向导 |
| `newapi-dashboard.png` | **真实截图**：刚初始化后的后台（无数据） |

## 为什么还要保留示意图

- 截图随 new-api/Caddy 版本变化，容易过期。
- 示意图能突出“看哪里”，不会被界面细节干扰。
- SVG 体积小、可缩放、GitHub 直接渲染。

## 如果你要补真实截图

建议命名：

| 文件名 | 内容 | 打码 |
|---|---|---|
| `shot-01-dns.png` | DNS A 记录 | 域名可保留，IP 打码 |
| `shot-02-compose.png` | `docker ps` 正常 | 无 |
| `shot-03-caddy.png` | `caddy validate` 通过 | 无 |
| `shot-04-admin.png` | 后台首页 | 用户/额度打码 |
| `shot-05-channel.png` | 渠道测试通过 | key 打码 |
| `shot-06-captcha.png` | 注册验证码 | 无 |
| `shot-07-backup.png` | 备份文件列表 | 路径可保留 |
| `shot-08-price.png` | 价格页 | 无 |

规范：

1. 分辨率 ≥1280×720，PNG，单张 <500KB。
2. 必须打码：API key、密码、支付密钥、用户邮箱/手机号、真实 IP。
3. 关键区域用红框/箭头，不要整张涂鸦。
4. 截图里的域名/路径要和文档一致，或明确写“示例”。

> 不要用 AI 生成“假截图”冒充真实后台。示意图可以，伪造截图不行。