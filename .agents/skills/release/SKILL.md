---
name: release
description: Prepare and publish Cliptate macOS version releases, verify installers and updates, and maintain the website changelog. Use for Cliptate release preparation, publication, or release verification; App Store submission is a separate workflow.
---

# Cliptate release

完成请求所涵盖的发布阶段，并明确区分“已准备”“已打包”“已发布”和“官网已上线”。以仓库当前文档和脚本为准；本技能记录衔接步骤，不维护第二套打包流程。

## 定位与范围

- 应用仓库为 `cliptate/cliptate`，官网仓库为 `cliptate/cliptate.github.io`。优先使用当前应用 checkout 和相邻的 `../cliptate.github.io` checkout；路径不匹配时按已知工作区定位，先核对两者的 Git remote、分支和工作区状态。下文应用文件路径均相对应用根目录。
- 从用户请求和会话确定版本、目标提交及阶段。版本未确定且存在多个合理选择时再询问。准备请求只完成准备；完整发布请求继续到发布验证和官网收尾。沿用已有提交、推送和发布授权；缺少外部变更授权时，先完成可审阅的准备，再针对尚未授权的动作确认。
- 在应用仓库读 `AGENTS.md`、`CONTRIBUTING.md`、`docs/development.md`、`docs/release-notes/README.md` 与 `docs/updates.md`。涉及本地签名打包或发布时再读 [本地发布](references/local-publication.md)。官网操作前读 [官网收尾](references/website.md)。

## 1. 准备版本与说明

1. 核对目标源码与上一个正式版本的差异。使用实际历史和发布状态确定前一版本，排除滚动 `nightly`；不要依赖标签的字典排序。保留工作区中不属于发布任务的改动，避免将未完成或他人的修改带入发布提交。
2. 检查 `config/app.json` 中的版本设置，将 `MARKETING_VERSION` 与目标标签去掉 `v` 后的版本对齐。按当前发布惯例推进应用的源码 `CURRENT_PROJECT_VERSION`，保留生产 bundle identity。分发渠道仍为免费的直接下载版，使用 `CLIPTATE_APP_STORE=NO`。
3. CI 和本地打包会覆盖安装包的内部 build number，具体规则见 `docs/updates.md`、`docs/local-actions.md`；源码 build number 不代表最终发布包的 build number。保持包版本递增，尤其核对当前 Latest 和 Nightly 的内部版本，防止旧包或旧 CI run 覆盖更新结果。
4. 按 `docs/release-notes/README.md` 写 `docs/release-notes/<tag>.md`。首行、五个摘要章节、日期（Asia/Shanghai）、前一版本、升级动作、限制和实际验证记录都要完整。提交清单保留真实标题与哈希，并提供版本比较链接；含特殊字符的标签按指南编码文件名。更新该目录 README 的版本索引。
5. 功能说明来自这一版本的源码范围。需要时同步应用使用指南、CLI 文档和各语言 README。验证章节只记录已经执行的检查；签名、公证与安装验证在取得结果前保持待验证表述。

GitHub Release 的更新内容只链接官网对应版本详情，保留自动生成的安装、签名、源码与构建信息。完整仓库版本文档继续用于验证与 Sparkle 的应用内更新说明。提前准备官网翻译，发布收尾时部署并验证详情链接；GitHub 的链接说明不能替代仓库文档。

完成条件：版本设置与标签匹配；发布说明覆盖这一版本的用户可见变化、兼容性和限制；没有尚待填充的内容。

## 2. 验证并提交准备结果

使用当前目标源码的验证证据；源码或配置变化使旧结果失效时重新运行相关检查。常规版本准备需要以下检查（在应用 checkout，选择已安装的完整 Xcode）：

```bash
swift build
swift test
CONFIGURATION=Release CLIPTATE_APP_STORE=NO ./scripts/build-and-run.sh build
python3 scripts/release-notes.py "$RELEASE_TAG" --check
python3 -m unittest discover -s Tests/Automation -v
python3 scripts/update-dependency-notices.py --check
git diff --check
```

`RELEASE_TAG` 使用已确定的目标标签。变更分发能力或 `APP_STORE` 逻辑时补充另一渠道的检查；模型和交互验证按变更涉及的行为执行，并如实记录未完成项。检查依赖锁文件没有被构建意外改写。普通本地 Release 构建可能使用 ad-hoc 签名，它只提供构建证据。

按 Conventional Commits 提交版本设置和说明，例如 `chore(release): prepare vX.Y`。**发布说明必须在目标提交中，先提交，再创建版本标签。** 提交之前核对暂存范围。版本已存在时转入检查或已获授权的同标签重跑，保留标签原指向。

完成条件：目标提交固定，说明已提交，必要检查有可核对的结果。

## 3. 发布正式版

默认使用现有云端流水线：将准备提交推送到约定分支，创建指向该提交的目标版本标签并推送这个标签。标签推送会触发 `.github/workflows/package.yml`；普通分支 push 不会打包，手动 branch workflow 运行的是 main 的 Nightly，不能替代版本发布。发布前检查本地和远端版本标签状态；已存在的版本标签保持不动。

检查目标提交的 **Test** 结果，以及所选执行方式的打包结果。打包流水线负责 Developer ID 签名、与旧正式版的权限身份比较、DMG 公证和 stapling、重新生成校验和、对最终 DMG 生成签名 appcast，以及发布 GitHub Release。通过现有脚本完成这些动作。

用户指定本地发布或需要复现打包时，执行 [本地发布](references/local-publication.md) 的分支；云端和本地发布流程只选一个作为当前发布执行者。

失败时先检查出错阶段、对应源码和日志。源码不变的临时故障可有限重跑同一 run；相同失败复现后停止盲目重试，报告具体阻碍。需要改源码时，修复并验证，按新版本流程发布；历史标签不会随 main 的修复变化。部分上传后先查看远端资产、源码和 Latest 状态再恢复，避免另起并发发布。

完成条件：目标提交的必要检查通过，所选路径的打包与发布成功，GitHub 正式 Release 已发布。云端路径使用成功的 Package run 为证据；本地路径使用本次 `make release` 的结果和产物为证据，不要求另一条云端 Package run 也成功。

## 4. 验证分发与官网收尾

- GitHub Release 的标签和源码提交对应目标版本，更新说明链接到 `https://cliptate.github.io/changelog/<URL-encoded-tag>/`，状态为非 draft、非 prerelease，并成为 Latest。按请求更新已有 Release 时检查其标签内脚本；旧标签的重跑仍采用当时的正文格式，不会自动使用 main 上的新逻辑。
- 核对 `Cliptate.dmg`、`Cliptate.dmg.sha256`、`appcast.xml` 可公开获取。下载到 checkout 外的临时目录，验证最终 DMG 校验和；运行 `scripts/validate-appcast.py` 检查 feed 的目标版本下载 URL 和文件长度，并核对 display/build version。最终安装包的签名、公证与 Gatekeeper 状态以流水线和产物检查结果为证据。
- 核对 Latest 的稳定更新 feed 指向本次发布。结构校验不等同于 Sparkle 的端到端安装验证；涉及更新、权限、数据迁移或 CLI 生命周期的改动时，按 `docs/updates.md` 在测试账号执行旧正式版 → 新版的安装/重启检查，确认配置、历史、CLI 和权限保留情况。说明仍待人工验证的项目。
- 正式 Release 成功后执行 [官网收尾](references/website.md)。可提前准备翻译，但正式发布前不把它当作已发布版本上线。

最终报告给出版本/提交、Release 与工作流链接、资产和更新检查结果、官网地址及部署状态、任何未完成的验证。对仅准备或仅打包的请求，报告所完成阶段和后续工作，保持请求边界。
