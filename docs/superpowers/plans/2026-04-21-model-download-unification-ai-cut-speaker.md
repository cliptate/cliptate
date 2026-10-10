# Model Download Unification and Ai Cut Speaker Preservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify Parakeet with the existing MLXAudio download flow and preserve `speakerId` across Ai Cut segment processing so the existing UI shows speaker badges correctly when time display is enabled.

**Architecture:** Keep `ModelDownloadManager` as the single owner of model-directory resolution under the HuggingFace `mlx-audio` root, but collapse Parakeet into the same download dispatcher used by ASR, align, VAD, and TTS. Treat `speakerId` as stable segment metadata and forward it through every Ai Cut transform that rebuilds `Segment` values.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), Swift Package Manager, MLXAudio, HuggingFace cache utilities

---

## File map

### Existing files to modify

- `Package.swift:52-72` — register any newly added test file in the explicit `VoiceFlowProTests` source list.
- `Sources/VoiceFlowPro/Models/DataTypes.swift:313-328` — remove `isMLXAudioModel`; keep concrete capability helpers.
- `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift:89-373` — collapse Parakeet into `downloadMLXAudioModel`, remove `downloadParakeetModel`, keep directory handling unchanged.
- `Sources/VoiceFlowPro/Services/SegmentProcess.swift:49-124` — preserve `speakerId` in padding.
- `Sources/VoiceFlowPro/Services/SegmentSplit.swift:31-107` — preserve `speakerId` in the legacy split helper.
- `Sources/VoiceFlowPro/Services/SegmentSplitBySilence.swift:42-105` — preserve `speakerId` in silence-based splitting.
- `Sources/VoiceFlowPro/Services/SegmentSplitBySentence.swift:30-83` — preserve `speakerId` in sentence splitting.
- `Sources/VoiceFlowPro/Services/SegmentSplitByNatural.swift:117-193` — preserve `speakerId` in both word-based and char-ratio splits.
- `Sources/VoiceFlowPro/Services/SegmentCompression.swift:42-85` — preserve `speakerId` while remapping compressed time.
- `Sources/VoiceFlowPro/Services/FillerWordFilter.swift:14-25` — preserve `speakerId` when filtering text.
- `Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift:49-65` — preserve `speakerId` when biasing segment text.
- `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift` — add unified download-route and shared-root assertions.

### New file to create

- `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift` — focused TDD coverage for `speakerId` survival across Ai Cut transforms.

### Existing files to read during implementation

- `docs/superpowers/specs/2026-04-21-model-download-unification-ai-cut-speaker-design.md`
- `Sources/VoiceFlowPro/Views/AICutView.swift:2025-2080`
- `Sources/VoiceFlowPro/Views/SegmentsPanelView.swift:348-359`

### Task 1: Preserve `speakerId` in non-splitting Ai Cut transforms

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`
- Modify: `Package.swift:52-72`
- Modify: `Sources/VoiceFlowPro/Services/SegmentProcess.swift:49-124`
- Modify: `Sources/VoiceFlowPro/Services/SegmentCompression.swift:42-85`
- Modify: `Sources/VoiceFlowPro/Services/FillerWordFilter.swift:14-25`
- Modify: `Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift:49-65`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`

- [ ] **Step 1: Write the failing transform-preservation tests**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("Segment speaker propagation pipeline")
struct SegmentSpeakerPropagationPipelineTests {
  private let words = [
    WordTiming(word: "hello", startTime: 1.0, endTime: 1.3),
    WordTiming(word: "world", startTime: 1.4, endTime: 1.8)
  ]

  private var baseSegment: Segment {
    Segment(
      startTime: 1.0,
      endTime: 2.0,
      text: "hello world",
      words: words,
      confidence: 0.9,
      speakerId: 7
    )
  }

  @Test("padding keeps speakerId")
  func paddingKeepsSpeakerId() {
    let output = SegmentProcess.process(
      segments: [baseSegment],
      totalDuration: 10,
      operations: [.padding(leftMs: 100, rightMs: 150)]
    )
    #expect(output.count == 1)
    #expect(output[0].speakerId == 7)
  }

  @Test("compression keeps speakerId")
  func compressionKeepsSpeakerId() {
    let compression = SegmentCompressor.compress([baseSegment])
    #expect(compression.compressedSegments.count == 1)
    #expect(compression.compressedSegments[0].speakerId == 7)
  }

  @Test("filler filter keeps speakerId")
  @MainActor
  func fillerFilterKeepsSpeakerId() {
    let input = Segment(
      startTime: 0,
      endTime: 1,
      text: "um hello",
      words: nil,
      confidence: 0.5,
      speakerId: 7
    )
    let output = FillerWordFilter.filterSegments([input], fillerWords: ["um"])
    #expect(output.count == 1)
    #expect(output[0].speakerId == 7)
    #expect(output[0].text == "hello")
  }

  @Test("dictionary bias keeps speakerId")
  func dictionaryBiasKeepsSpeakerId() {
    let output = ASRDictionaryBiasService.apply(
      to: [Segment(startTime: 0, endTime: 1, text: "we use whisper cut pro", speakerId: 7)],
      dictionaryEntries: ["Whisper Cut Pro"]
    )
    #expect(output.count == 1)
    #expect(output[0].speakerId == 7)
    #expect(output[0].text == "we use Whisper Cut Pro")
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
.testTarget(
    name: "VoiceFlowProTests",
    dependencies: ["VoiceFlowPro"],
    path: "Sources/VoiceFlowProTests",
    sources: [
        "Services/ModelDownloadStateStoreTests.swift",
        "Services/ModelCacheManagerLanguageTests.swift",
        "Services/ModelCacheManagerLifecycleTests.swift",
        "Services/ModelDownloadManagerTests.swift",
        "Services/SegmentSpeakerPropagationPipelineTests.swift",
        "Services/SortformerVADSegmenterTests.swift",
        "Services/SegmentedAlignmentPipelineTests.swift",
        "Services/SpeechSegmenterTests.swift",
        "Services/MLXParakeetTranscriberTests.swift",
        "Services/Qwen3ASRTranscriberContextTests.swift",
        "Services/AudioProcessorChunkTests.swift",
        "Integration/ModelSelectionUIFlowTests.swift",
        "Integration/TranscriberPoolMigrationTests.swift",
        "Models/AppConfigurationModelLifecyclePersistenceTests.swift",
        "Models/SegmentTests.swift",
        "Models/ModelVariantTTSTests.swift"
    ],
```

- [ ] **Step 3: Run the new suite and verify it fails**

Run:

```bash
swift test --filter SegmentSpeakerPropagationPipelineTests
```

Expected: FAIL with at least one `#expect(...speakerId == 7)` assertion because the rebuilt `Segment` values currently drop `speakerId`.

- [ ] **Step 4: Write the minimal implementation to preserve `speakerId` in non-splitting transforms**

```swift
// Sources/VoiceFlowPro/Services/SegmentProcess.swift
adjusted.append(
  Segment(
    startTime: newStart,
    endTime: newEnd,
    text: base.text,
    words: base.words,
    confidence: base.confidence,
    speakerId: base.speakerId
  )
)

// Sources/VoiceFlowPro/Services/SegmentCompression.swift
compressed.append(
  Segment(
    startTime: compStart,
    endTime: compEnd,
    text: seg.text,
    words: shiftedWords,
    confidence: seg.confidence,
    speakerId: seg.speakerId
  )
)

// Sources/VoiceFlowPro/Services/FillerWordFilter.swift
return Segment(
  startTime: segment.startTime,
  endTime: segment.endTime,
  text: trimmed,
  words: segment.words,
  confidence: segment.confidence,
  speakerId: segment.speakerId
)

// Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift
Segment(
  startTime: segment.startTime,
  endTime: segment.endTime,
  text: apply(
    to: segment.text,
    dictionaryEntries: dictionaryEntries,
    maxCharacters: maxCharacters
  ),
  words: segment.words,
  confidence: segment.confidence,
  speakerId: segment.speakerId
)
```

- [ ] **Step 5: Run the suite again and verify it passes**

Run:

```bash
swift test --filter SegmentSpeakerPropagationPipelineTests
```

Expected: PASS for `padding keeps speakerId`, `compression keeps speakerId`, `filler filter keeps speakerId`, and `dictionary bias keeps speakerId`.

- [ ] **Step 6: Commit the passing non-splitting transform work**

```bash
git add Package.swift \
  Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift \
  Sources/VoiceFlowPro/Services/SegmentProcess.swift \
  Sources/VoiceFlowPro/Services/SegmentCompression.swift \
  Sources/VoiceFlowPro/Services/FillerWordFilter.swift \
  Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift
git commit -m $'test: preserve speaker ids in ai cut transforms\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 2: Preserve `speakerId` in split helpers used by Ai Cut

**Files:**
- Modify: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`
- Modify: `Sources/VoiceFlowPro/Services/SegmentSplit.swift:31-107`
- Modify: `Sources/VoiceFlowPro/Services/SegmentSplitBySilence.swift:42-105`
- Modify: `Sources/VoiceFlowPro/Services/SegmentSplitBySentence.swift:30-83`
- Modify: `Sources/VoiceFlowPro/Services/SegmentSplitByNatural.swift:117-193`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`

- [ ] **Step 1: Extend the test file with failing split-preservation tests**

```swift
extension SegmentSpeakerPropagationPipelineTests {
  @Test("silence split keeps speakerId on every emitted segment")
  func silenceSplitKeepsSpeakerId() {
    let input = Segment(
      startTime: 0,
      endTime: 2.2,
      text: "hello world again",
      words: [
        WordTiming(word: "hello", startTime: 0.0, endTime: 0.3),
        WordTiming(word: "world", startTime: 0.9, endTime: 1.2),
        WordTiming(word: "again", startTime: 1.3, endTime: 1.6)
      ],
      speakerId: 3
    )
    let output = SegmentSplitBySilence.apply(segments: [input], options: .init(splitThreshold: 0.4))
    #expect(output.count == 2)
    #expect(output.allSatisfy { $0.speakerId == 3 })
  }

  @Test("sentence split keeps speakerId on every emitted segment")
  func sentenceSplitKeepsSpeakerId() {
    let input = Segment(
      startTime: 0,
      endTime: 1.2,
      text: "Hello. World.",
      words: [
        WordTiming(word: "Hello", startTime: 0.0, endTime: 0.3, punctuation: "."),
        WordTiming(word: "World", startTime: 0.5, endTime: 0.9, punctuation: ".")
      ],
      speakerId: 3
    )
    let output = SegmentSplitBySentence.apply(segments: [input])
    #expect(output.count == 2)
    #expect(output.allSatisfy { $0.speakerId == 3 })
  }

  @Test("natural split keeps speakerId on both halves")
  func naturalSplitKeepsSpeakerId() {
    let input = Segment(
      startTime: 0,
      endTime: 6,
      text: "This is a long segment that should split naturally in half.",
      words: nil,
      speakerId: 3
    )
    let output = SegmentSplitByNatural.apply(segments: [input], options: .init(maxChars: 20))
    #expect(output.count > 1)
    #expect(output.allSatisfy { $0.speakerId == 3 })
  }

  @Test("legacy split helper keeps speakerId")
  func legacySplitKeepsSpeakerId() {
    let input = Segment(
      startTime: 0,
      endTime: 1.6,
      text: "hello world again",
      words: [
        WordTiming(word: "hello", startTime: 0.0, endTime: 0.2),
        WordTiming(word: "world", startTime: 0.8, endTime: 1.0),
        WordTiming(word: "again", startTime: 1.1, endTime: 1.4)
      ],
      speakerId: 3
    )
    let output = SegmentSplit.apply(segments: [input], options: .init(splitThreshold: 0.4))
    #expect(output.count == 2)
    #expect(output.allSatisfy { $0.speakerId == 3 })
  }
}
```

- [ ] **Step 2: Run the suite and verify the new split tests fail**

Run:

```bash
swift test --filter SegmentSpeakerPropagationPipelineTests
```

Expected: FAIL in the new split-related assertions because each helper currently rebuilds `Segment` without forwarding `speakerId`.

- [ ] **Step 3: Write the minimal implementation to preserve `speakerId` in split helpers**

```swift
// Sources/VoiceFlowPro/Services/SegmentSplit.swift
return Segment(
  startTime: startTime,
  endTime: endTime,
  text: text,
  words: words,
  confidence: original.confidence,
  speakerId: original.speakerId
)

// Sources/VoiceFlowPro/Services/SegmentSplitBySilence.swift
private static func emitSegment(
  from words: [WordTiming],
  into segments: inout [Segment],
  segmentConfidence: Float?,
  speakerId: Int?
) {
  segments.append(
    Segment(
      startTime: startTime,
      endTime: endTime,
      text: text,
      words: words,
      confidence: segmentConfidence,
      speakerId: speakerId
    )
  )
}

// call site
emitSegment(from: currentWords, into: &segments, segmentConfidence: segment.confidence, speakerId: segment.speakerId)

// Sources/VoiceFlowPro/Services/SegmentSplitBySentence.swift
private static func emitSegment(
  from words: [WordTiming],
  into segments: inout [Segment],
  segmentConfidence: Float?,
  speakerId: Int?
) {
  segments.append(
    Segment(
      startTime: startTime,
      endTime: endTime,
      text: text,
      words: words,
      confidence: segmentConfidence,
      speakerId: speakerId
    )
  )
}

// call site
emitSegment(from: currentWords, into: &segments, segmentConfidence: segment.confidence, speakerId: segment.speakerId)

// Sources/VoiceFlowPro/Services/SegmentSplitByNatural.swift
let s1 = Segment(
  startTime: firstWords.first!.startTime,
  endTime: firstWords.last!.endTime,
  text: WordTimingTextComposer.composeText(from: firstWords),
  words: firstWords,
  confidence: segment.confidence,
  speakerId: segment.speakerId
)
let s2 = Segment(
  startTime: secondWords.first!.startTime,
  endTime: secondWords.last!.endTime,
  text: WordTimingTextComposer.composeText(from: secondWords),
  words: secondWords,
  confidence: segment.confidence,
  speakerId: segment.speakerId
)

// char-ratio fallback path
let fallback1 = Segment(
  startTime: segment.startTime,
  endTime: splitTime,
  text: firstText,
  words: nil,
  confidence: segment.confidence,
  speakerId: segment.speakerId
)
let fallback2 = Segment(
  startTime: splitTime,
  endTime: segment.endTime,
  text: secondText,
  words: nil,
  confidence: segment.confidence,
  speakerId: segment.speakerId
)
return [fallback1, fallback2]
```

- [ ] **Step 4: Run the suite again and verify the split tests pass**

Run:

```bash
swift test --filter SegmentSpeakerPropagationPipelineTests
```

Expected: PASS for silence, sentence, natural, and legacy split propagation cases.

- [ ] **Step 5: Commit the split-helper preservation work**

```bash
git add Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift \
  Sources/VoiceFlowPro/Services/SegmentSplit.swift \
  Sources/VoiceFlowPro/Services/SegmentSplitBySilence.swift \
  Sources/VoiceFlowPro/Services/SegmentSplitBySentence.swift \
  Sources/VoiceFlowPro/Services/SegmentSplitByNatural.swift
git commit -m $'fix: preserve speaker ids in segment split helpers\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 3: Add failing tests for unified MLXAudio download routing

**Files:**
- Modify: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`

- [ ] **Step 1: Add route-selection and shared-root tests to `ModelDownloadManagerTests.swift`**

```swift
@Suite("ModelDownloadManager unified download routing")
struct ModelDownloadManagerUnifiedRoutingTests {
  @Test("Parakeet is routed through the unified MLXAudio downloader")
  func parakeetUsesUnifiedDownloader() {
    #expect(ModelDownloadManager.downloadBackend(for: .parakeetV3) == .resolver)
  }

  @Test("Qwen3 ASR keeps the dedicated ASR backend")
  func qwen3ASRUsesASRBackend() {
    #expect(ModelDownloadManager.downloadBackend(for: .qwen3ASR) == .qwen3ASR)
  }

  @Test("Qwen3 aligner keeps the aligner backend")
  func alignerUsesAlignerBackend() {
    #expect(ModelDownloadManager.downloadBackend(for: .qwen3ForcedAligner) == .qwen3Aligner)
  }

  @Test("Sortformer keeps the VAD backend")
  func sortformerUsesVADBackend() {
    #expect(ModelDownloadManager.downloadBackend(for: .sortformerOffline) == .sortformerVAD)
  }

  @Test("TTS uses the resolver backend")
  func ttsUsesResolverBackend() {
    #expect(ModelDownloadManager.downloadBackend(for: .qwen3TTS06B4bit) == .resolver)
  }

  @Test("Parakeet and TTS directories share the mlx-audio root")
  func parakeetAndTTSShareMLXAudioRoot() {
    let env: [String: String] = [:]
    let home = URL(fileURLWithPath: "/mock/home", isDirectory: true)
    let caches = URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
    let parakeet = ModelDownloadManager.mlxAudioDirectory(
      forRepo: ModelVariant.parakeetV3.huggingFaceRepoId,
      environment: env,
      homeDirectory: home,
      cachesDirectory: caches
    )
    let tts = ModelDownloadManager.mlxAudioDirectory(
      forRepo: ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId,
      environment: env,
      homeDirectory: home,
      cachesDirectory: caches
    )

    #expect(parakeet.deletingLastPathComponent() == tts.deletingLastPathComponent())
    #expect(parakeet.path.contains("/mlx-audio/"))
    #expect(tts.path.contains("/mlx-audio/"))
  }
}
```

- [ ] **Step 2: Run the download-manager tests and verify they fail**

Run:

```bash
swift test --filter ModelDownloadManagerUnifiedRoutingTests
```

Expected: FAIL with compile errors first because `downloadBackend(for:)` and its enum do not exist yet.

- [ ] **Step 3: Implement the minimal routing seam and keep all models under the same root**

```swift
// Sources/VoiceFlowPro/Services/ModelDownloadManager.swift
extension ModelDownloadManager {
  enum DownloadBackend: Equatable {
    case resolver
    case qwen3ASR
    case qwen3Aligner
    case sortformerVAD
  }

  nonisolated static func downloadBackend(for model: ModelVariant) -> DownloadBackend? {
    if model.isParakeetModel || model.isTTSModel { return .resolver }
    if model.isQwen3ASRModel { return .qwen3ASR }
    if model.isQwen3AlignerModel { return .qwen3Aligner }
    if model.isSortformerVADModel { return .sortformerVAD }
    return nil
  }
}

func download(
  model: ModelVariant,
  progressHandler: @escaping @Sendable (ModelDownloadProgress) async -> Void
) async throws {
  if let existing = activeDownloads[model] {
    try await existing.value
    return
  }

  try await ensureDownloadPermitted(for: model)

  let task = Task {
    guard Self.downloadBackend(for: model) != nil else {
      await progressHandler(ModelDownloadProgress(currentStep: "Unsupported model type", progress: 0.0))
      return
    }
    try await self.downloadMLXAudioModel(model, progressHandler: progressHandler)
  }

  activeDownloads[model] = task
  defer { activeDownloads[model] = nil }
  try await task.value
}
```

- [ ] **Step 4: Run the routing tests again and verify they pass**

Run:

```bash
swift test --filter ModelDownloadManagerUnifiedRoutingTests
```

Expected: PASS for Parakeet, ASR, aligner, Sortformer, and TTS routing plus shared-root assertions.

- [ ] **Step 5: Commit the routing-test seam**

```bash
git add Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift \
  Sources/VoiceFlowPro/Services/ModelDownloadManager.swift
git commit -m $'test: cover unified mlx audio download routing\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 4: Remove the obsolete Parakeet branch and `isMLXAudioModel`

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift:313-328`
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift:89-373`
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`

- [ ] **Step 1: Remove `isMLXAudioModel` from `ModelVariant`**

```swift
// Delete this computed property entirely from Sources/VoiceFlowPro/Models/DataTypes.swift
var isMLXAudioModel: Bool {
  isQwen3Model || isSortformerVADModel || isTTSModel
}
```

- [ ] **Step 2: Delete `downloadParakeetModel` and fold Parakeet into `downloadMLXAudioModel`**

```swift
// Sources/VoiceFlowPro/Services/ModelDownloadManager.swift
let activeDownloadTask: Task<Void, Error> = Task {
  try Task.checkCancellation()
  switch Self.downloadBackend(for: model) {
  case .resolver:
    _ = try await ModelUtils.resolveOrDownloadModel(
      repoID: .init(rawValue: model.huggingFaceRepoId)!,
      requiredExtension: "safetensors"
    )
  case .qwen3Aligner:
    _ = try await Qwen3ForcedAlignerModel.fromPretrained(model.huggingFaceRepoId)
  case .sortformerVAD:
    _ = try await SortformerModel.fromPretrained(model.huggingFaceRepoId)
  case .qwen3ASR:
    _ = try await Qwen3ASRModel.fromPretrained(model.huggingFaceRepoId)
  case nil:
    throw NSError(
      domain: "ModelDownloadManager",
      code: -11,
      userInfo: [NSLocalizedDescriptionKey: "Unsupported model type: \(model.rawValue)"]
    )
  }
}
```

- [ ] **Step 3: Run the focused download-manager tests**

Run:

```bash
swift test --filter ModelDownloadManager
```

Expected: PASS for the existing path-resolution and artifact checks plus the new unified-routing suite.

- [ ] **Step 4: Run the speaker-propagation suite one more time to catch accidental regressions**

Run:

```bash
swift test --filter SegmentSpeakerPropagationPipelineTests
```

Expected: PASS.

- [ ] **Step 5: Commit the final implementation**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift \
  Sources/VoiceFlowPro/Services/ModelDownloadManager.swift
git commit -m $'feat: unify model downloads and preserve ai cut speaker ids\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 5: Final regression pass

**Files:**
- Modify: none
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/SortformerVADSegmenterTests.swift`

- [ ] **Step 1: Run the exact suites touched by this feature**

Run:

```bash
swift test --filter ModelDownloadManager
swift test --filter SegmentSpeakerPropagationPipelineTests
swift test --filter ASRDictionaryBiasServiceTests
swift test --filter SortformerVADSegmenterTests
```

Expected: PASS in all four commands.

- [ ] **Step 2: Run the full package test suite**

Run:

```bash
swift test
```

Expected: PASS for `VoiceFlowProTests`.

- [ ] **Step 3: Verify the working tree is clean except for intentional implementation commits**

Run:

```bash
git --no-pager status --short
```

Expected: no unexpected modified files; only intentional committed changes should remain.
