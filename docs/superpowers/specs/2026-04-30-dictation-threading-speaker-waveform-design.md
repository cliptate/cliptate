# Design: Dictation Threading Fix, Speaker ID Display, and Waveform Redesign

**Date:** 2026-04-30
**Status:** Draft

## Problem Statement

Three issues in the voice dictation feature:

1. **Threading bug**: Streaming text stops updating after ~1 minute with runtime warning: "Publishing changes from background threads is not allowed; make sure to publish values from the main thread". This kills the live transcription UX.

2. **Missing speaker attribution**: Dictation records no speaker identity. Users want to see "Speaker N: content" segmented display both in the overlay and in history.

3. **Waveform visual discomfort**: The left-to-right scrolling horizontal bar visualization causes dizziness. Users prefer vertical bouncing bars driven by real-time audio RMS.

## 1. Threading Fix

### Root Cause

The `MicIndicatorViewModel` class (line 485 of `MicIndicatorOverlay.swift`) is an `ObservableObject` with `@Published` properties but is **not annotated with `@MainActor`**. While `MicIndicatorOverlay` itself is `@MainActor`, the `Callbacks` closures in `StreamingAudioCaptureModule` are plain `(CGFloat) -> Void` / `(String) -> Void` — not actor-isolated.

Under sustained streaming (~1 minute), the high volume of `Task { @MainActor }` tasks from the audio tap, combined with `Task.detached` ASR results calling `await self?.handleTranscriptionResult(...)`, creates conditions where `@Published` property mutations can race against SwiftUI's observation cycle.

### Fix

1. **Annotate `MicIndicatorViewModel` with `@MainActor`** — ensures all `@Published` mutations are compile-time verified.

2. **Make `Callbacks` closures `@MainActor @Sendable`** in `StreamingAudioCaptureModule`:
   ```swift
   struct Callbacks {
     let onAudioLevel: @MainActor @Sendable (CGFloat) -> Void
     let onInterimText: @MainActor @Sendable (String) -> Void
   }
   ```

3. **Ensure callback invocations use `await`** where needed, or use `MainActor.assumeIsolated` when already known to be on main actor.

### Files Changed

- `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift` — add `@MainActor` to `MicIndicatorViewModel`
- `Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift` — make `Callbacks` closures `@MainActor @Sendable`
- `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift` — update callback closure signatures

## 2. Speaker ID in Dictation

### Architecture

The existing batch pipeline already performs speaker diarization via `PlainASRSpeakerPropagation` → `SegmentSpeakerAnnotator`. The streaming pipeline has no speaker detection. The approach:

- **During live streaming:** Show text without speaker labels (no change to streaming UX).
- **During batch re-transcription:** Run speaker diarization on the recorded audio, assign `speakerId` to each transcript line.
- **Display:** Format each line as "Speaker N: content" in both the MicIndicator overlay and VoiceToTextView history.

### Data Model Changes

**`TranscriptLine`** — add optional `speakerId`:
```swift
public struct TranscriptLine: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let timestamp: TimeInterval
  public var text: String
  public var speakerId: Int?
}
```

### Re-transcription Pipeline Change

In `VoiceTranscriber.retranscribeRecordedAudio(at:)`:
1. After batch ASR produces `biasedSegments`, run `PlainASRSpeakerPropagation` on the recording to get speaker-annotated segments.
2. Build `TranscriptLine` entries with `speakerId` from the annotated segments.
3. Store in session.

### Display Format

In both `MicIndicatorOverlay.transcriptEntries` and `VoiceToTextView`:
- Lines with `speakerId != nil` display as: `"Speaker {N}: {text}"`
- Lines without `speakerId` display as plain text (streaming phase).
- Speaker labels use localized format for zh-Hans/ja/ko.

### Files Changed

- `Sources/VoiceFlowPro/Models/TranscriptSession.swift` — add `speakerId` to `TranscriptLine`
- `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift` — add speaker diarization to `retranscribeRecordedAudio`
- `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift` — format display with speaker prefix
- `Sources/VoiceFlowPro/Views/VoiceToTextView.swift` — format history display with speaker prefix

## 3. Waveform Redesign

### Current State

- 30 horizontal bars scrolling left-to-right (level history)
- Driven by real RMS levels from `micRMSLevel(from:)`
- Simple linear animation

### New Design

Replace `scrollingVisualizer()` with a **5-bar vertical bouncing waveform**:

- **Bar count:** 5
- **Bar weights:** `[0.5, 0.8, 1.0, 0.75, 0.55]` — center-high, sides-low natural shape
- **Direction:** Vertical oscillation (bars stretch upward from center baseline)
- **Data source:** Real-time RMS level from `viewModel.level` (same as current)
- **Envelope smoothing:**
  - Attack coefficient: 0.40 (fast response to louder audio)
  - Release coefficient: 0.15 (slow decay for smoothness)
  - Formula: `smoothed = isMounting ? attack * raw + (1-attack) * prev : release * raw + (1-release) * prev`
- **Jitter:** ±4% random per bar per frame for organic feel
- **Bar sizing:**
  - Min height: 6pt (quiet)
  - Max height: 38pt (loud)
  - Bar width: ~8pt with 4pt spacing
  - Total width: ~60pt (5 bars × 8pt + 4 × 4pt = 56pt)
- **Visual style:**
  - Rounded rectangle bars with cornerRadius = barWidth / 2
  - Gradient fill matching current blue/cyan theme
  - Center-aligned vertically within the waveform area

### Smoothed Level State

Add smoothed per-bar levels to `MicIndicatorViewModel`:
```swift
var smoothedBarLevels: [CGFloat] = [0, 0, 0, 0, 0]
```

Update each frame in the `TimelineView`:
```swift
let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
for i in 0..<5 {
  let target = level * weights[i] + CGFloat.random(in: -0.04...0.04)
  let isAttack = target > smoothedBarLevels[i]
  let coeff: CGFloat = isAttack ? 0.40 : 0.15
  smoothedBarLevels[i] = coeff * target + (1 - coeff) * smoothedBarLevels[i]
}
```

### Files Changed

- `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift`:
  - Replace `scrollingVisualizer()` with `bouncingWaveform()`
  - Add `smoothedBarLevels` to `MicIndicatorViewModel`
  - Remove `levelHistory` array and `maxLevelHistory` constant (no longer needed for scrolling)
  - Keep `level` property for the raw RMS value

## Testing Strategy (TDD)

### Unit Tests

1. **Threading fix**: Verify `MicIndicatorViewModel` `@Published` changes compile with `@MainActor` annotation.
2. **TranscriptLine speaker ID**: Test encode/decode round-trip with `speakerId`, test backward compat (nil `speakerId` in old data).
3. **Speaker display formatting**: Test "Speaker N: text" formatting function.
4. **Waveform envelope**: Test attack/release smoothing math with known inputs.
5. **Waveform jitter**: Test that jitter stays within ±4% bounds.
6. **Bar weights**: Test that weights produce center-high, sides-low pattern.

### Integration Tests

- Verify `retranscribeRecordedAudio` produces lines with `speakerId` when diarization is available.
- Verify overlay displays speaker-prefixed lines correctly.
