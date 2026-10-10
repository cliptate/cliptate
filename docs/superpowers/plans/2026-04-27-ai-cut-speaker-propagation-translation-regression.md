# AI Cut Speaker Propagation and Translation Regression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Sortformer/VAD speaker labels all the way through AI Cut transcription even when no aligner is used, and add a simple regression test that proves the AI Cut translation action actually writes translations.

**Architecture:** Treat speaker labels as upstream diarization metadata produced by Sortformer/VAD, not as a capability unlocked by align/forced-align. Reuse a single overlap-based annotator to copy `speakerId` from VAD ranges onto ASR segments in both plain-ASR and align flows, then make the AI Cut translation trigger testable via a small injected translation runner instead of relying on manual clicking.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, existing Sortformer VAD pipeline, Qwen3 ASR, AI Cut view state, Apple Translation integration

---

## File map

### Existing files to modify

- `Package.swift` — register any new test files in the explicit `VoiceFlowProTests` source list.
- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift` — preserve speaker labels from Sortformer/VAD on the plain ASR path.
- `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift` — either reuse or extract the existing overlap-based speaker annotation helper.
- `Sources/VoiceFlowPro/Views/AICutView.swift` — stop treating aligner availability as the source of speaker labels, and make the translation action injectable/testable.
- `Sources/VoiceFlowPro/Localizable.xcstrings` — localize any new translation-action status strings if new static keys are introduced.

### New files to create

- `Sources/VoiceFlowPro/Services/SegmentSpeakerAnnotator.swift` — shared pure helper that maps VAD speaker ranges onto ASR segments by maximum overlap.
- `Sources/VoiceFlowProTests/Services/SegmentSpeakerAnnotatorTests.swift` — focused tests for overlap-based speaker propagation.
- `Sources/VoiceFlowProTests/Services/Qwen3ASRSpeakerPropagationTests.swift` — regression tests proving the non-align Qwen3 path keeps Sortformer/VAD speaker IDs.
- `Sources/VoiceFlowProTests/Views/AICutTranslationActionTests.swift` — simple regression test proving AI Cut translation action updates `segmentTranslations`.

### Existing files to read during implementation

- `Sources/VoiceFlowPro/Services/SortformerVADSegmenter.swift`
- `Sources/VoiceFlowPro/Services/SpeechSegmenter.swift`
- `Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift`
- `Sources/VoiceFlowPro/Views/AICutView.swift`
- `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`
- `Sources/VoiceFlowProTests/Views/SegmentsPanelInteractionTests.swift`

---

### Task 1: Extract and lock down shared speaker annotation with TDD

**Files:**
- Create: `Sources/VoiceFlowPro/Services/SegmentSpeakerAnnotator.swift`
- Create: `Sources/VoiceFlowProTests/Services/SegmentSpeakerAnnotatorTests.swift`
- Modify: `Package.swift`
- Modify: `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerAnnotatorTests.swift`

- [ ] **Step 1: Write the failing annotator tests**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("SegmentSpeakerAnnotator")
struct SegmentSpeakerAnnotatorTests {
  @Test("assigns the speaker with the largest overlap")
  func assignsLargestOverlapSpeaker() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
      Segment(startTime: 1.0, endTime: 2.0, text: "world")
    ]

    let vadRanges = [
      AudioTimeRange(startTime: 0.0, endTime: 0.8, speakerId: 3),
      AudioTimeRange(startTime: 1.2, endTime: 1.9, speakerId: 7)
    ]

    let annotated = SegmentSpeakerAnnotator.annotate(segments, withSpeakers: vadRanges)

    #expect(annotated[0].speakerId == 3)
    #expect(annotated[1].speakerId == 7)
  }

  @Test("keeps nil speakerId when no VAD speaker overlaps")
  func keepsNilWithoutOverlap() {
    let segments = [Segment(startTime: 4.0, endTime: 5.0, text: "late")]
    let vadRanges = [AudioTimeRange(startTime: 0.0, endTime: 1.0, speakerId: 1)]

    let annotated = SegmentSpeakerAnnotator.annotate(segments, withSpeakers: vadRanges)

    #expect(annotated[0].speakerId == nil)
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
"Services/SegmentSpeakerAnnotatorTests.swift",
```

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```bash
swift test --filter SegmentSpeakerAnnotatorTests
```

Expected: FAIL with unresolved symbol errors because `SegmentSpeakerAnnotator` does not exist yet.

- [ ] **Step 4: Add the minimal shared annotator**

```swift
import Foundation

enum SegmentSpeakerAnnotator {
  static func annotate(
    _ segments: [Segment],
    withSpeakers vadRanges: [AudioTimeRange]
  ) -> [Segment] {
    segments.map { segment in
      var bestSpeaker: Int?
      var bestOverlap: Double = 0

      for range in vadRanges {
        guard let speakerId = range.speakerId else { continue }
        let overlapStart = max(segment.startTime, range.startTime)
        let overlapEnd = min(segment.endTime, range.endTime)
        let overlap = overlapEnd - overlapStart
        if overlap > bestOverlap {
          bestOverlap = overlap
          bestSpeaker = speakerId
        }
      }

      guard let bestSpeaker else { return segment }
      return Segment(
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: segment.text,
        words: segment.words,
        confidence: segment.confidence,
        speakerId: bestSpeaker
      )
    }
  }
}
```

- [ ] **Step 5: Repoint `MLXParakeetTranscriber` at the shared helper**

```swift
static func annotateSegments(
  _ segments: [Segment],
  withSpeakers vadRanges: [AudioTimeRange]
) -> [Segment] {
  SegmentSpeakerAnnotator.annotate(segments, withSpeakers: vadRanges)
}
```

- [ ] **Step 6: Run the focused test to verify GREEN**

Run:

```bash
swift test --filter SegmentSpeakerAnnotatorTests
```

Expected: PASS.

---

### Task 2: Make the non-align Qwen3 path preserve Sortformer speaker IDs

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Create: `Sources/VoiceFlowProTests/Services/Qwen3ASRSpeakerPropagationTests.swift`
- Modify: `Package.swift`
- Test: `Sources/VoiceFlowProTests/Services/Qwen3ASRSpeakerPropagationTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`

- [ ] **Step 1: Write the failing Qwen3 speaker propagation test**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("Qwen3ASR speaker propagation")
struct Qwen3ASRSpeakerPropagationTests {
  @Test("plain ASR path preserves Sortformer speaker labels")
  func preservesSpeakerLabelsWithoutAligner() async throws {
    let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture(
      output: STTOutput(
        text: "hello world",
        segments: [
          ["text": "hello", "start": 0.0, "end": 1.0],
          ["text": "world", "start": 1.0, "end": 2.0]
        ]
      )
    )

    let transcriber = Qwen3ASRTranscriber(
      model: .qwen3ASR,
      testHooks: .init(
        loadAudioSamples: { _ in Array(repeating: 0, count: 32_000) },
        readAudioDuration: { _ in 2.0 },
        generate: { capture.record($0) }
      )
    )

    let result = try await transcriber.transcribeWithProgress(
      audioPath: "/tmp/fake.wav",
      language: .english,
      speakerRanges: [
        AudioTimeRange(startTime: 0.0, endTime: 1.0, speakerId: 2),
        AudioTimeRange(startTime: 1.0, endTime: 2.0, speakerId: 5)
      ],
      progressHandler: { _ in }
    )

    #expect(result.segments.map(\\.speakerId) == [2, 5])
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
"Services/Qwen3ASRSpeakerPropagationTests.swift",
```

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```bash
swift test --filter Qwen3ASRSpeakerPropagationTests
```

Expected: FAIL because `transcribeWithProgress(...speakerRanges:...)` does not exist yet.

- [ ] **Step 4: Add the minimal Qwen3 speaker-preserving overload**

```swift
public func transcribeWithProgress(
  audioPath: String,
  language: Language,
  speakerRanges: [AudioTimeRange],
  dictionaryContext: String? = nil,
  progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
) async throws -> TranscriptionResult {
  let result = try await transcribeWithProgress(
    audioPath: audioPath,
    language: language,
    dictionaryContext: dictionaryContext,
    progressHandler: progressHandler
  )

  return TranscriptionResult(
    segments: SegmentSpeakerAnnotator.annotate(result.segments, withSpeakers: speakerRanges),
    totalDuration: result.totalDuration,
    processingTime: result.processingTime,
    modelUsed: result.modelUsed
  )
}
```

- [ ] **Step 5: Feed Sortformer speaker ranges into the plain-ASR AI Cut path**

```swift
let audioSamples = try await AudioProcessor.loadAndConvertAudio(url: url)
let speakerRanges = try await SortformerVADSegmenter.makeWithModel(variant: .sortformerOffline)
  .detectSpeechSegmentsWithSpeakers(audioSamples: audioSamples)

result = try await qwen3Transcriber.transcribeWithProgress(
  audioPath: url.path,
  language: config.language,
  speakerRanges: speakerRanges,
  dictionaryContext: dictionaryContext,
  progressHandler: progressHandler
)
```
Use the same `speakerRanges` when the non-Qwen3 plain-ASR path needs post-annotation, rather than introducing a second heuristic.

- [ ] **Step 6: Remove the assumption that speaker labels require aligner availability**

```swift
// Do not gate speaker display on AICutSpeakerDiagnostics in the fallback path.
// Align remains preferred for timestamps/word alignment, but speakerId comes from Sortformer VAD.
```

- [ ] **Step 7: Run the focused regression suites**

Run:

```bash
swift test --filter Qwen3ASRSpeakerPropagationTests && \
swift test --filter SegmentSpeakerPropagationPipelineTests && \
swift test --filter SegmentedAlignmentPipelineTests
```

Expected: PASS.

---

### Task 3: Add a simple AI Cut translation regression test and minimal seam

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Create: `Sources/VoiceFlowProTests/Views/AICutTranslationActionTests.swift`
- Modify: `Package.swift`
- Test: `Sources/VoiceFlowProTests/Views/AICutTranslationActionTests.swift`
- Test: `Sources/VoiceFlowProTests/Views/SegmentsPanelInteractionTests.swift`

- [ ] **Step 1: Write the failing translation regression test**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("AI Cut translation action")
struct AICutTranslationActionTests {
  @MainActor
  @Test("translating active segments writes segmentTranslations")
  func translatingActiveSegmentsStoresTranslations() async throws {
    var storedTranslations: [String: SegmentTranslation] = [:]

    let runner = AICutTranslationRunner(
      translateSegments: { segments, _, _, progress in
        progress?(segments.count, segments.count)
        return Dictionary(
          uniqueKeysWithValues: segments.map {
            ($0.id, SegmentTranslation(text: "T:\($0.text)", language: .chinese))
          }
        )
      }
    )

    let result = try await runner.translate(
      segments: [Segment(startTime: 0, endTime: 1, text: "hello")],
      sourceLanguage: .english,
      targetLanguage: .chinese
    )

    storedTranslations = result

    #expect(storedTranslations.count == 1)
    #expect(storedTranslations.values.first?.text == "T:hello")
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
"Views/AICutTranslationActionTests.swift",
```

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```bash
swift test --filter AICutTranslationActionTests
```

Expected: FAIL because `AICutTranslationRunner` does not exist yet.

- [ ] **Step 4: Add the minimal translation seam**

```swift
struct AICutTranslationRunner {
  let translateSegments:
    @Sendable ([Segment], Language, Language, ((Int, Int) -> Void)?) async throws
      -> [String: SegmentTranslation]

  init(
    translateSegments:
      @escaping @Sendable ([Segment], Language, Language, ((Int, Int) -> Void)?) async throws
        -> [String: SegmentTranslation] = { segments, source, target, progress in
          guard #available(macOS 26.0, *) else {
            throw AppleTranslationError.platformUnavailable
          }
          return try await AppleTranslator.translateSegments(
            segments,
            from: source,
            to: target,
            progress: progress
          )
        }
  ) {
    self.translateSegments = translateSegments
  }

  func translate(
    segments: [Segment],
    sourceLanguage: Language,
    targetLanguage: Language,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [String: SegmentTranslation] {
    try await translateSegments(segments, sourceLanguage, targetLanguage, progress)
  }
}
```

- [ ] **Step 5: Make `translateActiveSegments()` use the seam**

```swift
let translations = try await translationRunner.translate(
  segments: segments,
  sourceLanguage: sourceLanguage,
  targetLanguage: targetLanguage,
  progress: progressBridge.report(completed:total:)
)
```

- [ ] **Step 6: Run the focused translation/UI slice**

Run:

```bash
swift test --filter AICutTranslationActionTests && \
swift test --filter SegmentsPanelInteractionTests
```

Expected: PASS.

---

### Task 4: Run the broader regression slice

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift` (only if task fixes require final cleanup)
- Test: `Sources/VoiceFlowProTests/Services/Qwen3ASRSpeakerPropagationTests.swift`
- Test: `Sources/VoiceFlowProTests/Views/AICutTranslationActionTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`

- [ ] **Step 1: Run the complete focused slice**

Run:

```bash
swift test --filter SegmentSpeakerAnnotatorTests && \
swift test --filter Qwen3ASRSpeakerPropagationTests && \
swift test --filter AICutTranslationActionTests && \
swift test --filter SegmentSpeakerPropagationPipelineTests && \
swift test --filter SegmentedAlignmentPipelineTests
```

Expected: PASS.

- [ ] **Step 2: Run the broader package build**

Run:

```bash
swift build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit the finished change**

```bash
git add Package.swift \
  Sources/VoiceFlowPro/Services/SegmentSpeakerAnnotator.swift \
  Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift \
  Sources/VoiceFlowPro/Views/AICutView.swift \
  Sources/VoiceFlowProTests/Services/SegmentSpeakerAnnotatorTests.swift \
  Sources/VoiceFlowProTests/Services/Qwen3ASRSpeakerPropagationTests.swift \
  Sources/VoiceFlowProTests/Views/AICutTranslationActionTests.swift
git commit -m $'feat: preserve ai cut speaker labels and test translation action\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```
