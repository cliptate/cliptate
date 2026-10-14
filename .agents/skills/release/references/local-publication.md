# 本地签名打包与发布

仅在用户指定本地执行、排查流水线，或需要本地生成签名产物时读取。先在应用仓库读 `docs/local-actions.md` 与 `Makefile`，以当前入口为准。

## 选择入口

| 目的 | 现有入口 | 结果 |
| --- | --- | --- |
| 查看打包步骤 | `make actions-plan` | 列举步骤，不执行 workflow |
| 开发用 DMG | `make dmg` | ad-hoc 直接版，不能作为已公证正式包 |
| 签名打包 | `make package TAG=<tag>` | 运行签名、公证和 feed 生成，保留 dist，不发布 GitHub |
| 签名打包并发布 | `make release TAG=<tag>` | 使用同一 package workflow 打包并发布 GitHub |

在 `package` / `release` 中明确传入正式标签；省略 TAG 默认是 Nightly。`make package` 使用当前 checkout，TAG 选择渠道和说明而不替你切到标签源码；正式版本先核对 HEAD 对应目标标签。`make release` 要求包含未跟踪文件在内的干净工作区，版本标签在本地和远端都指向 HEAD。Nightly 发布则要求 HEAD 与远端 main 一致。它不会创建或移动正式标签。

## 凭据与构建身份

Apple Silicon、完整 Xcode、act 与 gh 是本地 Actions 的前提。入口使用 host runner，无需另建 Docker 打包流程。`make actions-plan` 使用 act 的 listing；host 模式的 `act --dryrun` 仍可能执行 shell 步骤，不能用来证明没有副作用。

使用指南指定的 checkout 外的私有 `act.secrets` / `act.vars` 文件及已有 GitHub 认证。核对认证状态、文件存在和权限即可；配置缺失时说明所需名称和安全输入位置，不输出密钥内容。签名和 Sparkle 配置按 `docs/development.md` 与 `docs/updates.md` 设置；生产应用身份和信任链保持兼容。

入口自动计算本地内部 build number；只有明确需要覆盖时使用 `BUILD_VERSION`，核对它比当前分发包更新且与后续云端编号兼容。人工输入源码 build number不能替代这一检查。

## 与云端协调

正式标签必须先推送，而标签 push 已触发云端打包。先等待云端 run 结束；用户明确指定本地发布时，随后执行单次 `make release`，保留相同标签和源码，以本次产物串行替换资产。不要用云端成功结果代替用户要求的本地执行。用户没有指定本地发布且云端已经成功时，直接使用云端结果即可。act 不执行 GitHub workflow concurrency，checkout 内的锁也不会保护另一个 checkout 或云端 run。

本地发布前和打包后都会校验源码未变。检查失败时保存产物和诊断，修正原因后再决定是否重跑；不要绕过源码核对或直接上传旧 dist。发布流程会使用本次生成的 DMG、校验和与 appcast，记录 local build，不能引用虚构的 GitHub Actions run。

完成后回到主流程的资产、更新与官网检查。`make package` 完成时只能报告“已打包”，不能报告“已发布”。
