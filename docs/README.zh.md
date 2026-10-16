<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate 图标" />
  <h1>Cliptate</h1>
  <p><strong>面向 Mac 音视频创作者的端侧 AI 工作台</strong></p>

  <p>
    <a href="https://github.com/cliptate/cliptate/releases"><img alt="从 GitHub Releases 下载" src="https://img.shields.io/badge/GitHub%20Releases-下载-0066cc?logo=github&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="本地语音推理" src="https://img.shields.io/badge/处理方式-本地语音-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">官网</a> ·
    <a href="https://github.com/cliptate/skills">Skills</a> ·
    <a href="https://cliptate.github.io#features">功能介绍</a> ·
    <a href="https://cliptate.github.io#voice">语音与 TTS</a> ·
    <a href="https://github.com/cliptate/cliptate/releases">立即下载</a>
  </p>

  <p>
    <a href="../README.md">English</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ko.md">한국어</a> ·
    <a href="README.de.md">Deutsch</a>
  </p>
</div>

---

Cliptate 是一款原生 macOS 应用，可将语音转为可编辑文本、字幕和粗剪时间线。在 Apple Silicon Mac 上运行模型，完成录音转写、跨应用听写、停顿裁剪和语音合成。

**GitHub 下载版完全免费**：所有模型与 Pro 功能均已解锁，无需订阅或购买。可选在线 AI 功能使用你自行配置的服务。

![Cliptate 简体中文首页，显示听写统计和使用记录](../assets/screenshots/home.zh-Hans.jpg)

*首页展示累计听写统计、最近 12 个月的使用记录和记录来源。*

通过左侧栏打开**文件转录**、**语音听写**或**语音生成**；**设置**始终位于侧栏底部。

界面支持英语、简体中文、日语、韩语和德语，可在**设置 → 语言**中切换显示语言。

[快速开始](#快速开始) · [功能](#功能) · [命令行](#命令行) · [隐私与模型](#隐私与模型) · [源码构建](#从源码构建)

## 快速开始

### 下载与安装

1. 从 [GitHub Releases](https://github.com/cliptate/cliptate/releases/latest) 下载 `Cliptate.dmg`。如需每日构建，可选择 [Nightly 预发布版](https://github.com/cliptate/cliptate/releases/tag/nightly)。
2. 打开 DMG，将 **Cliptate.app** 拖入**应用程序**文件夹，再启动应用。
3. 打开**模型**页面，在首次转写或语音合成前下载所需模型。

发布包使用 Developer ID 签名并经 Apple 公证，同时提供 SHA-256 校验文件。参见[安装与校验说明](development.md#dmg-packages-and-ci-downloads)。直接下载版支持[应用内更新](updates.md)。

### 系统要求

| 要求 | 说明 |
| --- | --- |
| Mac | Apple Silicon（M1 及以上） |
| 系统 | macOS 15 Sequoia 或更高版本 |
| 存储与内存 | 取决于所选模型，可在模型页面查看大小 |
| 网络 | 首次下载模型和使用可选在线服务时需要 |

### 第一次使用

- **已有音视频**：打开 **AI Cut**，导入文件，选择转写模型和语言，转写后检查文本与停顿裁剪，再导出。
- **实时听写**：打开**语音转文字（Voice To Text）**，选择模型、设置快捷键并允许麦克风访问。直接下载版通过辅助功能权限向其他应用输入文本，也可通过剪贴板粘贴。
- **语音合成**：选择 TTS 模型，输入文本，再选择该模型支持的预设音色、参考音频或音色描述。

## 功能

| 工作流 | 能做什么 |
| --- | --- |
| **离线转写** | 使用 Parakeet、Qwen3 ASR、FireRed 或 Cohere 模型批量转写音视频，根据语言和硬件选择引擎。 |
| **语音听写** | 流式语音转文字，支持自定义词典和可配置的听写快捷键。 |
| **AI Cut** | 通过语音活动检测（VAD）识别停顿，检查片段并导出粗剪结果。 |
| **说话人标注** | 在支持的转写流程中使用 Sortformer 区分说话人；Silero VAD 只检测语音，不识别说话人。 |
| **语音合成** | Qwen3 TTS 支持预设音色、声音克隆、情感与风格提示、音色设计；可用控制项取决于模型。 |
| **纠错与翻译** | 可选在线 AI 服务用于文本纠错与关键词强调；Apple 翻译用于受支持语言对的字幕翻译。 |
| **命令行** | 从脚本或 AI 代理中转写文件、生成 WAV 语音、管理自定义词典。 |

## 导出

| 输出 | 格式与用途 |
| --- | --- |
| 剪辑时间线 | **FCPXML**，用于 Final Cut Pro |
| 字幕与逐字稿 | 应用支持 **SRT**、带样式的 **ASS**、带时间戳的 **TXT** |
| 视频 | **MP4**、**MOV**、**M4V**，可烧录字幕 |
| 音频 | **M4A**、**WAV** |
| CLI 转写 | **Text**、**JSON**、**Markdown**、**SRT**、**VTT** |

字幕和渲染后的媒体可用于 DaVinci Resolve、Adobe Premiere Pro 等工具，具体取决于编辑器的格式支持。FCPXML 对应 Final Cut Pro 时间线工作流。

## 命令行

直接下载版内置 CLI。先将应用移至应用程序文件夹，再打开**设置 → 命令行**，将复制的安装命令粘贴到终端运行。按照 [CLI 指南](cli.md)将 `~/.local/bin` 加入 shell 的 `PATH`。

```bash
cliptate transcribe interview.mp4 --format srt --output interview.srt
cliptate transcribe recording.wav --format json --download
cliptate tts --text "你好，欢迎使用 Cliptate。" --output speech.wav --download
cliptate dictionary add "Cliptate" "MLX"
```

CLI 使用应用当前选择的模型和配置，必要时在后台启动应用。`--download` 允许下载缺失模型。CLI 转写接受本地文件，不创建项目或历史记录。使用 `cliptate --help` 或阅读[完整命令参考](cli.md)，了解批量输出、模型覆盖和脚本调用方式。

## 隐私与模型

- **本地语音处理**：转写、VAD、说话人识别与 TTS 推理均在 Mac 上运行，下载后的语音模型可离线使用。
- **可选在线 AI**：纠错与关键词提取会将文本发送到你配置的服务。离线处理语音时请关闭这些功能。
- **翻译**：Apple 翻译可能需要下载语言资源，可用性取决于语言对。
- **模型存储**：权重单独下载。直接下载版可复用 `~/.cache/huggingface/hub` 下的 Hugging Face 缓存，详见[缓存说明](development.md#shared-model-cache)。
- **许可证**：应用代码采用 [MIT 许可证](../LICENSE)。模型权重和依赖遵循各自许可证，详见[第三方许可](../THIRD_PARTY_NOTICES.md)。

## 从源码构建

需要 Apple Silicon、macOS 15+ 和 **Xcode 26+（Swift 6.2+）**。

```bash
git clone https://github.com/cliptate/cliptate.git
cd cliptate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLIPTATE_APP_STORE=NO
swift build
swift test
./scripts/run.sh
```

SwiftPM 构建应用可执行文件与 CLI，并运行单元测试。`./scripts/run.sh` 组装、签名并启动 **Cliptate Dev.app**，使用独立的开发配置与数据。如只需构建应用，运行 `./scripts/build-and-run.sh build`。

`CLIPTATE_APP_STORE=NO` 选择免费的直接发行渠道，包含 CLI 和基于辅助功能的听写能力。Debug 默认使用此渠道；Release 默认保留 App Store 的能力限制与订阅行为。App Store 订阅服务需自行在本地配置。签名、模型缓存与发行配置详见[开发指南](development.md)。

## 参与贡献与获取帮助

请通过 [GitHub Issues](https://github.com/cliptate/cliptate/issues)反馈问题或提出功能建议，并附上 macOS 版本、应用版本、所选模型和复现步骤。请勿公开私人录音或凭据。

- [贡献指南](../CONTRIBUTING.md) — 开发流程、验证与提交规范
- [架构说明](architecture/README.md) — 代码结构与运行时边界
- [版本说明](release-notes/README.md#version-archive) — 版本历史
- [安全政策](../SECURITY.md) — 漏洞报告方式
- [官网](https://cliptate.github.io) — 产品介绍
