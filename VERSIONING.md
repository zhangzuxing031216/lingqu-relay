# 版本管理 / Versioning

> **当前版本 / Current version**: `0.1.0`
> **Git tag**: `v0.1.0`
> **发布日期 / Released**: 2026-11-06
> **仓库 / Repository**: https://github.com/zhangzuxing031216/lingqu-relay

## 1. 版本号规则 / Version scheme

版本号采用 `MAJOR.MINOR.PATCH`，Git tag 统一加 `v` 前缀：

- `MAJOR`：不兼容变更。例如部署目录、环境变量、compose 服务名发生破坏性调整。
- `MINOR`：向后兼容的新功能。例如新增支付方式、新增监控、新增前端模板。
- `PATCH`：向后兼容的修正。例如失效链接、脚本 bug、配置字段更新、截图更新。

`0.x` 表示公开预览版：主流程可用，但配置和目录仍可能小幅调整。第一个公开版本是 `v0.1.0`。

**已发布的 tag 不移动、不覆盖。** 发布后发现错误，修完发新的 `PATCH` 版本。

## 2. 当前版本 / Current release

| 项目 | 值 |
|---|---|
| 版本 | `0.1.0` |
| Tag | `v0.1.0` |
| 日期 | 2026-11-06 |
| 类型 | 首次公开 |
| 摘要 | Docker + new-api + Caddy + SQLite 的 OpenAI 兼容中转站脱敏模板，中英双语文档，含真实 new-api 截图 |

## 3. 发布新版本 / Release a new version

以 `v0.2.0` 为例：

```bash
# 1. 改版本号和更新记录
#    VERSION: 0.1.0 -> 0.2.0
#    CHANGELOG.md: 增加 v0.2.0 段落

# 2. 提交
git add VERSION CHANGELOG.md
git commit -m "release: v0.2.0"

# 3. 打附注 tag
git tag -a v0.2.0 -m "v0.2.0"

# 4. 推送提交和 tag
git push origin main
git push origin v0.2.0
```

发布后到 GitHub 的 **Releases → Draft a new release**，选择 `v0.2.0`，说明直接复制 `CHANGELOG.md` 里的对应段落。

## 4. 查看版本差距 / Compare versions

```bash
# 先取回远程 tag 和提交
git fetch --tags origin

# 当前版本
git describe --tags --always

# v0.1.0 之后有哪些提交
git log --oneline v0.1.0..origin/main

# 哪些文件变了、改了多少
git diff --stat v0.1.0..origin/main

# 看具体改动
git diff v0.1.0..origin/main

# 两个正式版本之间比较
git diff v0.1.0..v0.2.0 --stat
```

GitHub 网页对比：

```text
https://github.com/zhangzuxing031216/lingqu-relay/compare/v0.1.0...main
```

## 5. 取回旧版本 / Retrieve an old version

```bash
# 只查看，不改当前分支
git switch --detach v0.1.0

# 基于旧版本开一个分支
git switch -c snapshot/v0.1.0 v0.1.0

# 导出 zip
git archive --format=zip --output=lingqu-relay-v0.1.0.zip v0.1.0
```

看完后回到主线：

```bash
git switch main
```

## 6. 发布检查 / Release checklist

- [ ] `VERSION` 与 `CHANGELOG.md` 一致。
- [ ] `git status` 干净。
- [ ] 敏感信息扫描通过（域名、IP、key、支付账号全部是占位符）。
- [ ] 图片和文档链接断链为 0。
- [ ] tag 打在发布提交上。
- [ ] `git push origin main` 和 `git push origin vX.Y.Z` 都成功。
- [ ] GitHub Release 说明与 CHANGELOG 一致。