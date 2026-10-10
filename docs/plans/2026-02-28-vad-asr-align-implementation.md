# VAD -> ASR -> Align Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace long-audio full-text alignment with a unified VAD-segmented pipeline so no single alignment request exceeds long-duration accuracy limits.

**Architecture:** Introduce a shared speech segmentation service and a segmented alignment orchestrator that all offline AI Cut engines use. The orchestrator runs strict fail-fast `VAD -> ASR -> align` per speech segment, rebases timestamps to global timeline, and returns one compatibility-preserving segment with full `words`. Qwen3 two-phase flow is refactored to use the same segmented semantics instead of one-shot full-audio alignment.

**Tech Stack:** Swift, SwiftUI, AVFoundation, MLXAudioSTT, WhisperKit, FluidAudio VAD, Swift Testing, xcodebuild

---

Execution discipline: use @superpowers/test-driven-development for each task; if any step fails unexpectedly, use @superpowers/systematic-debugging before changing approach.

### Task 1: Add a reusable SpeechSegmenter with deterministic test seam

**Files:**
- Create: `Sources/VoiceFlowPro/Services/SpeechSegmenter.swift`
- Test: `Sources/VoiceFlowProTests/Services/SpeechSegmenterTests.swift`

**Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import VoiceFlowPro

@Suite("SpeechSegmenter")
struct SpeechSegmenterTests {
  @Test("clamps segment bounds and drops invalid ranges")
  func clampsAndFiltersRanges() async throws {
    let sut = SpeechSegmenter(
      segmentSpeech: { _, _ in
        [
          VadSegment(startTime: -1, endTime: 2),
          VadSegment(startTime: 3, endTime: 3),
          VadSegment(startTime: 9, endTime: 15)
        ]
      }
    )

    let result = try await sut.segmentSpeech(
      audioSamples: Array(repeating: 0, count: 16000 * 12),
      totalDuration: 10
    )

    #expect(result == [
      VadSegment(startTime: 0, endTime: 2),
      VadSegment(startTime: 9, endTime: 10)
    ])
  }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/SpeechSegmenterTests
```
Expected: FAIL because `SpeechSegmenter` does not exist.

**Step 3: Write minimal implementation**

```swift
import Foundation
import FluidAudio

struct SpeechSegmenter {
  typealias SegmentSpeechFn = @Sendable ([Float], VadSegmentationConfig) async throws -> [VadSegment]
  private let segmentSpeech: SegmentSpeechFn

  init(segmentSpeech: @escaping SegmentSpeechFn = SpeechSegmenter.defaultSegmentSpeech) {
    self.segmentSpeech = segmentSpeech
  }

  func segmentSpeech(audioSamples: [Float], totalDuration: Double) async throws -> [VadSegment] {
    var config = VadSegmentationConfig.default
    config.minSpeechDuration = 0.25
    config.minSilenceDuration = 0.4
    config.speechPadding = 0.12
    config.maxSpeechDuration = 30.0

    let raw = try await segmentSpeech(audioSamples, config)
    return raw
      .map { VadSegment(startTime: min(max($0.startTime, 0), totalDuration), endTime: min(max($0.endTime, 0), totalDuration)) }
      .filter { $0.endTime > $0.startTime }
  }

  private static func defaultSegmentSpeech(
    audioSamples: [Float],
    config: VadSegmentationConfig
  ) async throws -> [VadSegment] {
    let manager = try await VadManager(config: VadConfig())
    return try await manager.segmentSpeech(audioSamples, config: config)
  }
}
```

**Step 4: Run test to verify it passes**

Run the same command from Step 2.  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/SpeechSegmenter.swift Sources/VoiceFlowProTests/Services/SpeechSegmenterTests.swift
git commit -m "feat: add reusable speech segmenter for VAD slicing" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add segmented alignment orchestrator (fail-fast + global offset merge)

**Files:**
- Create: `Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift`

**Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import VoiceFlowPro

@Suite("SegmentedAlignmentPipeline")
struct SegmentedAlignmentPipelineTests {
  @Test("long audio aligns in chunks under hard duration cap")
  func enforcesChunkDurationCap() async throws {
    var seenDurations: [Double] = []
    let sut = SegmentedAlignmentPipeline(
      dependencies: .mock(
        vadSegments: [
          VadSegment(startTime: 0, endTime: 120),
          VadSegment(startTime: 120, endTime: 260),
          VadSegment(startTime: 260, endTime: 420)
        ],
        asrText: "hello world",
        alignWords: { segmentStart, _ in
          seenDurations.append(segmentStart.1 - segmentStart.0)
          return [WordTiming(word: "hello", startTime: 0.1, endTime: 0.4)]
        }
      )
    )

    _ = try await sut.run(
      audioURL: URL(fileURLWithPath: "/tmp/fake.wav"),
      language: .english
    ) { _ in }

    #expect(seenDurations.allSatisfy { $0 < 300 })
  }

  @Test("offset merge keeps monotonic word timeline")
  func mergedWordsAreMonotonic() async throws {
    // Build two aligned chunks with local 0.x timestamps and verify rebased global order.
  }

  @Test("any chunk failure aborts full pipeline")
  func failFastOnSingleChunkFailure() async throws {
    // second chunk ASR/align throws -> whole run throws
  }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/SegmentedAlignmentPipelineTests
```
Expected: FAIL because `SegmentedAlignmentPipeline` does not exist.

**Step 3: Write minimal implementation**

```swift
import Foundation

struct SegmentedAlignmentPipeline {
  struct Dependencies {
    let loadAudioSamples: @Sendable (URL) async throws -> [Float]
    let audioDuration: @Sendable (URL) async throws -> Double
    let segmentSpeech: @Sendable ([Float], Double) async throws -> [VadSegment]
    let writeChunkAudio: @Sendable ([Float], VadSegment) throws -> URL
    let transcribeChunk: @Sendable (URL, Language) async throws -> String
    let alignChunk: @Sendable (URL, String, Language) async throws -> [WordTiming]
    let cleanupChunk: @Sendable (URL) -> Void
  }

  private let dependencies: Dependencies

  func run(
    audioURL: URL,
    language: Language,
    progress: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    let samples = try await dependencies.loadAudioSamples(audioURL)
    let duration = try await dependencies.audioDuration(audioURL)
    let speech = try await dependencies.segmentSpeech(samples, duration)
    guard !speech.isEmpty else {
      return TranscriptionResult(segments: [], totalDuration: duration, processingTime: 0, modelUsed: "segmented-align")
    }

    let started = Date()
    var mergedWords: [WordTiming] = []

    for (index, segment) in speech.enumerated() {
      let chunkURL = try dependencies.writeChunkAudio(samples, segment)
      defer { dependencies.cleanupChunk(chunkURL) }

      let text = try await dependencies.transcribeChunk(chunkURL, language)
      let localWords = try await dependencies.alignChunk(chunkURL, text, language)
      let rebased = localWords.map {
        WordTiming(word: $0.word, startTime: segment.startTime + $0.startTime, endTime: segment.startTime + $0.endTime, confidence: $0.confidence, punctuation: $0.punctuation)
      }
      mergedWords.append(contentsOf: rebased)

      let p = Float(index + 1) / Float(speech.count)
      progress(TranscriptionProgress(currentSegments: [], progress: p, statusMessage: "Align \(index + 1)/\(speech.count)"))
    }

    let sorted = mergedWords.sorted { $0.startTime < $1.startTime }
    let text = WordTimingTextComposer.composeText(from: sorted)
    let finalSegment = Segment(
      startTime: sorted.first?.startTime ?? 0,
      endTime: sorted.last?.endTime ?? 0,
      text: text,
      words: sorted,
      confidence: nil
    )
    return TranscriptionResult(
      segments: sorted.isEmpty ? [] : [finalSegment],
      totalDuration: duration,
      processingTime: Date().timeIntervalSince(started),
      modelUsed: "segmented-align"
    )
  }
}
```

**Step 4: Run test to verify it passes**

Run the same command from Step 2.  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift
git commit -m "feat: add fail-fast segmented alignment pipeline" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Extend AudioProcessor with chunk extraction/export helpers

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/AudioProcessor.swift`
- Test: `Sources/VoiceFlowProTests/Services/AudioProcessorChunkTests.swift`

**Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import VoiceFlowPro

@Suite("AudioProcessor chunk helpers")
struct AudioProcessorChunkTests {
  @Test("extractSamples returns exact 16kHz window")
  func extractsSampleWindow() {
    let samples = Array(0..<32_000).map(Float.init)
    let chunk = AudioProcessor.extractSamples(samples: samples, startTime: 0.5, endTime: 1.0, sampleRate: 16_000)
    #expect(chunk.count == 8_000)
    #expect(chunk.first == samples[8_000])
  }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/AudioProcessorChunkTests
```
Expected: FAIL because helper APIs are missing.

**Step 3: Write minimal implementation**

```swift
extension AudioProcessor {
  static func extractSamples(
    samples: [Float],
    startTime: Double,
    endTime: Double,
    sampleRate: Double = 16_000
  ) -> [Float] {
    guard endTime > startTime else { return [] }
    let start = max(0, Int(startTime * sampleRate))
    let end = min(samples.count, Int(endTime * sampleRate))
    guard end > start else { return [] }
    return Array(samples[start..<end])
  }

  static func saveSegmentToTemporaryFile(samples: [Float]) throws -> URL {
    try saveToTemporaryFile(audioSamples: samples)
  }
}
```

**Step 4: Run test to verify it passes**

Run the same command from Step 2.  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/AudioProcessor.swift Sources/VoiceFlowProTests/Services/AudioProcessorChunkTests.swift
git commit -m "feat: add audio chunk extraction helpers" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Wire AI Cut single/batch flows to unified segmented pipeline

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift:640-710, 853-883`
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift` (add `runSegmentedAlignmentPipeline(...)` private helper)
- Test: `Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift` (add integration-style call-path assertions with mock dependencies)

**Step 1: Write the failing integration-oriented test**

```swift
@Test("pipeline stages execute in strict VAD -> ASR -> Align order")
func stageOrder() async throws {
  var events: [String] = []
  let sut = SegmentedAlignmentPipeline(
    dependencies: .mock(
      onVAD: { events.append("vad") },
      onASR: { _, _ in events.append("asr") },
      onAlign: { _, _, _ in events.append("align") }
    )
  )
  _ = try await sut.run(audioURL: URL(fileURLWithPath: "/tmp/fake.wav"), language: .english) { _ in }
  #expect(events == ["vad", "asr", "align"])
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/SegmentedAlignmentPipelineTests
```
Expected: FAIL before wiring/support code is added.

**Step 3: Write minimal implementation**

```swift
// AICutView.swift
private func runSegmentedAlignmentPipeline(
  sourceAudioURL: URL,
  language: Language,
  asrTranscribeChunk: @escaping @Sendable (URL, Language) async throws -> String,
  alignChunk: @escaping @Sendable (URL, String, Language) async throws -> [WordTiming],
  progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
) async throws -> TranscriptionResult {
  let pipeline = SegmentedAlignmentPipeline.live(
    asrTranscribeChunk: asrTranscribeChunk,
    alignChunk: alignChunk
  )
  return try await pipeline.run(audioURL: sourceAudioURL, language: language, progress: progressHandler)
}

// Replace both previous full-text align calls with runSegmentedAlignmentPipeline(...)
```

**Step 4: Run test to verify it passes**

Run command from Step 2; then run a build smoke test:
```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS'
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift
git commit -m "refactor: route AI Cut alignment through segmented pipeline" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Refactor Qwen3 two-phase method to segmented semantics

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift:497-624`
- Test: `Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift` (reuse with Qwen3-like closures)

**Step 1: Write the failing test**

```swift
@Test("Qwen3 path aborts on second chunk align failure")
func qwenLikeFlowFailFast() async throws {
  let sut = SegmentedAlignmentPipeline(
    dependencies: .mock(
      vadSegments: [VadSegment(startTime: 0, endTime: 10), VadSegment(startTime: 10, endTime: 20)],
      asrText: "ok",
      alignWords: { _, index in
        if index == 1 { throw NSError(domain: "test", code: 99) }
        return [WordTiming(word: "ok", startTime: 0, endTime: 0.3)]
      }
    )
  )
  await #expect(throws: Error.self) {
    _ = try await sut.run(audioURL: URL(fileURLWithPath: "/tmp/fake.wav"), language: .english) { _ in }
  }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/SegmentedAlignmentPipelineTests
```
Expected: FAIL until Qwen3 path and fail-fast semantics are fully aligned.

**Step 3: Write minimal implementation**

```swift
// Qwen3ASRTranscriber.transcribeWithAlignment(...)
// Replace one-shot `alignWithText(audioPath: fullAudio, text: fullText, ...)` with:
// 1) Build segmented pipeline with:
//    - ASR closure using provided asrTranscriber on chunk URL
//    - Align closure using self.alignWithText on chunk URL + chunk text
// 2) Run pipeline and return merged single-segment result
// 3) Keep existing rebuild/compat behavior only if still needed by downstream
```

**Step 4: Run tests to verify it passes**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/SegmentedAlignmentPipelineTests
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS'
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift
git commit -m "refactor: apply segmented VAD-ASR-align flow to Qwen3 two-phase transcription" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Final verification and documentation sync

**Files:**
- Modify: `docs/plans/2026-02-28-vad-asr-align-implementation.md` (mark final verification notes if needed)

**Step 1: Write the failing check (if any)**

No new test file; use full-suite verification as gate.

**Step 2: Run full verification**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```
Expected: PASS (or pre-existing unrelated failures only).

**Step 3: Fix only regressions introduced by this change**

If failures point to this feature, apply minimal corrections in:
- `Sources/VoiceFlowPro/Services/SpeechSegmenter.swift`
- `Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift`
- `Sources/VoiceFlowPro/Views/AICutView.swift`
- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`

**Step 4: Re-run verification**

Run the same command from Step 2.  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/SpeechSegmenter.swift Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift Sources/VoiceFlowPro/Services/AudioProcessor.swift Sources/VoiceFlowPro/Views/AICutView.swift Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift Sources/VoiceFlowProTests/Services/SpeechSegmenterTests.swift Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift Sources/VoiceFlowProTests/Services/AudioProcessorChunkTests.swift
git commit -m "fix: enforce segmented alignment pipeline for long audio accuracy" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
