<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate app icon" />
  <h1>Cliptate</h1>
  <p><strong>On-device AI workspace for Mac audio and video creators</strong></p>
  <p>面向 Mac 音视频创作者的端侧 AI 工作台</p>

  <p>
    <a href="https://apps.apple.com/"><img alt="Download on the App Store" src="https://img.shields.io/badge/App%20Store-Download-0066cc?logo=apple&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="100% On-Device" src="https://img.shields.io/badge/Processing-100%25%20Local-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">Website</a> ·
    <a href="https://cliptate.github.io#features">Features</a> ·
    <a href="https://cliptate.github.io#voice">Voice & TTS</a> ·
    <a href="https://apps.apple.com/">Download</a>
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

Cliptate is a native macOS application that compresses the most time-consuming steps in audio and video production into one continuous, fully local workflow. No cloud upload, no API keys, no waiting on network round trips — every model runs on your Mac.

---

## Features

### 🎙 Voice Dictation — Speak to Type

Real-time streaming speech-to-text that works like an input method. Invoke it from any context with a global keyboard shortcut and get editable text as you speak.

- Streaming transcription with minimal latency
- Automatic multi-speaker diarization and labeling
- Custom vocabulary dictionary for domain-specific accuracy
- Global keyboard shortcut to invoke or pause anywhere

### 📝 Offline Transcription

Batch-transcribe audio and video files entirely on-device. Supports multiple ASR engines (Parakeet, Qwen3, FireRed ASR) and Apple Silicon-optimized MLX inference for fast, accurate captions without sending audio to any server.

### ✂️ Smart Pause Trimming

VAD-powered silence detection automatically identifies and removes dead air across podcasts, interviews, and course recordings. Rough cuts arrive closer to delivery-ready with minimal manual scrubbing.

### 👥 Speaker Diarization

Automatically identify and label multiple speakers across a recording. Sortformer and Silero VAD models run on-device to produce structured, speaker-attributed transcripts for interviews, panels, and meetings.

### 🔊 TTS Voice Synthesis — Four Modes

| Mode | Description |
|---|---|
| **Preset** | Built-in multilingual voices, ready instantly |
| **Clone** | Upload reference audio to reproduce a speaker's timbre and cadence |
| **Emotion Control** | Steer emotion and speaking style on a named speaker via text prompts |
| **Voice Design** | Describe a voice in text to synthesize an entirely original persona |

All TTS inference runs on-device via MLX. No audio is sent to the cloud.

### 🌐 AI Correction & Translation

Context-aware transcript correction followed by on-device or Apple Translation-powered multilingual output. Produce subtitles and scripts in multiple languages without switching tools.

### ⭐ Highlight Detection

Automatically surface the strongest moments and key sentences from a recording and mark them on the timeline — so publishing edits move faster.

---

## Export Formats

Cliptate exports directly into the tools you already use:

| Format | Use |
|---|---|
| **FCPXML** | Final Cut Pro timeline project exchange |
| **SRT** | Universal subtitle delivery |
| **ASS** | Styled subtitles with positioning and formatting |
| **VTT** | Web captions for browsers and streaming platforms |

Compatible with **Final Cut Pro**, **DaVinci Resolve**, and **Adobe Premiere Pro**.

---

## Privacy & Security

- **Zero cloud upload** — audio, video, and transcripts never leave your Mac
- **No API keys required** — all models ship with the app or download on first use
- **No network dependency** — works fully offline once models are cached
- Suitable for sensitive, confidential, and compliance-regulated content

---

## Requirements

| | |
|---|---|
| **Platform** | macOS 14 Sonoma or later |
| **Architecture** | Apple Silicon (M1 and later) recommended |
| **Storage** | Varies by model selection (2–8 GB for full model set) |

---

## Tech Stack

Cliptate is built entirely in Swift and runs on Apple-native frameworks:

---

## Use Cases

**Podcasters & Interviewers** — Trim silence, generate captions, and flag publishable moments without leaving the app.

**Vloggers & Short-form Creators** — Smooth out talking-head recordings and keep focus on pacing instead of manual cuts.

**Course Creators & Meeting Recorders** — Turn hours of live or recorded audio into searchable, translatable text assets via dictation or batch transcription.

**Multilingual Content Teams** — Clone a voice, translate the transcript, and produce dubbed alternate-language versions — all on one Mac.

---

## Links

- **Website:** [cliptate.github.io](https://cliptate.github.io)
- **App Store:** [Download Cliptate](https://apps.apple.com/)
- **Issues & Feedback:** [GitHub Issues](https://github.com/cliptate/cliptate.github.io/issues)

---

<div align="center">
  <sub>Built for creators who care about privacy, speed, and professional output.</sub>
</div>
