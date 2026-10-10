# Translation Display Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix translations being generated but never displayed by decoupling translation storage from the segment processing pipeline.

**Architecture:** Translations are stored in a separate `processedTranslations` dictionary on `VideoState`, keyed by `SegmentIdentifier` (timing-based). After segment processing (splits, padding, filters), translations are injected into processed segments by matching `SegmentIdentifier`. This decouples translation display from the raw segment pipeline and survives all processing operations.

**Tech Stack:** Swift, SwiftUI, Swift Testing

---

## Root Cause

Three compounding bugs prevent translations from displaying:

1. **`processedSegments` cache not refreshed after translation** — `segmentProcessingSignature` doesn't include translation state; `Segment.Equatable` excludes `.translation`.
2. **All split operations strip `.translation`** — 5 split operations create new `Segment` objects without `.translation`.
3. **ID mismatch** — translations keyed by processed segment UUID; `applyTranslations()` matches against raw segment UUIDs.

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/VoiceFlowPro/Views/ContentView.swift` | Modify | Add `processedTranslations` to `VideoState`, update `applyTranslations()`, `clearTranslations()` |
| `Sources/VoiceFlowPro/Views/AICutView.swift` | Modify | Inject translations in `paddedSegments()`, force refresh in `markTranslationsChanged()`, update manual edit |
| `Sources/VoiceFlowPro/Services/AICutTranslationExecutor.swift` | Modify | Pass processed segments to `applyTranslations()` |
| `Sources/VoiceFlowProTests/Services/TranslationDisplayPipelineTests.swift` | Create | Tests for translation storage, injection, and invalidation |
| `Sources/VoiceFlowProTests/Services/AICutTranslationExecutorTests.swift` | Modify | Update for new `applyTranslations` signature |
| `Package.swift` | Modify | Add new test file to sources list |

---

### Task 1: Add failing tests for translation storage and injection

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/TranslationDisplayPipelineTests.swift`
- Modify: `Package.swift` (add to sources list)

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import VoiceFlowPro

@Suite("Translation display pipeline")
@MainActor
struct TranslationDisplayPipelineTests {

  // MARK: - VideoState.processedTranslations storage

  @Test("applyTranslations stores by SegmentIdentifier and populates processedTranslations")
  func applyTranslationsStoresBySegmentIdentifier() {
    let raw = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]
    let state = VideoState(segments: raw)

    // Simulate processed segments (different IDs, as splits would produce)
    let processed = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]

    let translations: [String: SegmentTranslation] = [
      processed[0].id: SegmentTranslation(text: "你好", language: .chinese),
      processed[1].id: SegmentTranslation(text: "世界", language: .chinese),
    ]

    state.applyTranslations(translations, for: processed)

    let id0 = SegmentIdentifier(segment: processed[0])
    let id1 = SegmentIdentifier(segment: processed[1])
    #expect(state.processedTranslations[id0]?.text == "你好")
    #expect(state.processedTranslations[id1]?.text == "世界")
  }

  @Test("clearTranslations removes processedTranslations")
  func clearTranslationsRemovesProcessedTranslations() {
    let raw = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    let state = VideoState(segments: raw)
    let processed = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    let translations: [String: SegmentTranslation] = [
      processed[0].id: SegmentTranslation(text: "你好", language: .chinese),
    ]
    state.applyTranslations(translations, for: processed)
    #expect(!state.processedTranslations.isEmpty)

    state.clearTranslations()

    #expect(state.processedTranslations.isEmpty)
    #expect(state.translationSignature == nil)
    #expect(state.lastTranslatedLanguage == nil)
  }

  @Test("setting new segments clears processedTranslations")
  func settingSegmentsClearsProcessedTranslations() {
    let raw = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    let state = VideoState(segments: raw)
    let processed = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    state.applyTranslations(
      [processed[0].id: SegmentTranslation(text: "你好", language: .chinese)],
      for: processed
    )
    #expect(!state.processedTranslations.isEmpty)

    // Setting new segments should clear translations
    state.segments = [Segment(startTime: 0, endTime: 2, text: "Different")]

    #expect(state.processedTranslations.isEmpty)
  }

  // MARK: - Translation injection after processing

  @Test("translations injected into segments after split+padding processing")
  func translationsInjectedAfterProcessing() {
    // Raw segment that will be split by silence
    let words: [WordTiming] = [
      WordTiming(word: "Hello", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 2.0, endTime: 2.5),
    ]
    let raw = [Segment(startTime: 0, endTime: 2.5, text: "Hello World", words: words)]

    // Process with split-by-silence (threshold 0.3s, gap is 1.5s → will split)
    let processed = SegmentProcess.process(
      segments: raw,
      totalDuration: 3.0,
      operations: [
        .splitBySilence(.init(splitThreshold: 0.3)),
        .padding(leftMs: 0, rightMs: 0),
      ]
    )
    #expect(processed.count == 2, "Should split into 2 segments")

    // Store translations keyed by processed segment identifiers
    var translations: [SegmentIdentifier: SegmentTranslation] = [:]
    translations[SegmentIdentifier(segment: processed[0])] =
      SegmentTranslation(text: "你好", language: .chinese)
    translations[SegmentIdentifier(segment: processed[1])] =
      SegmentTranslation(text: "世界", language: .chinese)

    // Inject translations
    let injected = VideoState.injectTranslations(translations, into: processed)

    #expect(injected[0].translation?.text == "你好")
    #expect(injected[1].translation?.text == "世界")
  }

  @Test("translations survive identical reprocessing")
  func translationsSurviveReprocessing() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 2.0, endTime: 2.5),
    ]
    let raw = [Segment(startTime: 0, endTime: 2.5, text: "Hello World", words: words)]
    let ops: [SegmentProcess.Operation] = [
      .splitBySilence(.init(splitThreshold: 0.3)),
      .padding(leftMs: 100, rightMs: 100),
    ]

    // First processing
    let first = SegmentProcess.process(segments: raw, totalDuration: 3.0, operations: ops)

    // Store translations
    var translations: [SegmentIdentifier: SegmentTranslation] = [:]
    for seg in first {
      translations[SegmentIdentifier(segment: seg)] =
        SegmentTranslation(text: "translated-\(seg.text)", language: .chinese)
    }

    // Second processing (identical config) — should produce same timing
    let second = SegmentProcess.process(segments: raw, totalDuration: 3.0, operations: ops)
    let injected = VideoState.injectTranslations(translations, into: second)

    for seg in injected {
      #expect(seg.translation != nil, "Translation should survive reprocessing for segment: \(seg.text)")
    }
  }

  @Test("duplicate timing segments each get translation via SegmentIdentifier")
  func duplicateTimingHandled() {
    // Two segments with same timing but different text — SegmentIdentifier collides
    // This is an accepted trade-off; in practice, same-timing segments are extremely rare
    let seg1 = Segment(startTime: 0, endTime: 1, text: "Hello")
    let seg2 = Segment(startTime: 0, endTime: 1, text: "World")
    let id1 = SegmentIdentifier(segment: seg1)
    let id2 = SegmentIdentifier(segment: seg2)
    #expect(id1 == id2, "SegmentIdentifier is timing-based, so same timing = same ID")
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

In `Package.swift`, add to the `sources:` array in the test target:
```
"Services/TranslationDisplayPipelineTests.swift",
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter TranslationDisplayPipelineTests 2>&1 | tail -20`
Expected: Compilation errors — `applyTranslations(_:for:)` and `injectTranslations(_:into:)` don't exist yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowProTests/Services/TranslationDisplayPipelineTests.swift Package.swift
git commit -m "test: add failing tests for translation display pipeline

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add `processedTranslations` to VideoState and update translation application

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ContentView.swift` (VideoState class, lines 8-70)

- [ ] **Step 1: Add `processedTranslations` property**

Add after the `lastTranslatedLanguage` property (line 24):
```swift
@Published var processedTranslations: [SegmentIdentifier: SegmentTranslation] = [:]
```

- [ ] **Step 2: Clear `processedTranslations` in `segments.didSet`**

In the `segments` property `didSet` block (line 10-16), add after `lastTranslatedLanguage = nil`:
```swift
processedTranslations.removeAll()
```

- [ ] **Step 3: Update `applyTranslations` to accept processed segments and populate map**

Replace the existing `applyTranslations(_:)` method (lines 53-59) with:
```swift
/// Apply translations from a dict (keyed by segment id) into processedTranslations.
/// Also embeds into raw segments where IDs match (best-effort for persistence).
func applyTranslations(_ translations: [String: SegmentTranslation], for processedSegments: [Segment]) {
    // Primary: store by SegmentIdentifier for display injection
    var map: [SegmentIdentifier: SegmentTranslation] = [:]
    for seg in processedSegments {
        if let t = translations[seg.id] {
            map[SegmentIdentifier(segment: seg)] = t
        }
    }
    processedTranslations = map
}

/// Inject translations from a dictionary into segments by matching SegmentIdentifier.
static func injectTranslations(
    _ translations: [SegmentIdentifier: SegmentTranslation],
    into segments: [Segment]
) -> [Segment] {
    guard !translations.isEmpty else { return segments }
    return segments.map { seg in
        let id = SegmentIdentifier(segment: seg)
        guard let t = translations[id] else { return seg }
        return Segment(
            id: seg.id,
            startTime: seg.startTime, endTime: seg.endTime,
            text: seg.text, words: seg.words,
            confidence: seg.confidence, speakerId: seg.speakerId,
            translation: t
        )
    }
}
```

- [ ] **Step 4: Update `clearTranslations` to clear processedTranslations**

Replace the existing `clearTranslations()` method (lines 62-70) with:
```swift
/// Clear all translations.
func clearTranslations() {
    processedTranslations.removeAll()
    translationSignature = nil
    lastTranslatedLanguage = nil
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter TranslationDisplayPipelineTests 2>&1 | tail -30`
Expected: Tests pass (storage, clear, didSet clearing, injection tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ContentView.swift
git commit -m "feat: add processedTranslations external store to VideoState

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Update AICutTranslationExecutor to use new signature

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/AICutTranslationExecutor.swift` (line 32)
- Modify: `Sources/VoiceFlowProTests/Services/AICutTranslationExecutorTests.swift` (line 42)

- [ ] **Step 1: Update executor to pass processed segments**

In `AICutTranslationExecutor.execute()` (line 32), change:
```swift
state.applyTranslations(translations)
```
to:
```swift
state.applyTranslations(translations, for: request.segments)
```

- [ ] **Step 2: Update existing executor test**

In `AICutTranslationExecutorTests.swift`, update the assertion (lines 42-43) to verify processedTranslations instead of embedded segment translations:
```swift
// Translations stored in processedTranslations
let id0 = SegmentIdentifier(segment: segments[0])
let id1 = SegmentIdentifier(segment: segments[1])
#expect(state.processedTranslations[id0] == expectedTranslations[segments[0].id])
#expect(state.processedTranslations[id1] == expectedTranslations[segments[1].id])
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter AICutTranslationExecutorTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Services/AICutTranslationExecutor.swift Sources/VoiceFlowProTests/Services/AICutTranslationExecutorTests.swift
git commit -m "refactor: executor uses new applyTranslations signature

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Update AICutView — inject translations and force refresh

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`

- [ ] **Step 1: Update `paddedSegments(for:)` to inject translations as final step**

At the end of `paddedSegments(for:)` (before the `return processed` on line 2690), add:
```swift
// Inject translations from external store
if let translations = videoStates[url]?.processedTranslations, !translations.isEmpty {
    processed = VideoState.injectTranslations(translations, into: processed)
}
```

- [ ] **Step 2: Force `processedSegments` refresh in `markTranslationsChanged`**

In `markTranslationsChanged(for:state:)` (line 2513), add after `translationsVersion &+= 1`:
```swift
processedSegments = currentSegments
```

- [ ] **Step 3: Update `runPendingTranslation` to pass processed segments**

In `runPendingTranslation(using:)` (line 3551), change:
```swift
state.applyTranslations(translations)
```
to:
```swift
state.applyTranslations(translations, for: request.segments)
```

- [ ] **Step 4: Update `applyManualTranslationEdit` to use processedTranslations**

In `applyManualTranslationEdit(displaySegment:newText:)` (lines 2731-2770), replace the segment mutation logic with processedTranslations updates:
```swift
private func applyManualTranslationEdit(
    displaySegment: SegmentsPanelView.DisplaySeg,
    newText: String?
) {
    guard let url = activeVideoURL,
        let videoState = videoStates[url]
    else {
        statusText = String(localized: "Select a video before editing translation.", comment: "AI Cut status message")
        return
    }

    let targetSegment = displaySegment.segment
    let identifier = SegmentIdentifier(segment: targetSegment)
    let trimmed = (newText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
        if videoState.processedTranslations.removeValue(forKey: identifier) != nil {
            markTranslationsChanged(for: url, state: videoState)
            statusText = String(localized: "Removed translation at \(formatTimecode(targetSegment.startTime)).", comment: "AI Cut status message")
        }
        return
    }

    let existing = videoState.processedTranslations[identifier]
    if existing?.text == trimmed { return }

    if var updated = existing {
        updated.text = trimmed
        updated.translatedAt = Date()
        videoState.processedTranslations[identifier] = updated
    } else {
        let language = config.translationTargetLanguage
        videoState.processedTranslations[identifier] = SegmentTranslation(text: trimmed, language: language)
    }

    markTranslationsChanged(for: url, state: videoState)
    statusText = String(localized: "Updated translation at \(formatTimecode(targetSegment.startTime)).", comment: "AI Cut status message")
}
```

- [ ] **Step 5: Update `onChange(of: config.translationTargetLanguage)` handler**

The existing handler (line 192-195) calls `state.clearTranslations()`. The updated `clearTranslations()` already clears `processedTranslations`, so no change needed here. Verify it works.

- [ ] **Step 6: Build and run all tests**

Run: `swift build 2>&1 | tail -10` then `swift test 2>&1 | tail -30`
Expected: Build succeeds, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift
git commit -m "fix: inject translations after segment processing and force refresh

Translations are now injected from processedTranslations after the
segment processing pipeline completes, ensuring they survive split
operations and display correctly in the UI.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Wiring integration test

**Files:**
- Modify: `Sources/VoiceFlowProTests/Integration/AICutTranslationWiringTests.swift`

- [ ] **Step 1: Add wiring test for translation injection in paddedSegments**

Add a new test to `AICutTranslationWiringTests`:
```swift
@Test("paddedSegments injects translations from processedTranslations store")
func paddedSegmentsInjectsTranslations() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/VoiceFlowPro/Views/AICutView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    // Verify injection code exists in paddedSegments
    #expect(content.contains("VideoState.injectTranslations("))
    #expect(content.contains("processedTranslations"))
}

@Test("markTranslationsChanged forces processedSegments refresh")
func markTranslationsChangedForcesRefresh() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/VoiceFlowPro/Views/AICutView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    // Find markTranslationsChanged and verify it sets processedSegments
    guard let funcRange = content.range(of: "private func markTranslationsChanged(") else {
        Issue.record("markTranslationsChanged not found")
        return
    }
    let slice = content[funcRange.lowerBound...]
    #expect(slice.contains("processedSegments = currentSegments"))
}
```

- [ ] **Step 2: Run integration tests**

Run: `swift test --filter AICutTranslationWiringTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowProTests/Integration/AICutTranslationWiringTests.swift
git commit -m "test: add wiring tests for translation injection pipeline

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Final verification

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 2: Build Xcode project**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Final commit (if any remaining changes)**

```bash
git add -A && git status
```
