# VAD+ASR Per-Segment Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor `transcribeWithAlignment` in `Qwen3ASRTranscriber` so forced alignment is performed per ASR segment (on the exact audio slice) rather than on the whole audio with concatenated text.

**Architecture:** Phase 1 (ASR) is unchanged — it produces `[Segment]` with absolute timestamps. Phase 2 replaces the single whole-audio `alignWithText` call with a per-segment loop: slice audio samples, call a new private `alignSamples` helper, rebase timestamps, and emit one `Segment` per ASR segment. The `rebuildAlignedSegments` heuristic and its unused tokenization helpers are deleted.

**Tech Stack:** Swift, MLXAudioSTT (`ForcedAlignerModel.generate`), `AudioProcessor.extractSamples`, `WordTimingTextComposer`

---

### Task 1: Add `alignSamples` private helper and unit-test the rebasing logic

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- Create: `Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift`

**Context:**  
`alignSamples` wraps `alignerModel.generate(audio:text:language:)` at the sample level. The rebasing logic (word.startTime += asrSegment.startTime) is the critical correctness invariant. Since `Qwen3ASRTranscriber` uses real MLX models that can't be instantiated in unit tests, the rebasing and reconstruction logic is tested via a pure free function `buildAlignedSegment` extracted at module scope.

**Step 1: Write the failing test**

Create `Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceFlowPro

@Suite("Qwen3 Per-Segment Alignment")
struct Qwen3PerSegmentAlignTests {

  // Tests the rebasing helper that turns local word timings into global-timeline segments.
  @Test("rebases local word timings by segment offset")
  func rebasesWordTimingsBySegmentOffset() {
    let asrSegment = Segment(
      startTime: 10.0,
      endTime: 13.0,
      text: "hello world",
      words: nil,
      confidence: nil
    )
    // Local words: times relative to segment audio start (0-based)
    let localWords = [
      WordTiming(word: "hello", startTime: 0.1, endTime: 0.5, confidence: nil, punctuation: ""),
      WordTiming(word: "world", startTime: 0.6, endTime: 1.0, confidence: nil, punctuation: ""),
    ]

    let result = Qwen3ASRTranscriber.rebaseAndBuildSegment(
      asrSegment: asrSegment,
      localWords: localWords
    )

    #expect(result != nil)
    #expect(result?.startTime == 10.1)
    #expect(result?.endTime == 11.0)
    #expect(result?.words?.count == 2)
    #expect(result?.words?[0].startTime == 10.1)
    #expect(result?.words?[1].startTime == 10.6)
  }

  @Test("returns nil for empty word timings")
  func returnsNilForEmptyWords() {
    let asrSegment = Segment(
      startTime: 5.0, endTime: 8.0, text: "silence", words: nil, confidence: nil)
    let result = Qwen3ASRTranscriber.rebaseAndBuildSegment(
      asrSegment: asrSegment,
      localWords: []
    )
    #expect(result == nil)
  }

  @Test("preserves original ASR segment confidence in output segment")
  func preservesConfidence() {
    let asrSegment = Segment(
      startTime: 0.0, endTime: 2.0, text: "hi", words: nil, confidence: 0.9)
    let localWords = [
      WordTiming(word: "hi", startTime: 0.1, endTime: 0.4, confidence: nil, punctuation: ""),
    ]
    let result = Qwen3ASRTranscriber.rebaseAndBuildSegment(
      asrSegment: asrSegment,
      localWords: localWords
    )
    #expect(result?.confidence == 0.9)
  }
}
```

**Step 2: Run tests to verify they fail**

```bash
xcodebuild test \
  -project Sources/VoiceFlowPro.xcodeproj \
  -scheme VoicePinkPro \
  -destination 'platform=macOS' \
  -only-testing:VoiceFlowProTests/Qwen3PerSegmentAlignTests \
  -parallel-testing-enabled NO 2>&1 | tail -20
```

Expected: compile error — `Qwen3ASRTranscriber.rebaseAndBuildSegment` does not exist.

**Step 3: Add `rebaseAndBuildSegment` static method to `Qwen3ASRTranscriber`**

Add inside the `Qwen3ASRTranscriber` class (near the MARK: - Alignment Reconstruction section):

```swift
// MARK: - Per-Segment Alignment Helpers

/// Rebases local (0-based) word timings from a segment audio slice to global timeline
/// and builds a Segment. Returns nil if localWords is empty.
static func rebaseAndBuildSegment(
  asrSegment: Segment,
  localWords: [WordTiming]
) -> Segment? {
  guard !localWords.isEmpty else { return nil }
  let rebased = localWords.map { word in
    WordTiming(
      word: word.word,
      startTime: asrSegment.startTime + word.startTime,
      endTime: asrSegment.startTime + word.endTime,
      confidence: word.confidence,
      punctuation: word.punctuation
    )
  }
  guard let first = rebased.first, let last = rebased.last else { return nil }
  let text = WordTimingTextComposer.composeText(from: rebased)
  return Segment(
    startTime: first.startTime,
    endTime: last.endTime,
    text: text.isEmpty ? asrSegment.text : text,
    words: rebased,
    confidence: asrSegment.confidence
  )
}
```

**Step 4: Add `alignSamples` private helper**

Add inside `Qwen3ASRTranscriber` (below `rebaseAndBuildSegment`):

```swift
/// Aligns audio samples against known text. Samples must be 16kHz [Float].
/// Returns local (0-based) word timings.
private func alignSamples(
  _ samples: [Float],
  text: String,
  language: Language
) throws -> [WordTiming] {
  guard let alignerModel else {
    throw NSError(
      domain: "Qwen3ASR", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "ForcedAligner model not initialized."])
  }
  let audioArray = MLXArray(samples)
  let languageName = language.qwen3LanguageName
  let result = alignerModel.generate(audio: audioArray, text: text, language: languageName)
  return result.items.map { item in
    WordTiming(word: item.text, startTime: item.startTime, endTime: item.endTime, confidence: nil)
  }
}
```

**Step 5: Run tests to verify they pass**

```bash
xcodebuild test \
  -project Sources/VoiceFlowPro.xcodeproj \
  -scheme VoicePinkPro \
  -destination 'platform=macOS' \
  -only-testing:VoiceFlowProTests/Qwen3PerSegmentAlignTests \
  -parallel-testing-enabled NO 2>&1 | tail -20
```

Expected: All 3 tests PASS.

**Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift \
        Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift
git commit -m "feat: add rebaseAndBuildSegment + alignSamples helpers to Qwen3ASRTranscriber"
```

---

### Task 2: Refactor `transcribeWithAlignment` to use per-segment alignment

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`

**Context:**  
Replace the current Phase 2 (single `alignWithText(fullAudio, fullText)` + `rebuildAlignedSegments`) with a loop over `asrResult.segments`. Load `audioSamples` once near the top of `transcribeWithAlignment` (before Phase 1) so they are available for slicing in Phase 2. Use `AudioProcessor.extractSamples` for slicing. Apply `applyPunctuation` after rebasing.

**Step 1: Load audio samples before Phase 1 ASR**

In `transcribeWithAlignment`, after the security-scoped resource access and duration loading (around line 526), add audio sample loading. Currently this method does NOT load samples (only `asrTranscriber` does internally). Add:

```swift
let audioSamples = try await AudioProcessor.loadAndConvertAudioForFluidAudio(
  url: URL(fileURLWithPath: audioPath))
try Task.checkCancellation()
```

Place this after the `let startTime = Date()` line and before the Phase 1 progress report.

**Step 2: Replace Phase 2 body**

Find the current Phase 2 block (from `// Phase 2: Forced alignment` to the `rebuildAlignedSegments` call and `return`) and replace it entirely:

OLD Phase 2 code to remove:
```swift
// Phase 2: Forced alignment
Task { @MainActor in
  progressHandler(
    TranscriptionProgress(
      currentSegments: asrResult.segments,
      progress: 0.45,
      statusMessage: "Phase 2: Aligning timestamps...",
      estimatedTimeRemaining: nil
    ))
}

let alignedResult = try await alignWithText(
  audioPath: audioPath,
  text: fullText,
  language: language
) { progress in
  // Scale alignment progress to 45-100%
  let scaledProgress = 0.45 + (progress.progress * 0.55)
  Task { @MainActor in
    progressHandler(
      TranscriptionProgress(
        currentSegments: progress.currentSegments,
        progress: scaledProgress,
        statusMessage: "Phase 2: \(progress.statusMessage)",
        estimatedTimeRemaining: progress.estimatedTimeRemaining
      ))
  }
}

let rebuiltSegments = rebuildAlignedSegments(
  asrSegments: asrResult.segments,
  alignedSegments: alignedResult.segments,
  language: language
)
let finalSegments = rebuiltSegments.isEmpty ? alignedResult.segments : rebuiltSegments

let totalTime = Date().timeIntervalSince(startTime)

logger.notice(
  "🤖 Two-phase transcription complete: \(finalSegments.count) segments in \(String(format: "%.1f", totalTime))s"
)

return TranscriptionResult(
  segments: finalSegments,
  totalDuration: alignedResult.totalDuration,
  processingTime: totalTime,
  modelUsed: "\(asrTranscriber.model.rawValue) + \(modelVariant.rawValue)"
)
```

NEW Phase 2 code:
```swift
// Phase 2: Per-segment forced alignment
logger.notice("🤖 Phase 2: aligning \(asrResult.segments.count) ASR segments individually")

var alignedSegments: [Segment] = []
alignedSegments.reserveCapacity(asrResult.segments.count)

for (index, asrSegment) in asrResult.segments.enumerated() {
  try Task.checkCancellation()

  let segmentText = asrSegment.text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !segmentText.isEmpty else { continue }

  let alignProgress = Float(0.45) + Float(index) / Float(asrResult.segments.count) * Float(0.54)
  Task { @MainActor in
    progressHandler(
      TranscriptionProgress(
        currentSegments: alignedSegments,
        progress: alignProgress,
        statusMessage: "Phase 2: Align \(index + 1)/\(asrResult.segments.count)",
        estimatedTimeRemaining: nil
      ))
  }

  let segmentSamples = AudioProcessor.extractSamples(
    samples: audioSamples,
    startTime: asrSegment.startTime,
    endTime: asrSegment.endTime
  )
  guard !segmentSamples.isEmpty else { continue }

  let localWords = try alignSamples(segmentSamples, text: segmentText, language: language)
  let punctuatedLocal = applyPunctuation(from: segmentText, to: localWords)

  if let seg = Self.rebaseAndBuildSegment(asrSegment: asrSegment, localWords: punctuatedLocal) {
    alignedSegments.append(seg)
  }
}

let totalTime = Date().timeIntervalSince(startTime)
logger.notice(
  "🤖 Per-segment alignment complete: \(alignedSegments.count) segments in \(String(format: "%.1f", totalTime))s"
)

Task { @MainActor in
  progressHandler(
    TranscriptionProgress(
      currentSegments: alignedSegments,
      progress: 1.0,
      statusMessage: "Alignment completed",
      estimatedTimeRemaining: 0
    ))
}

return TranscriptionResult(
  segments: alignedSegments,
  totalDuration: asrResult.totalDuration,
  processingTime: totalTime,
  modelUsed: "\(asrTranscriber.model.rawValue) + \(modelVariant.rawValue)"
)
```

**Step 3: Remove fullText extraction (no longer needed)**

Remove the lines that extract and join text (they appear between Phase 1 and Phase 2):

```swift
// Extract full text from ASR result
let fullText = asrResult.segments.map { $0.text }.joined(separator: " ")
  .trimmingCharacters(in: .whitespacesAndNewlines)

guard !fullText.isEmpty else {
  logger.warning("🤖 ASR produced no text, returning empty result")
  return TranscriptionResult(
    segments: [],
    totalDuration: asrResult.totalDuration,
    processingTime: Date().timeIntervalSince(startTime),
    modelUsed: "\(asrTranscriber.model.rawValue) + \(modelVariant.rawValue)"
  )
}

logger.notice("🤖 Phase 1 complete. ASR text: \(fullText.prefix(100))...")
```

Replace with:
```swift
guard !asrResult.segments.isEmpty else {
  logger.warning("🤖 ASR produced no segments, returning empty result")
  return TranscriptionResult(
    segments: [],
    totalDuration: asrResult.totalDuration,
    processingTime: Date().timeIntervalSince(startTime),
    modelUsed: "\(asrTranscriber.model.rawValue) + \(modelVariant.rawValue)"
  )
}
logger.notice("🤖 Phase 1 complete: \(asrResult.segments.count) segments")
```

**Step 4: Build the project to verify it compiles**

```bash
xcodebuild build \
  -project Sources/VoiceFlowPro.xcodeproj \
  -scheme VoicePinkPro \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift
git commit -m "refactor: use per-segment alignment in transcribeWithAlignment"
```

---

### Task 3: Delete `rebuildAlignedSegments` and its dead helper code

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`

**Context:**  
`rebuildAlignedSegments` and the tokenization helpers it depends on (`alignmentTokens`, `tokenizeChineseMixed`, `tokenizeSpaceLanguage`, `splitSegmentWithChinese`, `cleanAlignmentToken`) are now unused. `isAlignmentSignificantCharacter` and `isKeptAlignmentCharacter` are still used by `applyPunctuation` — keep those. `isCJKCharacter` is used in both — keep it.

**Step 1: Delete `rebuildAlignedSegments` and its dependent tokenization helpers**

Remove the following private methods from `Qwen3ASRTranscriber`:
- `rebuildAlignedSegments(asrSegments:alignedSegments:language:)` — entire function
- `alignmentTokens(from:language:)` — entire function
- `tokenizeChineseMixed(_:)` — entire function
- `tokenizeSpaceLanguage(_:)` — entire function
- `splitSegmentWithChinese(_:)` — entire function
- `cleanAlignmentToken(_:)` — entire function

Keep:
- `applyPunctuation(from:to:)` — still used in per-segment alignment
- `isAlignmentSignificantCharacter(_:)` — used in `applyPunctuation`
- `isKeptAlignmentCharacter(_:)` — used in `applyPunctuation` and `isAlignmentSignificantCharacter`
- `isCJKCharacter(_:)` — used in `applyPunctuation` and `isKeptAlignmentCharacter`

**Step 2: Build to verify no compile errors**

```bash
xcodebuild build \
  -project Sources/VoiceFlowPro.xcodeproj \
  -scheme VoicePinkPro \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 3: Run all tests to verify no regressions**

```bash
xcodebuild test \
  -project Sources/VoiceFlowPro.xcodeproj \
  -scheme VoicePinkPro \
  -destination 'platform=macOS' \
  -only-testing:VoiceFlowProTests \
  -parallel-testing-enabled NO 2>&1 | tail -30
```

Expected: All existing tests pass, plus the 3 new `Qwen3PerSegmentAlignTests` pass.

**Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift
git commit -m "refactor: remove rebuildAlignedSegments and dead tokenization helpers"
```

---

### Task 4: Add edge-case tests for per-segment alignment loop behavior

**Files:**
- Modify: `Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift`

**Context:**  
Test edge cases: empty-text segments are skipped, empty-sample segments are skipped, multiple segments produce monotonic timestamps.

**Step 1: Add tests**

Append to `Qwen3PerSegmentAlignTests`:

```swift
@Test("multiple segments produce monotonically increasing start times after rebasing")
func multipleSegmentsMonotonicTimestamps() {
  let segments = [
    Segment(startTime: 0.0, endTime: 2.0, text: "hello", words: nil, confidence: nil),
    Segment(startTime: 5.0, endTime: 7.0, text: "world", words: nil, confidence: nil),
  ]
  let localWordsPerSegment: [[WordTiming]] = [
    [WordTiming(word: "hello", startTime: 0.1, endTime: 0.4, confidence: nil, punctuation: "")],
    [WordTiming(word: "world", startTime: 0.2, endTime: 0.6, confidence: nil, punctuation: "")],
  ]

  let results = zip(segments, localWordsPerSegment).compactMap { (seg, words) in
    Qwen3ASRTranscriber.rebaseAndBuildSegment(asrSegment: seg, localWords: words)
  }

  #expect(results.count == 2)
  #expect(results[0].startTime < results[1].startTime)
  #expect(results[0].endTime <= results[1].startTime)
}

@Test("segment with only whitespace text returns nil (skipped by caller)")
func nilForWhitespaceOnlySegment() {
  let seg = Segment(startTime: 1.0, endTime: 3.0, text: "   ", words: nil, confidence: nil)
  // Caller trims before calling rebaseAndBuildSegment; empty localWords → nil
  let result = Qwen3ASRTranscriber.rebaseAndBuildSegment(asrSegment: seg, localWords: [])
  #expect(result == nil)
}
```

**Step 2: Run the new tests**

```bash
xcodebuild test \
  -project Sources/VoiceFlowPro.xcodeproj \
  -scheme VoicePinkPro \
  -destination 'platform=macOS' \
  -only-testing:VoiceFlowProTests/Qwen3PerSegmentAlignTests \
  -parallel-testing-enabled NO 2>&1 | tail -20
```

Expected: All 5 tests PASS.

**Step 3: Commit**

```bash
git add Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift
git commit -m "test: add edge-case tests for Qwen3 per-segment alignment rebasing"
```
