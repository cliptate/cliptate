# 官网 changelog 与发布收尾

更新或发布官网时读取。官网是独立仓库 `cliptate/cliptate.github.io`；确认 remote 和工作区后，读它的 README 内容维护章节、`src/data/changelog.ts`、`src/data/release-metadata.json`、`astro.config.mjs` 和 `scripts/check-seo.py`。

## 内容

以应用仓库 `docs/release-notes/<tag>.md` 的完整内容和已发布 Release 的版本/源码信息为依据，添加该版本的本地化摘要、功能与修复、升级说明和已知限制。GitHub 正文只有官网详情链接，不能作为功能内容来源。保留原始 Release 和完整英文验证/提交记录的链接。覆盖 `zh`、`en`、`ja`、`ko`、`de` 的正文与独立搜索标题；旧版本的功能说明仍来自各自版本，Nightly 与未发布 main 功能不进入正式版列表。

`src/data/release-metadata.json` 的每个版本记录：

| 字段 | 含义 |
| --- | --- |
| `tag` | 与已发布 GitHub Release 一致的版本标签 |
| `date` | 版本说明中的版本日期 |
| `published` | 官网条目首次上线日期；以后编辑时保留 |
| `updated` | 内容实质变化的日期，作为 sitemap lastmod |

在 `src/data/changelog.ts` 的 content 中添加同一 tag 的全部字段。当前路由、倒序列表、语言切换、版本导航和 schema 由数据生成；保持现有模式，常规新增版本无需复制页面模板。日期按 Asia/Shanghai 判断；首次上线和版本发布日可以不同。

## 校验与上线

在官网 checkout，使用 `package.json` 要求的 Node 和已有依赖运行：

```bash
npm run check
npm run build
npm run check:seo
git diff --check
```

检查新增版本在五种语言中的 `/changelog/<tag>/` 路由，独立 title/description、自引用 canonical、双向 hreflang、正文、面包屑、Article/ItemList 和 sitemap lastmod；确认主页、列表与版本导航链接可达。渲染验证覆盖桌面与手机，并确认不依赖浏览器实时抓取 GitHub 的正文能在无 JavaScript 时阅读。README 的固定版本范围或功能描述变旧时同步五种语言文档。

正式 Release 成功后，在请求授权范围内以 Conventional Commit 提交官网内容并推送到约定分支。当前 main push 触发 `.github/workflows/deploy.yml`，它是另一条独立流水线；应用发布不会自动同步或部署 changelog。

检查 Pages 部署完成，再验证 `https://cliptate.github.io/changelog/` 和对应语言详情，以及线上 sitemap 和元信息。检查 GitHub Release 正文中的官网链接返回成功并展示该版本；链接尚不可访问时继续完成官网部署和验证，不能宣布完整发布收尾已完成。部署尚在进行时保留“已推送，部署待完成”的状态；部署成功且新版本可见才报告“官网已上线”。已有 sitemap 地址不变，普通新增版本无需重复创建 Search Console 或重新配置 robots。
