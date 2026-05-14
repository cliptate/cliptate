<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate 图标" />
  <h1>Cliptate</h1>
  <p><strong>面向 Mac 音视频创作者的端侧 AI 工作台</strong></p>

  <p>
    <a href="https://apps.apple.com/"><img alt="在 App Store 下载" src="https://img.shields.io/badge/App%20Store-下载-0066cc?logo=apple&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="100% 本地处理" src="https://img.shields.io/badge/处理方式-100%25%20本地-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">官网</a> ·
    <a href="https://cliptate.github.io#features">功能介绍</a> ·
    <a href="https://cliptate.github.io#voice">语音与 TTS</a> ·
    <a href="https://apps.apple.com/">立即下载</a>
  </p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ko.md">한국어</a> ·
    <a href="README.de.md">Deutsch</a>
  </p>
</div>

---

Cliptate 是一款原生 macOS 应用，将音视频制作中最耗时的环节整合为一条连续、完全本地化的工作流。无需云端上传，无需 API 密钥，无需等待网络响应——所有模型均在你的 Mac 上运行。

---

## 功能

### 🎙 语音听写 — 说话即输入

实时流式语音转文字，像输入法一样随时唤起。通过全局快捷键从任意应用调出，说话即可生成可编辑文本。

- 流式实时转写，低延迟输出
- 多说话人自动识别与标注
- 自定义词典，提升专有词汇准确率
- 全局快捷键随时唤起或暂停

### 📝 离线转写

批量转写音视频文件，全程在设备端完成。支持多种 ASR 引擎（Parakeet、Qwen3、FireRed ASR）和针对 Apple Silicon 优化的 MLX 推理，生成精准字幕，不向任何服务器发送音频。

### ✂️ 智能去停顿

基于 VAD 的静音检测，自动识别并批量裁剪播客、访谈、课程录音中的冗余停顿，让粗剪更快接近可交付状态。

### 👥 说话人识别

自动识别录音中的多位说话人并分段标注。Sortformer 与 Silero VAD 模型在设备端运行，为访谈、圆桌和会议记录生成结构清晰、带说话人归属的逐字稿。

### 🔊 TTS 语音合成 — 四种模式

| 模式 | 说明 |
|---|---|
| **预设音色** | 内置多语言音色库，即开即用 |
| **声音克隆** | 上传参考音频，复现说话人的音色与节奏 |
| **情感控制** | 通过提示词调控指定音色的情感与表达风格 |
| **音色设计** | 用文字描述生成完全原创的声音形象 |

所有 TTS 推理均通过 MLX 在设备端完成，音频不上传云端。

### 🌐 AI 纠错与翻译

上下文感知的字幕纠错，结合设备端或 Apple 翻译生成多语言输出，无需切换工具即可制作面向全球受众的内容。

### ⭐ 高亮标记

自动识别录音中最关键的句子与精彩片段，并在时间线上标注——让剪辑和发布流程更快推进。

---

## 导出格式

Cliptate 直接输出你常用工具所需的格式：

| 格式 | 用途 |
|---|---|
| **FCPXML** | Final Cut Pro 时间线工程交换 |
| **SRT** | 通用字幕交付 |
| **ASS** | 带样式与定位的字幕格式 |
| **VTT** | 适用于浏览器与流媒体平台的网页字幕 |

兼容 **Final Cut Pro**、**DaVinci Resolve** 和 **Adobe Premiere Pro**。

---

## 隐私与安全

- **零云端上传** — 音频、视频和字幕始终留在你的 Mac 上
- **无需 API 密钥** — 所有模型随应用附带或首次使用时下载
- **无网络依赖** — 模型缓存后完全离线可用
- 适合敏感、机密及合规要求严格的内容场景

---

## 系统要求

| | |
|---|---|
| **平台** | macOS 14 Sonoma 或更高版本 |
| **架构** | 推荐 Apple Silicon（M1 及以上） |
| **存储空间** | 因模型选择而异（完整模型组约 2–8 GB） |

---

## 技术栈

Cliptate 完全使用 Swift 开发，基于 Apple 原生框架构建：

---

## 适用场景

**播客主与访谈者** — 去停顿、生成字幕、标记可发布片段，无需离开应用。

**Vlog 与短视频创作者** — 让口播剪辑更顺滑，专注于节奏和表达。

**课程制作者与会议记录者** — 通过实时听写或批量转写，将数小时录音转化为可检索、可翻译的文本资产。

**多语言内容团队** — 克隆声音、翻译字幕、生成配音版本——全在一台 Mac 上完成。

---

## 链接

- **官网：** [cliptate.github.io](https://cliptate.github.io)
- **App Store：** [下载 Cliptate](https://apps.apple.com/)
- **问题与反馈：** [GitHub Issues](https://github.com/cliptate/cliptate.github.io/issues)

---

<div align="center">
  <sub>为重视隐私、速度与专业输出的创作者而生。</sub>
</div>
