# Qwen3 UI Integration Design

> **Date**: 2026-02-09
> **Status**: Approved

## Overview

集成 Qwen3 ASR 到应用的三个功能模块：
1. **Models 页面** - 支持下载 Qwen3 模型
2. **AI Cut** - 使用强制对齐获取精确时间戳
3. **Voice To Text** - 流式语音转文字

## Feature Summary

| 功能 | 使用模型 | 模式 |
|-----|---------|------|
| **Models 页面** | Qwen3-ASR + ForcedAligner | 下载管理 |
| **AI Cut** | Qwen3-ASR → ForcedAligner | 两阶段：转录 + 精确对齐 |
| **Voice To Text** | Qwen3-ASR | 流式转录（参考 Parakeet） |

---

## Part 1: Models Page

### UI Changes

**ModelsView.swift** - 添加 Qwen3 provider tab：

- 在现有 provider picker 中添加 "Qwen3" 选项
- Provider 顺序: Whisper | Parakeet | Qwen3 | TTS

### Qwen3 Provider Models

| 模型 | 显示名称 | 大小 | 描述 |
|-----|---------|------|-----|
| `qwen3ASR` | Qwen3 ASR (0.6B) | 600MB | 52种语言，MLX优化 |
| `qwen3ForcedAligner` | Qwen3 ForcedAligner (0.6B) | 400MB | 精确字级时间戳 |

### Model Card Display

- 复用现有 `ModelCardView` 组件
- 显示下载进度、状态、操作按钮
- 指标显示：速度、准确度、大小、语言数

---

## Part 2: Qwen3 Streaming Module

### New File: Qwen3StreamingModule.swift

参考 `ParakeetTranscriptionModule` 实现：

```swift
@MainActor
final class Qwen3StreamingModule {
  struct Configuration {
    let chunkDuration: Double       // 音频分块时长 (2-3秒)
    let levelCalculator: ([Float]) -> CGFloat
  }
  
  struct Callbacks {
    let onAudioLevel: (CGFloat) -> Void
    let onInterimText: (String) -> Void
  }
  
  func start(language: Language) async throws
  func stop() async throws -> String?
  func reset()
}
```

### Streaming Flow

1. **音频捕获**: 使用 `AVAudioEngine` 捕获麦克风输入
2. **分块处理**: 累积到 `chunkDuration`（2-3秒）后处理
3. **增量转录**: 调用 `Qwen3ASRModel.generate(audio:)` 
4. **文本合并**: 合并确认文本和临时文本
5. **回调更新**: 通过 `onInterimText` 回调更新 UI

### Comparison with Parakeet

| 特性 | Parakeet | Qwen3 |
|-----|----------|-------|
| 流式API | 原生 `StreamingAsrManager` | 分块模拟 |
| 分块时长 | 0.2秒 | 2-3秒（模型推理开销） |
| 确认机制 | 内置 confirmed/volatile | 手动实现文本对比 |

---

## Part 3: AI Cut with Forced Alignment

### Workflow

```
用户选择 Qwen3 + 视频
      ↓
检查模型 (ASR + ForcedAligner 是否下载)
      ↓
[未下载] → 报错，提示"请先到 Models 页面下载 Qwen3 模型"
      ↓
[已下载] → 提取音频 → Qwen3-ASR.generate() → 原始文本
      ↓
ForcedAligner.generate(audio, text) → 精确时间戳
      ↓
返回带 word-level 时间戳的 Segment[]
```

### Model Validation

```swift
func validateQwen3Models() async throws {
  let asrDownloaded = await ModelDownloadManager.shared.isModelDownloaded(.qwen3ASR)
  let alignerDownloaded = await ModelDownloadManager.shared.isModelDownloaded(.qwen3ForcedAligner)
  
  if !asrDownloaded || !alignerDownloaded {
    throw ModelPreparationError.modelNotDownloaded(
      message: "Qwen3 模型未下载，请先到 Models 页面下载"
    )
  }
}
```

### Error Handling

- **错误类型**: `ModelPreparationError.modelNotDownloaded`
- **UI 显示**: Alert 弹窗，附带"前往 Models"按钮
- **设计考虑**: 方便后期接入付费订阅检查

### Two-Phase Transcription

```swift
/// 两阶段转录：先 ASR 转录，再 ForcedAligner 对齐
public func transcribeWithAlignment(
  audioPath: String,
  language: Language,
  progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
) async throws -> TranscriptionResult {
  // 1. 使用 Qwen3-ASR 获取文本
  let asrResult = try await transcribe(audioPath, language)
  
  // 2. 使用 ForcedAligner 获取精确时间戳
  let aligned = try await alignWithText(audioPath, asrResult.text, language)
  
  // 3. 返回带 word-level 时间戳的结果
  return aligned
}
```

---

## Files to Create/Modify

### New Files
- `Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift`

### Modified Files
- `Sources/VoiceFlowPro/Views/ModelsView.swift` - 添加 Qwen3 provider
- `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift` - 集成 Qwen3 streaming
- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift` - 添加 transcribeWithAlignment()
- `Sources/VoiceFlowPro/Views/AICutView.swift` - 集成 Qwen3 + 模型检查

---

## Implementation Order

1. **Task 1**: Update ModelsView to add Qwen3 provider
2. **Task 2**: Create Qwen3StreamingModule for Voice To Text
3. **Task 3**: Integrate Qwen3StreamingModule into VoiceTranscriber
4. **Task 4**: Add transcribeWithAlignment() to Qwen3ASRTranscriber
5. **Task 5**: Integrate Qwen3 forced alignment into AI Cut
6. **Task 6**: Build and test
