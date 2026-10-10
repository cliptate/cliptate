# Audio Dubbing Feature Design

**Date:** 2026-04-28  
**Status:** Draft  
**Scope:** Audio export dubbing via TTS voice cloning  

## Problem

Users who transcribe and translate video content want to generate dubbed audio in the target language, using a voice that sounds like the original speaker. Currently the app can transcribe, translate, and export audio — but cannot synthesize translated speech that matches the original speaker's voice. This feature bridges that gap as a first step toward full video dubbing.

## Approach: Recommended

**Option A (Recommended): Segment-level TTS with per-segment time alignment**

Pipeline: extract voice reference from video → for each translated segment, synthesize TTS with voice cloning → align each segment's duration to the original → compose final dubbed audio track.

- Pros: Leverages existing MLXTTSService + voice cloning, segment-level granularity gives precise timing control, works with existing translation pipeline
- Cons: Requires new audio composition logic, synthesis is sequential per-segment

**Option B: Whole-text TTS then re-align**

Concatenate all translated text, synthesize one long audio, then stretch/compress to match total duration.

- Pros: Simpler pipeline
- Cons: Loses per-segment timing precision, cannot handle pauses/gaps between speech, poor lip-sync potential

**Option C: External service (cloud-based)**

Delegate to ElevenLabs/similar API for voice cloning + dubbing.

- Pros: Higher quality models available
- Cons: Requires API keys, network dependency, cost, privacy concerns for on-device app

**Decision:** Option A — aligns with the app's on-device philosophy and existing MLX TTS infrastructure.

## Architecture

### Pipeline Overview

```
Video/Audio Source
    ↓
[1] Voice Reference Extraction
    └─→ Extract longest speech segments (≥5s combined)
    └─→ Build reference audio + transcription text
    ↓
[2] Per-Segment TTS Synthesis (voice cloning)
    └─→ For each processedSegment with translation:
        └─→ MLXTTSService.synthesize(translatedText, referenceAudio)
    ↓
[3] Time Alignment
    └─→ Compare synthesized duration vs original segment duration
    └─→ If synth > original: speed up (atempo, clamp at 1.5×)
    └─→ If synth < original: pad with silence on both sides
    ↓
[4] Audio Composition
    └─→ Place each aligned segment at original timeline position
    └─→ Fill gaps between segments with silence
    └─→ Export as M4A or WAV
```

### New Components

#### 1. `DubbingService` (Service layer — orchestrator)

**File:** `Sources/VoiceFlowPro/Services/DubbingService.swift`

Responsibilities:
- Orchestrate the full dubbing pipeline
- Extract voice reference from source media
- Iterate segments, synthesize TTS, align timing, compose output
- Report progress via callback

```swift
public final class DubbingService {
    /// Result of a dubbing operation.
    struct DubbingResult {
        let audioFileURL: URL           // The composed dubbed audio file
        let segmentCount: Int           // Number of segments dubbed
        let totalDuration: TimeInterval // Duration of output audio
    }

    /// Generate a dubbed audio track from translated segments.
    func generateDubbedAudio(
        sourceMediaURL: URL,
        segments: [Segment],
        ttsModelDefinition: MLXTTSModelDefinition,
        ttsLanguage: String,
        outputURL: URL,
        outputFormat: AudioExportFormat,
        progress: @escaping (DubbingProgress) -> Void
    ) async throws -> DubbingResult
}
```

#### 2. `AudioTimeAligner` (Pure logic — testable)

**File:** `Sources/VoiceFlowPro/Services/AudioTimeAligner.swift`

Responsibilities:
- Compare synthesized audio duration to target duration
- Decide: speed up, or pad with silence
- Apply the transformation to raw audio samples

```swift
public struct AudioTimeAligner {
    /// The strategy chosen to align audio to a target duration.
    enum AlignmentStrategy: Equatable {
        case speedUp(factor: Double)       // factor > 1.0 means faster
        case padSilence(rightMs: Int)      // silence appended after speech
        case passthrough                   // durations match within tolerance
    }

    /// Maximum speedup factor before audio becomes unintelligible.
    static let maxSpeedFactor: Double = 1.5
    /// Tolerance: if durations differ by less than this, passthrough.
    static let toleranceMs: Int = 50

    /// Determine the alignment strategy given source and target durations.
    static func strategy(
        synthesizedDuration: TimeInterval,
        targetDuration: TimeInterval
    ) -> AlignmentStrategy

    /// Apply alignment to audio samples: returns adjusted samples.
    static func align(
        samples: [Float],
        sampleRate: Int,
        synthesizedDuration: TimeInterval,
        targetDuration: TimeInterval
    ) -> [Float]
}
```

**Time alignment rules:**
- If `|synthDuration - targetDuration| < 50ms`: passthrough (no adjustment)
- If `synthDuration > targetDuration`: speed up by factor `synthDuration / targetDuration`, clamped to 1.5×. If clamping is hit, the audio is still sped up at 1.5× and truncated to fit the target duration, with a 50ms fade-out at the end. A warning is emitted but export continues.
- If `synthDuration < targetDuration`: pad with silence **on the right side only** so dubbed speech starts at the same moment as the original segment. This preserves lip-sync alignment for future video dubbing.

**Speed adjustment implementation:** Use linear interpolation on raw Float samples (no FFmpeg dependency). Given `factor = synthDuration / targetDuration`, resample by stepping through the source at `factor` increments per output sample, linearly interpolating between adjacent source samples. This is equivalent to playback speed change without pitch correction — acceptable for speech at factors up to 1.5×.

#### 3. `AudioComposer` (Composition logic — testable)

**File:** `Sources/VoiceFlowPro/Services/AudioComposer.swift`

Responsibilities:
- Take time-aligned audio clips with timeline positions
- Compose into a single continuous audio buffer
- Fill gaps with silence
- Export to WAV Data

```swift
public struct AudioComposer {
    struct TimedClip {
        let samples: [Float]
        let startTime: TimeInterval  // Position on the output timeline
        let duration: TimeInterval
    }

    /// Compose clips into a single audio buffer at the given sample rate.
    static func compose(
        clips: [TimedClip],
        totalDuration: TimeInterval,
        sampleRate: Int
    ) -> [Float]
}
```

### Configuration Changes

#### `AppConfiguration`

Add one new published property:

```swift
@Published var audioDubbingEnabled: Bool  // default: false
```

Wire through `Snapshot` (add field, default value, `makeSnapshot()`, `applySnapshot(_:)`, and Codable with `decodeIfPresent` for backward compatibility).

#### `ExportAllRequest`

No changes needed — dubbing is controlled by `config.audioDubbingEnabled` and only activates when `includeAudio` is also true. The export flow checks the config at runtime.

### UI Changes

#### `ControlPanelConfigurationView` — Audio Module

Add a dubbing toggle below the existing audio export toggle:

```swift
GroupBox {
    Toggle(isOn: $config.audioDubbingEnabled) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Voice Dubbing")
            Text("Generate dubbed audio using TTS voice cloning with translated text.")
        }
    }
}
```

The toggle is disabled when:
- Audio export is disabled (`!config.audioExportEnabled`)
- No translations exist (runtime check during export)

### Export Flow Changes

#### `AICutView.performBatchAudioExport`

When `config.audioDubbingEnabled` is true:

1. Instead of extracting audio from source via `AudioExporter`, invoke `DubbingService`
2. Pass the current `processedSegments` (which already include translations)
3. Use the active TTS model configuration from `AppConfiguration`
4. Output the dubbed audio file in the selected format

When dubbing is disabled, existing behavior is preserved unchanged.

### Voice Reference Extraction

The service extracts a voice reference from the source media by:

1. Loading audio from the source video/audio file via `AudioProcessor.loadAndConvertAudio`
2. Using the `processedSegments` to identify speech regions
3. Sorting segments by duration (longest first), accumulating until ≥5 seconds total
4. For multi-speaker media (segments with different `speakerId`): use only segments from the **most frequent speaker** (MVP is single-speaker-focus)
5. Extracting those samples via `AudioProcessor.extractSamples` and saving to a temporary WAV file
6. Concatenating the text of selected segments as the reference transcription

**TTS synthesis contract:** Each segment is synthesized via `MLXTTSService.synthesize()` with:
- `text`: the segment's `translation.text`
- `modelDefinition`: resolved from `config.ttsMLXModelId` (same model user selected for TTS)
- `voiceDescription`: nil (voice cloning mode, not voice design)
- `referenceAudioURL`: the extracted temporary WAV file
- `referenceText`: the concatenated original text from reference segments
- `language`: `config.ttsLanguage` (target language for synthesis)

**Preflight checks before export:**
1. Target language must be supported by the selected TTS model (Qwen3 supports: en, zh, ja, ko)
2. At least one segment must have a translation
3. TTS model must be downloaded (attempt load; fail with actionable message if unavailable)
4. Source media must have an audio track

**Partial translation policy:** Segments without translations are skipped — silence is inserted at their timeline position. The export continues and the status reports how many segments were dubbed vs. total.

### Error Handling

- **No translations available:** Preflight check fails with user-facing error before starting export
- **Target language unsupported by TTS:** Preflight check fails with message listing supported languages
- **TTS model not loaded:** Attempt to load; fail with actionable message if unavailable
- **Individual segment synthesis failure:** Log warning, insert silence for that segment, continue with remaining segments. Report count of failed segments in final status.
- **Reference audio too short (<1s):** Fall back to TTS preset speaker from config
- **Speed factor exceeds 1.5× clamp:** Apply 1.5× speed + truncate with fade-out, emit warning in status

### Progress Reporting

```swift
struct DubbingProgress {
    let phase: Phase
    let currentSegment: Int
    let totalSegments: Int

    enum Phase {
        case extractingReference
        case synthesizing
        case aligning
        case composing
        case exporting
    }
}
```

Status text updates in `AICutView` follow the existing pattern:
- "Extracting voice reference..."
- "Dubbing segment [3/12]..."
- "Composing dubbed audio..."

### Testing Strategy

**Unit tests (TDD, Swift package):**

1. `AudioTimeAlignerTests` — Pure logic, no AVFoundation dependency:
   - `strategy()` returns `.passthrough` when durations match within tolerance
   - `strategy()` returns `.speedUp` when synth > target
   - `strategy()` returns `.padSilence` with equal L/R padding when synth < target
   - Speed factor is clamped to 1.5×
   - `align()` produces correct sample count for speed-up and padding cases

2. `AudioComposerTests` — Pure sample composition:
   - Single clip placed at correct offset
   - Multiple clips with gaps filled by silence
   - Total output duration matches expected
   - Overlapping clips handled gracefully (later clip overwrites)

3. `DubbingServiceTests` — Integration-level (may require mocking TTS):
   - Segments without translations are skipped
   - Progress callback fires correctly
   - Empty segment list produces error

### Localization

All new user-visible strings must include zh-Hans, ja, ko translations in `Localizable.xcstrings`.

New keys:
- "Voice Dubbing" (toggle title)
- "Generate dubbed audio using TTS voice cloning with translated text." (toggle description)
- "Extracting voice reference..." (status)
- "Dubbing segment [%d/%d]..." (status)
- "Composing dubbed audio..." (status)
- Error messages for no-translation, TTS-not-loaded scenarios

### Future Extensions (Out of Scope)

- **Video dubbing:** Replace audio track in exported video (user mentioned as future work)
- **Background audio preservation:** Separate vocals via Demucs, duck background during dubbed speech
- **Multi-speaker dubbing:** Different voice clones per `speakerId`
- **Real-time preview:** Play dubbed segment before full export
- **Segment-level voice override:** Let user pick different voice per segment

## File Summary

| File | Action | Purpose |
|------|--------|---------|
| `Services/DubbingService.swift` | New | Pipeline orchestrator |
| `Services/AudioTimeAligner.swift` | New | Duration alignment logic |
| `Services/AudioComposer.swift` | New | Multi-clip audio composition |
| `Models/AppConfiguration.swift` | Edit | Add `audioDubbingEnabled` |
| `Models/ExportOptions.swift` | No change | — |
| `Views/ControlPanelConfigurationView.swift` | Edit | Add dubbing toggle in audio module |
| `Views/AICutView.swift` | Edit | Integrate dubbing into export flow |
| `Tests/AudioTimeAlignerTests.swift` | New | Time alignment unit tests |
| `Tests/AudioComposerTests.swift` | New | Composition unit tests |
