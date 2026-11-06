# 工作记录 / Worklog

> 最新在上。每次公开发布、大整理或重要决策后追加一条。
> 目的：下一次打开 `E:\008githup` 时，先看这里，30 秒知道上次做到哪、下一步是什么。
> 本记录同时保存在四个仓库根目录的 `WORKLOG.md`；它提交在 `v0.1.0` tag 之后，不单独发版。

---

## 2026-11-06 · 首次公开发布 `v0.1.0`

### 一句话

把 `E:\008githup` 下四个项目整理成中英双语、可公开搜索的 GitHub 仓库，统一发布 `v0.1.0`，并建立版本号、更新记录、版本对比和旧版本取回流程。

### 结果

| 项目 | GitHub 仓库 | 版本 | Release |
|---|---|---|---|
| ComfyUI 低显存部署 / ComfyUI Low-VRAM | https://github.com/zhangzuxing031216/comfyui-low-vram | `0.1.0` | https://github.com/zhangzuxing031216/comfyui-low-vram/releases/tag/v0.1.0 |
| 灵渠 AI 中转站 / Lingqu AI Relay | https://github.com/zhangzuxing031216/lingqu-relay | `0.1.0` | https://github.com/zhangzuxing031216/lingqu-relay/releases/tag/v0.1.0 |
| AI 议会 / AI Council | https://github.com/zhangzuxing031216/ai-council | `0.1.0` | https://github.com/zhangzuxing031216/ai-council/releases/tag/v0.1.0 |
| 个人数据库 / Personal Knowledge Base | https://github.com/zhangzuxing031216/personal-db | `0.1.0` | https://github.com/zhangzuxing031216/personal-db/releases/tag/v0.1.0 |

四个仓库均为 **Public**，默认分支 `main`，已设置 About、Topics、`v0.1.0` tag 和 GitHub Release。

### 本次做了什么

1. **四个项目定名**
   - `comfyui-low-vram`：ComfyUI 低显存部署 / ComfyUI Low-VRAM Deployment
   - `lingqu-relay`：灵渠 AI 中转站 / Lingqu AI Relay
   - `ai-council`：AI 议会 / AI Council
   - `personal-db`：个人数据库 / Personal Knowledge Base
2. **每个项目都有完整中文和英文**
   - `README.md` + `README.en.md`
   - `AI-DEPLOY.md` + `AI-DEPLOY.en.md`，或 `AI-INSTALL.md` + `AI-INSTALL.en.md`
   - README 顶部有 `中文 | English` 切换，英文不是摘要。
3. **README 首屏按新手顺序重排**
   - 中英双语 H1、名称行、版本行
   - 徽章、三行简介、适合谁 / 不适合谁、你会得到什么、新手 3 步
   - 真实截图优先，示意图补充
4. **建立版本体系**
   - 每个仓库根部：`VERSION`、`CHANGELOG.md`、`VERSIONING.md`
   - 当前版本统一 `0.1.0`，Git tag 统一 `v0.1.0`
   - README 首屏有版本行和版本徽章
   - `CHANGELOG.md` 记录 `v0.1.0` 新增内容
   - `VERSIONING.md` 写清楚发版、对比、取回旧版本的命令
5. **补真实截图**
   - ComfyUI：RTX 3060 6GB、`--lowvram`、768×768、20 步真实出图 + 真实界面截图
   - 灵渠中转站：new-api `v1.0.0-rc.48` 真实初始化页 + 后台截图
   - 个人数据库：Obsidian 1.15.0 示例 vault 真实截图（之后已恢复本机 Obsidian 配置）
   - AI 议会：没有固定 UI，保留合成示意图，不伪造真实截图
6. **GitHub CLI 安装与登录**
   - 安装位置：`C:\Program Files\GitHub CLI\gh.exe`
   - 版本：`2.103.3`
   - 登录账号：`zhangzuxing031216`
   - Token 类型：`gho_`，scopes：`gist`、`read:org`、`repo`
   - Token 存系统 keyring，没有写入任何项目文件或笔记
7. **创建仓库并推送**
   - 四个仓库全部 `Public`
   - `git push -u origin main`
   - `git push origin v0.1.0`
   - `gh repo edit` 设置中英双语 About + Topics
   - `gh release create v0.1.0` 发布首个 Release
8. **验证**
   - 本地 `HEAD` = `origin/main` = `v0.1.0` 指向的提交
   - 四个仓库 `git status` 干净
   - GitHub 大小写敏感链接检查：四个仓库全部 0 个断链
   - 根目录文档链接检查：0 个断链
   - GitHub About 描述与 `REPO-METADATA.md` 完全一致
   - Release 说明已去掉 BOM

### 关键决策

- 仓库名/URL 保持英文 slug；README 标题、首屏名称行、GitHub About 同时写中英文。
- `0.x` 是公开预览版，第一个版本统一 `v0.1.0`；不为了“看起来正式”直接发 `v1.0.0`。
- 已发布的 tag 不移动、不覆盖。发错就修完发新的 `PATCH`。
- 英文 README 和 AI 协议是完整翻译；`docs/` 深层专题暂时保留中文，英文 README 已注明。
- AI 议会没有固定 UI，报告图是合成示意；不冒充真实运行截图。
- `personal-db` 当前是通用骨架，`vault-template/AGENTS.md` 等用户最新规则。

### 踩过的坑

1. **GitHub App token 不能建仓库**
   - 第一次设备授权拿到 `ghu_` token，`X-OAuth-Scopes` 为空，`CreateRepository` 返回 403。
   - 改用 GitHub CLI 自己的 OAuth 登录，拿到 `gho_` token，scopes 含 `repo`，才能建仓库。
2. **本机直连 `github.com` 的 443 不稳定**
   - `api.github.com` 正常，`github.com` TLS 经常超时/重置。
   - 授权阶段临时用本地 CONNECT 代理，把 `github.com` 指到可访问的 `20.27.177.113`；授权完成即删除，没有改 hosts。
3. **PowerShell 5.1 写中文参数会乱码**
   - 第一次 `gh repo edit --description` 把中文写成了乱码。
   - 改用 UTF-8 JSON 文件 + `gh api --input` 修复。
4. **Release 说明带 BOM**
   - `Set-Content -Encoding UTF8` 在 PowerShell 5.1 会写 BOM。
   - 改用 Python 写无 BOM UTF-8，再 `gh release edit --notes-file`。
5. **`$ErrorActionPreference = "Stop"` + 原生命令 stderr**
   - `gh repo view` 查询不存在的仓库本来就会返回非零，脚本被误判为致命错误。
   - 改成 `Continue` + 显式检查 `$LASTEXITCODE`。

### 下次快速接手

```bash
cd E:\008githup

# 1. 先看索引和本记录
#    README.md
#    WORKLOG.md
#    REPO-METADATA.md
#    VERSIONING.md

# 2. 确认 GitHub 登录
gh auth status

# 3. 看四个仓库状态
git -C comfyui-low-vram status --short
git -C lingqu-relay status --short
git -C ai-council status --short
git -C personal-db status --short

# 4. 看远程有没有新提交
git -C <repo> fetch --tags origin
git -C <repo> log --oneline v0.1.0..origin/main
git -C <repo> diff --stat v0.1.0..origin/main
```

版本对比：

```bash
git -C <repo> fetch --tags origin
git -C <repo> log --oneline v0.1.0..origin/main
git -C <repo> diff --stat v0.1.0..origin/main
git -C <repo> diff v0.1.0..origin/main
```

取回旧版本：

```bash
git -C <repo> switch --detach v0.1.0
git -C <repo> switch -c snapshot/v0.1.0 v0.1.0
git -C <repo> archive --format=zip --output=<repo>-v0.1.0.zip v0.1.0
```

发下一个版本：

```bash
# 改 VERSION、CHANGELOG.md、README 版本行/徽章
git -C <repo> add -A
git -C <repo> commit -m "release: v0.1.1"
git -C <repo> tag -a v0.1.1 -m "v0.1.1"
git -C <repo> push origin main
git -C <repo> push origin v0.1.1
gh release create v0.1.1 --repo zhangzuxing031216/<repo> --title "v0.1.1" --notes-file <notes.md>
```

### 未完成 / 下一步

- [ ] `personal-db`：等用户给最新个人数据库规则，替换 `vault-template/AGENTS.md` 与 `docs/rules.md` 对应章节，发 `v0.1.1`。
- [ ] 在 GitHub 网页逐项目目检 README 图片、双语切换和 Release 说明（API 检查已通过）。
- [ ] ComfyUI：补下载页/解压/控制台截图，补 macOS / Linux、AMD / Intel、SD3.5 / Flux。
- [ ] 灵渠中转站：补 new-api 版本固定/digest、MySQL/多机、Cloudflare/CDN、完整前端模板。
- [ ] AI 议会：补真实多模型运行截图、更多席位模板、只讨论不执行命令、成本估算脚本。
- [ ] 个人数据库：补 `new-note.py`、Dataview 查询示例、附件管理规范、英文深层专题。

### 文件地图

| 位置 | 内容 |
|---|---|
| `README.md` | 四个项目总索引、GitHub 链接、版本表、效果预览、当前状态 |
| `WORKLOG.md` | 本文件，工作记录 |
| `REPO-METADATA.md` | 四个仓库的 About / Topics / 首屏检查清单 |
| `VERSIONING.md` | 四个仓库统一的发版、对比、取回规则 |
| `comfyui-low-vram/` | ComfyUI 低显存部署项目 |
| `lingqu-relay/` | 灵渠 AI 中转站项目 |
| `ai-council/` | AI 议会项目 |
| `personal-db/` | 个人数据库项目 |