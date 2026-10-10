# Speaker Propagation + Models Page State Persistence

**Date:** 2026-04-21  
**Status:** Approved

---

## Problem Statement

Two issues identified after the v1.8 download-progress + speaker-badge work:

1. **Speaker IDs never appear in transcription output** — even though `SortformerVADSegmenter` assigns `speakerId` to each `AudioTimeRange`, `SegmentedAlignmentPipeline` drops that information before it reaches the UI.

2. **ModelsView loses in-progress download state on navigation** — switching to another sidebar section destroys `ModelsView` and resets all `@State` variables, making active downloads appear to disappear (they continue in the actor but the UI loses track).

---

## Issue 1: Speaker Propagation in SegmentedAlignmentPipeline

### Root Cause

Two bugs in `SegmentedAlignmentPipeline.swift`:

**Bug A — `normalizeAndSplit()` discards `speakerId`:**
```swift
// Before (broken)
result.append(AudioTimeRange(startTime: cursor, endTime: next))
// After (fixed)
result.append(AudioTimeRange(startTime: cursor, endTime: next, speakerId: segment.speakerId))
```

**Bug B — All chunks collapsed into one mega-segment:**  
The pipeline collects words from all chunks into `mergedWords`, sorts them globally, then creates a single `Segment`. Even with the `speakerId` fix in A, speaker information would be irretrievably lost at this merge step.

### Fix

Refactor `run()` to produce **one `Segment` per VAD chunk** instead of one merged segment:

- Each chunk's aligned words are assembled into a `Segment` with `speakerId: chunk.speakerId`
- Word timestamps are still rebased to absolute time (same as before)
- `progressHandler` receives the growing list of segments per chunk

```swift
// Conceptual output change:
// Before: [Segment(all words merged, speakerId: nil)]
// After:  [Segment(chunk1 words, speakerId: 0),
//          Segment(chunk2 words, speakerId: 1), ...]
```

### Scope

- `Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift` — both `normalizeAndSplit()` and `run()` 
- Existing `SegmentedAlignmentPipelineTests` must be updated to reflect the new multi-segment output
- No changes to `AudioTimeRange`, `Segment`, or callers in `AICutView`

---

## Issue 2: ModelsView Download State Persistence

### Root Cause

`ModelsView` holds `progressMap`, `downloadedMap`, and `errorMap` as `@State`. In a `NavigationSplitView`, the detail view is destroyed and recreated when you switch sections. `@State` is reset to defaults on recreation, causing in-progress downloads to appear vanished.

### Fix

Introduce `ModelDownloadStateStore` — a `@MainActor`-isolated `ObservableObject` singleton:

```swift
@MainActor
final class ModelDownloadStateStore: ObservableObject {
    static let shared = ModelDownloadStateStore()
    
    @Published var progressMap: [ModelVariant: ModelDownloadProgress] = [:]
    @Published var downloadedMap: [ModelVariant: Bool] = [:]
    @Published var errorMap: [ModelVariant: String] = [:]
}
```

- Instantiated as `@StateObject` in `ContentView` and injected via `.environmentObject()`
- `ModelsView` replaces its three `@State` properties with `@EnvironmentObject private var downloadState: ModelDownloadStateStore`
- All read/write accesses to those three maps in `ModelsView` use `downloadState.progressMap` etc.
- `downloadedMap` and `errorMap` are also moved to the store so status is consistent across navigation

### Scope

- `Sources/VoiceFlowPro/Services/ModelDownloadStateStore.swift` — new file
- `Sources/VoiceFlowPro/Views/ContentView.swift` — add `@StateObject` + `.environmentObject()`
- `Sources/VoiceFlowPro/Views/ModelsView.swift` — replace `@State` with `@EnvironmentObject`, update all usages

---

## Testing Strategy (TDD)

### SegmentedAlignmentPipeline tests

| # | Test | Expected |
|---|------|----------|
| T1 | Two chunks with different speakerIds → two output segments with correct speakerIds | pass |
| T2 | Chunk longer than maxChunkDuration → split into sub-chunks sharing original speakerId | pass |
| T3 | Empty chunk text → no segment emitted for that chunk | pass |
| T4 | Single chunk, speakerId nil → one segment with speakerId nil | pass |

### ModelDownloadStateStore tests

| # | Test | Expected |
|---|------|----------|
| T5 | Initial state — all maps empty | pass |
| T6 | Set progress for variant → `progressMap[variant]` reflects it | pass |
| T7 | Clear progress → `progressMap[variant]` is nil | pass |

---

## Out of Scope

- Qwen3 streaming (microphone) speaker propagation — separate investigation
- UI changes to segment display (speaker badge already shipped in v1.8)
- Sorting/ordering of speakers in the UI
