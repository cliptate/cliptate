# Transcription Consolidation & FCPXML Speed Configuration

**Date:** 2026-04-28
**Scope:** AI Cut Editor transcription pipeline consolidation + FCPXML speed export

---

## Problem Statement

### 1. Scattered Transcription Entry Points

AICutView currently has 6+ transcription methods with duplicated pipeline logic:

| Method | Role |
|--------|------|
| `transcribeVideo()` | UI entry → single |
| `transcribeAllVideos()` | UI entry → batch |
| `performSingleTranscription()` | Inline: ASR → dictionary bias → speaker annotation |
| `performBatchTranscription()` | Loop: calls `transcribeBatchVideo` per URL |
| `performImportedBatchTranscription()` | Import loop: calls `transcribeBatchVideo` per URL |
| `transcribeBatchVideo()` | Batch single: ASR → dictionary bias → speaker annotation |
| `transcribeBatchVideoResult()` | Raw ASR dispatch (Qwen3 forced-align vs generic) |

The core pipeline (ASR → dictionary bias → speaker annotation) is duplicated between `performSingleTranscription` (lines 896–1109) and `transcribeBatchVideo` (lines 1369–1426).

### 2. Speaker Annotation Fragility

Speaker identification IS implemented (`PlainASRSpeakerPropagation` + `SortformerVADSegmenter`), but:

- If the Sortformer model isn't downloaded, `SortformerVADSegmenter.makeWithModel` throws
- This error propagates up and **kills the entire transcription** — the ASR result is lost
- No graceful fallback: the user loses their transcription because of an optional feature
- Both single and batch paths share this fragility

### 3. FCPXML Missing Speed Configuration

`FCPXMLExportSettings` has no speed/rate control. The Python reference implementation supports:
- Timeline speed via `timeMap` elements (FCPXML native speed ramps)
- Adjusted timeline durations (source duration / speed)
- Both clip-mode and full-video-mode speed application

---

## Approach: Unified Transcription Pipeline + FCPXML Speed

### Alternatives Considered

| Approach | Pros | Cons |
|----------|------|------|
| **A. Extract TranscriptionPipeline** (chosen) | Single source of truth; graceful speaker fallback; testable | Moderate refactor of AICutView |
| B. Minimal speaker fix only | Fast; low risk | Leaves duplication; doesn't address consolidation |
| C. Full strategy-pattern pipeline | Maximum flexibility | Overengineered for current needs |

---

## Design

### Part 1: TranscriptionPipeline Service

Extract a new `TranscriptionPipeline` that owns the post-ASR processing chain:

```
ASR result → Dictionary Bias → Speaker Annotation (graceful) → Final Segments
```

**File:** `Sources/VoiceFlowPro/Services/TranscriptionPipeline.swift`

```swift
struct TranscriptionPipeline {
  let speakerPropagation: PlainASRSpeakerPropagation

  struct Result {
    let segments: [Segment]
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
    let speakerAnnotationApplied: Bool
  }

  /// Post-processes raw ASR output: applies dictionary bias, then speaker annotation.
  /// Speaker annotation failure is gracefully handled — returns unannotated segments.
  func postProcess(
    asrResult: TranscriptionResult,
    sourceURL: URL,
    dictionaryEntries: [String]
  ) async -> Result {
    let biasedSegments = ASRDictionaryBiasService.apply(
      to: asrResult.segments,
      dictionaryEntries: dictionaryEntries
    )

    var finalSegments = biasedSegments
    var speakerApplied = false

    do {
      finalSegments = try await speakerPropagation.annotate(biasedSegments, for: sourceURL)
      speakerApplied = true
    } catch {
      // Graceful fallback: speaker annotation failed (model not available, etc.)
      // Return segments without speaker IDs rather than failing transcription
      print("Speaker annotation skipped: \(error.localizedDescription)")
    }

    return Result(
      segments: finalSegments,
      audioDuration: asrResult.totalDuration,
      processingTime: asrResult.processingTime,
      speakerAnnotationApplied: speakerApplied
    )
  }
}
```

**Changes to AICutView:**

- Replace inline pipeline in `performSingleTranscription` with `pipeline.postProcess(...)`
- Replace inline pipeline in `transcribeBatchVideo` with `pipeline.postProcess(...)`
- `transcribeBatchVideoResult` stays as-is (it's the raw ASR dispatch)
- Remove duplicated `ASRDictionaryBiasService.apply()` + `plainASRSpeakerPropagation.annotate()` calls

**Before (performSingleTranscription):**
```swift
let biasedSegments = ASRDictionaryBiasService.apply(to: result.segments, ...)
let speakerAnnotatedSegments = try await plainASRSpeakerPropagation.annotate(biasedSegments, for: url)
// ... use speakerAnnotatedSegments
```

**After:**
```swift
let pipelineResult = await transcriptionPipeline.postProcess(
  asrResult: result,
  sourceURL: url,
  dictionaryEntries: config.voiceToTextCustomDictionary
)
// ... use pipelineResult.segments
```

Same change applies to `transcribeBatchVideo`.

### Part 2: FCPXML Speed Configuration

Add a `speed` property (Double, default 1.0, range 0.1–10.0) to control playback speed in the exported FCPXML timeline.

**Config chain (all files need the new field):**

| File | Change |
|------|--------|
| `AppConfiguration.swift` | Add `@Published var fcpxmlSpeed: Double` with didSet clamping |
| `AppConfiguration.Snapshot` | Add `var fcpxmlSpeed: Double` field |
| `AppConfiguration.defaultSnapshot` | Add `fcpxmlSpeed: 1.0` |
| `AppConfiguration.makeSnapshot()` | Include `fcpxmlSpeed` |
| `AppConfiguration.applySnapshot(_:)` | Apply `fcpxmlSpeed` |
| `AppConfiguration.Snapshot.init(from:)` | Decode with fallback `?? 1.0` |
| `AppConfiguration.Snapshot.encode(to:)` | Encode `fcpxmlSpeed` |
| `ConfigPresetStore.PresetPayload` | Add `fcpxmlSpeed` field + CodingKey |
| `FCPXMLExportSettings` | Add `let speed: Double` |
| `FCPXMLExporter` | Implement speed math + timeMap |
| `AICutView` (export call site) | Pass `config.fcpxmlSpeed` |
| `ControlPanelConfigurationView` | Add speed slider/field in FCPXML section |

**FCPXMLExporter speed implementation** (matching Python reference):

```swift
// Timeline frame conversion (adjusted for speed)
func secondsToTimelineFrames(_ seconds: Double) -> Int {
  Int(ceil(seconds * settings.frameRate / settings.speed))
}

// Source frame conversion (original media timing)
func secondsToSourceFrames(_ seconds: Double) -> Int {
  Int(ceil(seconds * settings.frameRate))
}

// timeMap element for speed != 1.0
func buildTimeMap(sourceStart: Int, timelineDuration: Int, sourceDuration: Int, fps: Int) -> String {
  """
                <timeMap>
                  <timept time="\(sourceStart)/\(fps)s" value="\(sourceStart)/\(fps)s" interp="smooth2"/>
                  <timept time="\(sourceStart + timelineDuration)/\(fps)s" value="\(sourceStart + sourceDuration)/\(fps)s" interp="smooth2"/>
                </timeMap>
  """
}
```

**Key behavior:**
- `speed == 1.0`: No change to current behavior (no timeMap emitted)
- `speed > 1.0`: Timeline is shorter, timeMap maps compressed timeline to original source
- `speed < 1.0`: Timeline is longer (slow motion)
- Gap clips also get timeMap when speed != 1.0
- Total sequence duration is adjusted: `totalFrames / speed`

### Part 3: UI — Speed Control

Add a speed field in the FCPXML export configuration section of `ControlPanelConfigurationView`, adjacent to Frame Rate:

```
Frame Rate  [25.0] fps
Speed       [1.0 ] ×
```

The speed field uses the same `TextField` + `NumberFormatter` pattern as Frame Rate, with range 0.1–10.0.

---

## Testing Strategy

### TranscriptionPipeline Tests
- **Happy path**: ASR result + dictionary bias + speaker annotation all succeed
- **Speaker fallback**: Mock `PlainASRSpeakerPropagation` to throw → verify segments returned without speakerIds
- **Empty segments**: Pipeline handles empty ASR result gracefully

### FCPXML Speed Tests
- **Speed 1.0**: Output matches current behavior (no timeMap)
- **Speed 2.0**: Timeline durations halved, timeMap present
- **Speed 0.5**: Timeline durations doubled, timeMap present
- **Edge cases**: Speed at boundaries (0.1, 10.0)
- **Round-trip**: Speed value persisted/restored via Snapshot

### Config Persistence Tests
- `fcpxmlSpeed` round-trips through Snapshot encode/decode
- `fcpxmlSpeed` round-trips through ConfigPresetStore
- Default value is 1.0 when decoding legacy snapshots

---

## Files Modified

| File | Change Type |
|------|-------------|
| `Services/TranscriptionPipeline.swift` | **New** — unified post-ASR pipeline |
| `Views/AICutView.swift` | **Modified** — use TranscriptionPipeline |
| `Models/AppConfiguration.swift` | **Modified** — add fcpxmlSpeed |
| `Services/ConfigPresetStore.swift` | **Modified** — add fcpxmlSpeed |
| `Services/FCPXMLExporter.swift` | **Modified** — speed + timeMap |
| `Views/ControlPanelConfigurationView.swift` | **Modified** — speed UI |
| `Tests/TranscriptionPipelineTests.swift` | **New** — pipeline tests |
| `Tests/FCPXMLSpeedTests.swift` | **New** — speed export tests |
