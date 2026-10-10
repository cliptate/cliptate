# Qwen3 Dictionary Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pass Dictionary entries into every Qwen3 ASR path as native model `context`, while keeping the existing dictionary post-processing as a fallback correction layer.

**Architecture:** Add a single `dictionaryContext` string built from `AppConfiguration.voiceToTextCustomDictionary`, thread it through Qwen3-specific entry points, and pass it to Qwen3's native `generate(..., context:)` / `generateStream(..., context:)` APIs. Keep `ASRDictionaryBiasService.apply(...)` after model output so behavior stays robust even if the model only partially follows the provided context.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, MLXAudioSTT (`mlx-audio-swift` main), SwiftUI

---

### Task 1: Add a test seam and context-aware Qwen3 transcriber API

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- Create: `Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift`
- Modify: `Package.swift:52-70`

- [ ] **Step 1: Write the failing transcriber context test**

```swift
import Foundation
import Testing

@testable import VoiceFlowPro

@Suite("Qwen3ASRTranscriber dictionary context")
struct Qwen3ASRTranscriberContextTests {
  @Test("file transcription forwards dictionary context into Qwen3 generate")
  func fileTranscriptionForwardsDictionaryContext() async throws {
    let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
    let transcriber = Qwen3ASRTranscriber(
      model: .qwen3ASR,
      testHooks: .init(
        loadAudioSamples: { _ in Array(repeating: 0.01, count: 16000) },
        audioDuration: { _ in 1.0 },
        generate: { request in
          capture.record(request)
          return .init(
            text: "sysulq whispercut",
            segments: [["text": "sysulq whispercut", "start": 0.0, "end": 1.0]],
            language: "English",
            promptTokens: 4,
            generationTokens: 3,
            totalTokens: 7,
            promptTps: 1,
            generationTps: 1,
            totalTime: 1,
            peakMemoryUsage: 0
          )
        }
      )
    )

    let result = try await transcriber.transcribeWithProgress(
      audioPath: "/tmp/fake.wav",
      language: .english,
      dictionaryContext: "WhisperCutPro\nsysulq"
    ) { _ in }

    #expect(capture.last?.context == "WhisperCutPro\nsysulq")
    #expect(result.segments.first?.text == "sysulq whispercut")
  }
}
```

- [ ] **Step 2: Register the new test file**

```swift
.testTarget(
    name: "VoiceFlowProTests",
    dependencies: ["VoiceFlowPro"],
    path: "Sources/VoiceFlowProTests",
    sources: [
        "Services/Qwen3ASRTranscriberContextTests.swift",
        "Services/ModelDownloadStateStoreTests.swift",
        "Services/ModelCacheManagerLanguageTests.swift",
        "Services/ModelCacheManagerLifecycleTests.swift",
        "Services/ModelDownloadManagerTests.swift",
        "Services/SortformerVADSegmenterTests.swift",
        "Services/SegmentedAlignmentPipelineTests.swift",
        "Services/SpeechSegmenterTests.swift",
        "Services/MLXParakeetTranscriberTests.swift",
        "Services/AudioProcessorChunkTests.swift",
        "Integration/ModelSelectionUIFlowTests.swift",
        "Integration/TranscriberPoolMigrationTests.swift",
        "Models/AppConfigurationModelLifecyclePersistenceTests.swift",
        "Models/SegmentTests.swift",
        "Models/ModelVariantTTSTests.swift"
    ],
```

- [ ] **Step 3: Run the new test and verify it fails**

Run: `swift test --filter fileTranscriptionForwardsDictionaryContext`

Expected: FAIL with errors like `Qwen3ASRTranscriber.TestHooks` / `dictionaryContext` not found.

- [ ] **Step 4: Add minimal Qwen3-native context support**

```swift
public final class Qwen3ASRTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber {
  struct GenerationRequest: Sendable {
    let audio: MLXArray
    let language: String
    let chunkDuration: Float
    let minChunkDuration: Float
    let context: String
  }

  struct TestHooks {
    final class GenerateCapture: @unchecked Sendable {
      private(set) var last: (context: String, language: String)?
      func record(_ request: GenerationRequest) {
        last = (context: request.context, language: request.language)
      }
    }

    var loadAudioSamples: (@Sendable (URL) async throws -> [Float])?
    var audioDuration: (@Sendable (URL) async throws -> Double)?
    var generate: (@Sendable (GenerationRequest) throws -> STTOutput)?
  }

  private let testHooks: TestHooks?

  public init(model: ModelVariant = .qwen3ASR, testHooks: TestHooks? = nil) {
    self.modelVariant = model
    self.testHooks = testHooks
    logger.notice("🤖 Qwen3ASRTranscriber initialized with model: \(model.rawValue)")
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    dictionaryContext: String? = nil,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try await transcribeWithProgressInternal(
      audioPath: audioPath,
      language: language,
      dictionaryContext: dictionaryContext,
      chunkDuration: nil,
      progressHandler: progressHandler
    )
  }
}
```

- [ ] **Step 5: Thread context into the native Qwen3 model call**

```swift
private func transcribeWithProgressInternal(
  audioPath: String,
  language: Language,
  dictionaryContext: String?,
  chunkDuration: Float?,
  progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
) async throws -> TranscriptionResult {
  let context = dictionaryContext ?? ""
  let audioURL = URL(fileURLWithPath: audioPath)

  let audioDuration: Double
  if let durationHook = testHooks?.audioDuration {
    audioDuration = try await durationHook(audioURL)
  } else {
    let asset = AVURLAsset(url: audioURL)
    let assetDuration = try await asset.load(.duration)
    audioDuration = max(assetDuration.seconds, 0.001)
  }

  let audioSamples: [Float]
  if let loadHook = testHooks?.loadAudioSamples {
    audioSamples = try await loadHook(audioURL)
  } else {
    audioSamples = try await AudioProcessor.loadAndConvertAudio(url: audioURL)
  }

  let audioArray = MLXArray(audioSamples)
  let languageName = language.qwen3LanguageName

  if let asrModel = asrModel {
    let effectiveChunkDuration = max(0.5, chunkDuration ?? 1200.0)
    let result: STTOutput
    if let generateHook = testHooks?.generate {
      result = try generateHook(
        .init(
          audio: audioArray,
          language: languageName,
          chunkDuration: effectiveChunkDuration,
          minChunkDuration: 1.0,
          context: context
        )
      )
    } else {
      result = asrModel.generate(
        audio: audioArray,
        maxTokens: 8192,
        temperature: 0.0,
        context: context,
        language: languageName,
        chunkDuration: effectiveChunkDuration,
        minChunkDuration: 1.0
      )
    }
    // existing segment conversion stays here
  }
}
```

- [ ] **Step 6: Add context-aware chunk and streaming entry points**

```swift
public func transcribeStreamingChunk(
  samples16k: [Float],
  language: Language,
  dictionaryContext: String? = nil
) throws -> String {
  let context = dictionaryContext ?? ""
  let audioArray = MLXArray(samples16k)
  let languageName = language.qwen3LanguageName
  let result = asrModel.generate(
    audio: audioArray,
    maxTokens: 8192,
    temperature: 0.0,
    context: context,
    language: languageName,
    chunkDuration: 1200.0,
    minChunkDuration: 1.0
  )
  return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func transcribeChunk(
  samples: [Float],
  language: Language,
  dictionaryContext: String? = nil
) async throws -> String {
  try transcribeStreamingChunk(
    samples16k: samples,
    language: language,
    dictionaryContext: dictionaryContext
  )
}
```

- [ ] **Step 7: Run the transcriber test and verify it passes**

Run: `swift test --filter fileTranscriptionForwardsDictionaryContext`

Expected: PASS with one test in `Qwen3ASRTranscriber dictionary context`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift \
  Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift \
  Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift
git commit -m "feat: add qwen3 dictionary context API"
```

### Task 2: Wire dictionary context into AICut and segmented chunk transcription

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift:650-1010`
- Test: `Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift`

- [ ] **Step 1: Write the failing chunk-path test**

```swift
@Test("chunk transcription forwards dictionary context into Qwen3 chunk path")
func chunkTranscriptionForwardsDictionaryContext() async throws {
  let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
  let transcriber = Qwen3ASRTranscriber(
    model: .qwen3ASR,
    testHooks: .init(
      generate: { request in
        capture.record(request)
        return .init(
          text: "WhisperCutPro",
          segments: [["text": "WhisperCutPro", "start": 0.0, "end": 1.0]],
          language: "English",
          promptTokens: 4,
          generationTokens: 3,
          totalTokens: 7,
          promptTps: 1,
          generationTps: 1,
          totalTime: 1,
          peakMemoryUsage: 0
        )
      }
    )
  )

  _ = try await transcriber.transcribeChunk(
    samples: Array(repeating: 0.02, count: 16000),
    language: .english,
    dictionaryContext: "WhisperCutPro"
  )

  #expect(capture.last?.context == "WhisperCutPro")
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --filter chunkTranscriptionForwardsDictionaryContext`

Expected: FAIL until call sites are updated or signature is incomplete.

- [ ] **Step 3: Build one dictionary context per AICut transcription job**

```swift
let dictionaryContext = ASRDictionaryBiasService.dictionaryContext(
  from: config.voiceToTextCustomDictionary
)
```

- [ ] **Step 4: Pass context into direct Qwen3 file transcription**

```swift
if let qwenTranscriber = transcriber as? Qwen3ASRTranscriber {
  result = try await qwenTranscriber.transcribeWithProgress(
    audioPath: url.path,
    language: config.language,
    dictionaryContext: dictionaryContext,
    progressHandler: progressHandler
  )
} else {
  result = try await transcriber.transcribeWithProgress(
    audioPath: url.path,
    language: config.language,
    progressHandler: progressHandler
  )
}
```

- [ ] **Step 5: Pass context into segmented chunk transcription**

```swift
private func runSegmentedAlignmentPipeline(
  sourceURL: URL,
  language: Language,
  asrTranscriber: Transcriber,
  aligner: Qwen3ASRTranscriber,
  modelUsed: String,
  dictionaryContext: String?,
  progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
) async throws -> TranscriptionResult {
  return try await SegmentedAlignmentPipeline().run(
    speechSegments: speechSegments,
    totalDuration: audioDuration,
    modelUsed: modelUsed,
    progressHandler: progressHandler,
    transcribe: { segment in
      let chunkSamples = AudioProcessor.extractSamples(
        samples: audioSamples,
        startTime: segment.startTime,
        endTime: segment.endTime
      )
      guard !chunkSamples.isEmpty else { return "" }

      if let qwenChunkTranscriber = asrTranscriber as? Qwen3ASRTranscriber {
        return try await qwenChunkTranscriber.transcribeChunk(
          samples: chunkSamples,
          language: language,
          dictionaryContext: dictionaryContext
        )
      } else if let chunkTranscriber = asrTranscriber as? ChunkTranscriber {
        return try await chunkTranscriber.transcribeChunk(samples: chunkSamples, language: language)
      }

      let chunkResult = try await asrTranscriber.transcribeWithProgress(
        audioPath: chunkURL.path,
        language: language
      ) { _ in }
      return chunkResult.segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    },
    align: { segment, text in
      try aligner.alignChunk(samples: chunkSamples, text: text, language: language)
    }
  )
}
```

- [ ] **Step 6: Run the focused test and AICut-related suite**

Run: `swift test --filter "Qwen3ASRTranscriber dictionary context"`

Expected: PASS with both transcriber context tests green.

- [ ] **Step 7: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift \
  Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift
git commit -m "feat: pass dictionary context through qwen3 file transcription"
```

### Task 3: Wire dictionary context into realtime streaming and history reprocessing

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift:1-220`
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift:1548-1585`
- Modify: `Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift`

- [ ] **Step 1: Write the failing streaming context test**

```swift
@Test("streaming chunk transcription forwards dictionary context into Qwen3 generate")
func streamingChunkForwardsDictionaryContext() throws {
  let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
  let transcriber = Qwen3ASRTranscriber(
    model: .qwen3ASR,
    testHooks: .init(
      generate: { request in
        capture.record(request)
        return .init(
          text: "sysulq",
          segments: [["text": "sysulq", "start": 0.0, "end": 1.0]],
          language: "English",
          promptTokens: 4,
          generationTokens: 3,
          totalTokens: 7,
          promptTps: 1,
          generationTps: 1,
          totalTime: 1,
          peakMemoryUsage: 0
        )
      }
    )
  )

  _ = try transcriber.transcribeStreamingChunk(
    samples16k: Array(repeating: 0.03, count: 16000),
    language: .english,
    dictionaryContext: "sysulq"
  )

  #expect(capture.last?.context == "sysulq")
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --filter streamingChunkForwardsDictionaryContext`

Expected: FAIL until streaming call sites are wired.

- [ ] **Step 3: Add dictionary context state to Qwen3StreamingModule**

```swift
@MainActor
final class Qwen3StreamingModule {
  private var dictionaryContext: String?

  func start(
    language: Language,
    dictionaryContext: String? = nil,
    using transcriber: Qwen3ASRTranscriber
  ) async throws {
    reset()
    isActive = true
    currentLanguage = language
    self.dictionaryContext = dictionaryContext
    asrTranscriber = transcriber
    try configureAudioPipeline()
  }
}
```

- [ ] **Step 4: Pass context into streaming chunk transcription**

```swift
private func transcribe(samples: [Float]) throws {
  guard let transcriber = asrTranscriber else { return }
  guard !samples.isEmpty else { return }

  let text = try transcriber.transcribeStreamingChunk(
    samples16k: samples,
    language: currentLanguage,
    dictionaryContext: dictionaryContext
  )
  guard !text.isEmpty else { return }

  accumulatedText = mergeTranscript(accumulatedText, with: text)
  callbacks.onInterimText(collapseWhitespace(accumulatedText))
}
```

- [ ] **Step 5: Wire VoiceToText history reprocessing**

```swift
let dictionaryContext = ASRDictionaryBiasService.dictionaryContext(
  from: config.voiceToTextCustomDictionary
)

let result: TranscriptionResult
if let qwenTranscriber = transcriber as? Qwen3ASRTranscriber {
  result = try await qwenTranscriber.transcribeWithProgress(
    audioPath: url.path,
    language: targetLanguage,
    dictionaryContext: dictionaryContext
  ) { progress in
    Task { @MainActor in
      guard self.reprocessingSessionID == session.id else { return }
      self.reprocessingProgress = Double(progress.progress)
      self.historyStatusSessionID = session.id
      self.historyStatusMessage = progress.statusMessage
    }
  }
} else {
  result = try await transcriber.transcribeWithProgress(
    audioPath: url.path,
    language: targetLanguage
  ) { progress in
    Task { @MainActor in
      guard self.reprocessingSessionID == session.id else { return }
      self.reprocessingProgress = Double(progress.progress)
      self.historyStatusSessionID = session.id
      self.historyStatusMessage = progress.statusMessage
    }
  }
}
```

- [ ] **Step 6: Run the focused tests**

Run: `swift test --filter "Qwen3ASRTranscriber dictionary context"`

Expected: PASS with file/chunk/streaming tests all green.

- [ ] **Step 7: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift \
  Sources/VoiceFlowPro/Views/VoiceToTextView.swift \
  Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift
git commit -m "feat: pass dictionary context through qwen3 streaming paths"
```

### Task 4: Keep fallback bias, run full validation, and document the handoff

**Files:**
- Modify: `Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift`
- Verify: `Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift`

- [ ] **Step 1: Write the fallback-bias regression test**

```swift
@Test("dictionary bias fallback still normalizes qwen3 output after context injection")
func fallbackBiasStillApplies() {
  let segments = [
    Segment(startTime: 0, endTime: 1, text: "whisper cut pro", words: nil, confidence: nil)
  ]

  let biased = ASRDictionaryBiasService.apply(
    to: segments,
    dictionaryEntries: ["WhisperCutPro"]
  )

  #expect(biased.first?.text == "WhisperCutPro")
}
```

- [ ] **Step 2: Run the focused fallback test**

Run: `swift test --filter fallbackBiasStillApplies`

Expected: PASS.

- [ ] **Step 3: Run the full package test suite**

Run: `swift test`

Expected: all suites pass; existing MLX metallib warnings may still appear in this environment, but there should be no new failures.

- [ ] **Step 4: Run a build smoke check**

Run: `swift build`

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift
git commit -m "test: cover qwen3 dictionary context fallback behavior"
```

- [ ] **Step 6: Final integration commit**

```bash
git add Package.swift \
  Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift \
  Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift \
  Sources/VoiceFlowPro/Views/AICutView.swift \
  Sources/VoiceFlowPro/Views/VoiceToTextView.swift \
  Sources/VoiceFlowProTests/Services/Qwen3ASRTranscriberContextTests.swift
git commit -m "feat: integrate dictionary context across qwen3 asr flows"
```
