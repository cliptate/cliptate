# Streaming Architecture Refactor & Waveform Layout Fix

## Problem Statement

Two issues to address:

1. **MicIndicatorOverlay layout**: The waveform section's `Spacer(minLength: 1)` causes excessive gaps between the app icon, waveform visualizer, and duration timer.

2. **Streaming module duplication**: `MLXParakeetStreamingModule` and `Qwen3StreamingModule` duplicate ~90% of their code (audio engine setup, buffer management, VAD integration, resampling). Adding new ASR engines (e.g., FireRedASR) requires duplicating this entire module. The desired flow is: **mic → VAD → ASR → AI enhance → output**.

## Part 1: MicIndicatorOverlay Layout Fix

### Current State

```swift
HStack(alignment: .center, spacing: 0) {
    appIcon (24x24)
    Spacer(minLength: 1)        // ← excessive gap
    scrollingVisualizer(width: 70)  // ← fixed, small
    Spacer(minLength: 1)        // ← excessive gap
    timer/spinner (24x24)
}
```

### Target Layout

```swift
HStack(alignment: .center, spacing: 12) {
    appIcon (24x24)
    scrollingVisualizer()  // flexible, fills available space
    timer/spinner (24x24)
}
```

### Changes

- Replace `spacing: 0` + `Spacer(minLength: 1)` with `spacing: 12`
- Remove both `Spacer` views
- Change `scrollingVisualizer(width:)` to use flexible width via `.frame(maxWidth: .infinity)`
- The visualizer `barCount` remains 30 but bar width adapts to available space

## Part 2: Streaming Architecture Refactor

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│              StreamingAudioCaptureModule                  │
│   (AVAudioEngine, buffer, resample, VAD, accumulator)   │
│                                                          │
│   Configuration:                                         │
│     - chunkDuration: Double                              │
│     - sampleRate: 16000                                  │
│     - maxSpeechWindowDuration: 3.0                       │
│                                                          │
│   Callbacks:                                             │
│     - onAudioLevel: (CGFloat) -> Void                    │
│     - onInterimText: (String) -> Void                    │
│                                                          │
│   Pipeline:                                              │
│     mic tap → resample → chunk → VAD → speech window     │
│                                     ↓                    │
│                            StreamingASREngine             │
│                            .transcribe(samples)           │
│                                     ↓                    │
│                            text accumulation → callback   │
└─────────────────────────────────────────────────────────┘
```

### New Protocol: `StreamingASREngine`

```swift
/// Minimal protocol for any ASR model that can transcribe a chunk of 16kHz audio.
@MainActor
protocol StreamingASREngine {
    func transcribeStreamingChunk(
        samples16k: [Float],
        language: Language,
        dictionaryContext: String?
    ) throws -> String
}
```

**Conformers:**
- `MLXParakeetTranscriber` — already has `transcribeStreamingChunk` (just needs protocol conformance)
- `Qwen3ASRTranscriber` — already has `transcribeStreamingChunk` (just needs protocol conformance)
- `FireRedASRTranscriber` — new method, delegates to `FireRedASR2Model.generate()` with the chunk

### New Class: `StreamingAudioCaptureModule`

Replaces both `MLXParakeetStreamingModule` and `Qwen3StreamingModule`:

```swift
@MainActor
final class StreamingAudioCaptureModule {
    struct Configuration {
        let chunkDuration: Double  // e.g., 2.0 for Parakeet, 3.0 for Qwen3
        let levelCalculator: ([Float]) -> CGFloat
    }

    struct Callbacks {
        let onAudioLevel: (CGFloat) -> Void
        let onInterimText: (String) -> Void
    }

    func start(
        engine: any StreamingASREngine,
        language: Language,
        dictionaryContext: String?,
        streamingVAD: (any StreamingVADProvider)?
    ) async throws

    func stop() async throws -> String?
    func reset()
}
```

### Files Deleted

- `Sources/VoiceFlowPro/Services/MLXParakeetStreamingModule.swift`
- `Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift`

### Files Created

- `Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift` — unified module
- `Sources/VoiceFlowPro/Services/StreamingASREngine.swift` — protocol definition

### Files Modified

- `Sources/VoiceFlowPro/Services/StreamingTranscriptionProvider.swift` — providers use `StreamingAudioCaptureModule`
- `Sources/VoiceFlowPro/Services/TranscriptionPipelineFactory.swift` — factory creates unified module, FireRed now supported
- `Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift` — add `transcribeStreamingChunk` conformance
- `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift` — add `StreamingASREngine` conformance declaration
- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift` — add `StreamingASREngine` conformance declaration
- `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift` — layout fix
- `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift` — update to use unified module (if references old modules)

### StreamingTranscriptionProvider Simplification

With the unified module, providers become trivial wrappers:

```swift
@MainActor
final class UnifiedStreamingProvider: StreamingTranscriptionProvider {
    private let module: StreamingAudioCaptureModule
    private let engine: any StreamingASREngine
    private let streamingVAD: (any StreamingVADProvider)?

    func start(language: Language, dictionaryContext: String?) async throws {
        try await module.start(
            engine: engine,
            language: language,
            dictionaryContext: dictionaryContext,
            streamingVAD: streamingVAD
        )
    }

    func stop() async throws -> String? { try await module.stop() }
    func reset() { module.reset() }
}
```

Or we can collapse `StreamingTranscriptionProvider` entirely since it's now a thin pass-through. Decision: keep it as the public API surface for `VoiceTranscriber` consumers but use a single concrete class instead of per-engine classes.

### FireRedASR Streaming Support

`FireRedASRTranscriber` gains:

```swift
extension FireRedASRTranscriber: StreamingASREngine {
    func transcribeStreamingChunk(
        samples16k: [Float],
        language: Language,
        dictionaryContext: String?
    ) throws -> String {
        guard let model = state.currentModel() else {
            throw FireRedASRError.modelNotReady
        }
        let request = GenerationRequest(audio: samples16k, language: language.bcp47Code)
        let output = try model.generate(request)
        return output.text
    }
}
```

### Error Handling

- If VAD fails mid-stream, fall back to fixed-duration chunks (existing behavior, preserved)
- If ASR engine throws, log and skip the chunk (don't crash the stream)
- If audio engine fails to start, propagate the error to the caller

### Testing Strategy

- Unit tests for `StreamingAudioCaptureModule` with a mock `StreamingASREngine`
- Unit tests for `FireRedASRTranscriber.transcribeStreamingChunk` with test hooks
- Update `TranscriptionPipelineFactoryTests` for FireRed streaming support
- Update `MicIndicatorOverlayTests` if layout logic affects testable state

## Success Criteria

1. Waveform overlay shows icon, waveform, and timer with compact spacing (no large gaps)
2. `MLXParakeetStreamingModule` and `Qwen3StreamingModule` are deleted
3. All streaming flows use the unified `StreamingAudioCaptureModule`
4. FireRed ASR works in streaming mode through the unified pipeline
5. Existing tests pass; new tests cover the unified module and FireRed streaming
