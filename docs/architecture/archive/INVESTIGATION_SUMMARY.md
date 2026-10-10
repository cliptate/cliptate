# WhisperCutPro Transcription Architecture Investigation - Complete Report

**Date:** March 2025  
**Status:** Complete Analysis  
**Files Generated:**
- `ARCHITECTURE_ANALYSIS.md` - Full 598-line technical reference
- `INVESTIGATION_SUMMARY.md` - This document (executive summary)

---

## Quick Reference

### Three Transcription Engines

| Engine | Status | Files | Library | Models |
|--------|--------|-------|---------|--------|
| **Whisper** | Implemented | `WhisperTranscriber.swift` | WhisperKit | base, small, medium, large, v3 |
| **Parakeet** | FluidAudio | `FluidAudioStreamModule.swift` (429L)<br/>`FluidAudioTranscriptionModule.swift` (429L) | FluidAudio | parakeetV2 (EN), parakeetV3 (25 langs) |
| **Qwen3 ASR** | MLX-audio | `Qwen3ASRTranscriber.swift`<br/>`Qwen3StreamingModule.swift` (372L) | mlx-audio-swift | 10+ variants (ASR + ForcedAligner) |

---

## 1. WHERE ENGINES ARE DEFINED & SELECTED

### Definition
**File:** `Sources/Cliptate/Models/DataTypes.swift` (lines 748-802)

```swift
public enum TranscriberType: String, CaseIterable, Identifiable, Codable, Sendable {
  case whisper
  case parakeet = "parakeet"
  case qwen3 = "qwen3"
  
  public func createTranscriber(model: ModelVariant = .base) -> Transcriber {
    switch self {
    case .whisper: return WhisperTranscriber(model: model)
    case .parakeet: return FluidAudioTranscriber(model: parakeetModel)
    case .qwen3: return Qwen3ASRTranscriber(model: qwenModel)
    }
  }
}
```

### Selection Flow

1. **User selects engine + model** → stored in `AppConfiguration`
2. **VoiceTranscriber.start(type:, model:, language:)** called
3. **ModelCacheManager.getASRTranscriber(type:, model:)** retrieves/warms model
4. **Result type-checked & assigned** to `parakeetTranscriber`, `whisperTranscriber`, or `qwen3Transcriber`
5. **startTranscriptionPipeline()** routes to correct module via switch on `currentType`

**Key Files:**
- `VoiceTranscriber.swift` - Main @MainActor controller (lines 160+, 433, 474)
- `ModelCacheManager.swift` - Unified caching for all types
- `DataTypes.swift` - Enum definitions + factory method

---

## 2. MLXAUDIO/QWEN3 SUPPORT - CURRENT IMPLEMENTATION

### Qwen3ASRTranscriber
**File:** `Sources/Cliptate/Services/Qwen3ASRTranscriber.swift`

- **Pattern:** Direct MLX library usage (NOT wrapped by FluidAudio)
- **Imports:** `import MLX`, `import MLXAudioCore`, `import MLXAudioSTT`
- **Protocol:** Implements `Transcriber` + `ChunkTranscriber`

**Key Methods:**
```swift
warmUpModelWithProgress(...) async throws
  → Loads Qwen3ASRModel or Qwen3ForcedAlignerModel from HuggingFace
  → Downloads via mlx-audio-swift
  
transcribeStreamingChunk(samples16k: [Float], language: Language) throws -> String
  → Direct MLX inference on 16kHz mono samples
  → Returns plain text without timestamps
  
transcribeWithProgress(...) async throws -> TranscriptionResult
  → Full file transcription with embedded VAD segmentation
```

**Supported Models:**
- `.qwen3ASR` (0.6B 8-bit, ~600MB)
- `.qwen3ASR06B{4,5,6}bit`, `.qwen3ASR17B{4,5,6,8}bit` (various quantizations)
- `.qwen3ForcedAligner` variants (for word-level timestamps)

### Qwen3StreamingModule
**File:** `Sources/Cliptate/Services/Qwen3StreamingModule.swift` (372 lines)

- **Architecture:** Chunk-based streaming (not continuous like some systems)
- **Chunk Duration:** 2.0 seconds (configurable)
- **Flow:**
  1. `start(language:, using transcriber:)` - Receives warmed transcriber
  2. `configureAudioPipeline()` - Sets up AVAudioEngine input tap
  3. Audio → buffer → chunk → transcribe → accumulate
  4. Callbacks deliver: `onAudioLevel`, `onInterimText`

**Key Code:**
```swift
@MainActor final class Qwen3StreamingModule {
  private var asrTranscriber: Qwen3ASRTranscriber?  // Shared cached instance
  
  func start(language: Language, using transcriber: Qwen3ASRTranscriber) async throws {
    asrTranscriber = transcriber
    try configureAudioPipeline()
  }
  
  private func processChunkBuffer(...) async {
    let text = try asrTranscriber.transcribeStreamingChunk(samples16k: ...)
    accumulatedText += text
    callbacks.onInterimText(accumulatedText)
  }
}
```

### Model Cache Integration
**File:** `Sources/Cliptate/Services/ModelCacheManager.swift` (350+ lines)

```swift
func getASRTranscriber(type: TranscriberType, model: ModelVariant, 
                       progress: @escaping (ModelDownloadProgress) -> Void
) async throws -> Transcriber {
  let key = asrKey(type: type, model: model)
  let resource = try await loadResource(key: key, ...) { [weak self] in
    try await self?.validateModelReadiness(for: model)
    let transcriber = type.createTranscriber(model: model)  // ← Factory dispatch
    try await transcriber.warmUpModelWithProgress { step in progress(step) }
    return .asr(transcriber)
  }
  guard case .asr(let transcriber) = resource else {
    throw ModelCacheError.typeMismatch(expected: "ASR transcriber")
  }
  return transcriber
}
```

**Lifecycle:**
- Lazy loading with concurrent request deduplication
- 10-minute idle timeout (configurable)
- Memory usage tracking

### Documentation
**File:** `docs/plans/2026-02-09-qwen3-asr-integration.md`
- mlx-audio-swift setup instructions
- Model variant definitions
- HuggingFace repository IDs and sizes

---

## 3. CURRENT PARAKEET SUPPORT (FLUIDAUDIO-BASED)

### Architecture

Two separate classes handle Parakeet:

1. **FluidAudioTranscriber** - Implements `Transcriber` protocol for batch/file transcription
2. **ParakeetTranscriptionModule** - Implements streaming transcription logic

### FluidAudioTranscriber
**File:** `Sources/Cliptate/Services/FluidAudioStreamModule.swift`

```swift
public final class FluidAudioTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber {
  private var asrManager: AsrManager?
  private var vadManager: VadManager?
  private let selectedModel: ModelVariant
  
  public init(model: ModelVariant = .parakeetV2)
  
  public func warmUpModelWithProgress(...) async throws {
    asrManager = AsrManager(config: .default)
    let asrVersion = asrModelVersion(for: selectedModel)
    let models = try await AsrModels.load(from: cacheDirectory, version: asrVersion)
    try await asrManager?.initialize(models: models)
    
    vadManager = try await VadManager(config: VadConfig())
  }
  
  public func transcribeWithProgress(...) async throws -> TranscriptionResult {
    // VAD segmentation → transcript each segment → combine results
  }
}
```

**Supported Models:**
- `.parakeetV2` - English only
- `.parakeetV3` - 25 European languages

### ParakeetTranscriptionModule
**File:** `Sources/Cliptate/Services/FluidAudioTranscriptionModule.swift` (429 lines)

```swift
@MainActor
final class ParakeetTranscriptionModule {
  private var streamingAsr: StreamingAsrManager?
  private var streamingModelCache: [AsrModelVersion: AsrModels] = [:]
  
  func start(language: Language, model: ModelVariant) async throws {
    let streaming = StreamingAsrConfig(
      chunkSeconds: 0.1,
      hypothesisChunkSeconds: 1.0,
      leftContextSeconds: 2.0,
      rightContextSeconds: 2.0,
      minContextForConfirmation: 10.0,
      confirmationThreshold: 0.80
    )
    let manager = StreamingAsrManager(config: streaming)
    try await manager.start(models: ..., source: .microphone)
    startForwardingUpdates(from: manager)
    try configureAudioPipeline()
  }
  
  private func processBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) async {
    // Buffer → chunk → streamingAsr.streamAudio() → forwardStreamingUpdate()
  }
}
```

**Audio Pipeline:**
- AVAudioEngine input tap on microphone
- Configurable chunk duration (default 1.0s)
- Audio buffer → scratch buffer → reusable AVAudioPCMBuffer
- Per-chunk audio level calculation for UI visualization

### Usage in VoiceTranscriber
**File:** `Sources/Cliptate/Services/VoiceTranscriber.swift`

```swift
private var parakeetTranscriber: FluidAudioTranscriber?
private lazy var parakeetModule: ParakeetTranscriptionModule = {
  let configuration = ParakeetTranscriptionModule.Configuration(
    chunkDuration: 1.0,
    levelCalculator: micRMSLevel
  )
  let callbacks = ParakeetTranscriptionModule.Callbacks(
    onAudioLevel: { [weak self] level in
      self?.handleMicLevelUpdate(level)
    },
    onInterimText: { [weak self] text in
      self?.handleParakeetStreamUpdate(text)
    }
  )
  return ParakeetTranscriptionModule(...)
}()

// Line 433: configureEngine()
case .parakeet:
  guard let parakeet = transcriber as? FluidAudioTranscriber else { ... }
  parakeetTranscriber = parakeet

// Line 474: startTranscriptionPipeline()
case .parakeet:
  try await parakeetModule.start(language: language, model: model)
```

### FluidAudio Dependencies (9+ files)
- `FluidAudioStreamModule.swift`
- `FluidAudioTranscriptionModule.swift`
- `VoiceTranscriber.swift`
- `WhisperTranscriber.swift`
- `ModelDownloadManager.swift`
- `KokoroTTSService.swift` (for Kokoro TTS, not ASR)
- `TranscriberWarmupCoordinator.swift`
- `SpeechSegmenter.swift`
- `SegmentedAlignmentPipeline.swift`

---

## 4. EXISTING TEST COVERAGE

### Engine Selection & Migration Tests

**TranscriberPoolMigrationTests.swift**
- ✓ Verifies `TranscriberPool.shared` is deprecated with `@available(*, deprecated)`
- ✓ Checks main workflows don't reference legacy pool
- ✓ Files validated: `VoiceTranscriber.swift`, `TranscriberWarmupCoordinator.swift`, etc.

**ModelSelectionUIFlowTests.swift**
- ✓ Tests language fallback when switching models: `.parakeet` + `.parakeetV2` → English fallback from Chinese
- ✓ Tests language preservation when compatible: `.parakeet` + `.parakeetV2` → English stays
- ✓ Uses context: `.asr(type: .parakeet, model: .parakeetV2)`

**DataTypesTests.swift** (ModelVariantAccessLevelTests)
- ✓ All models are currently free (no pro models)
- ✓ Sortformer VAD models classified correctly

### Model Cache Lifecycle Tests

**ModelCacheManagerLifecycleTests.swift**
- ✓ Lazy loading reuses cached instances
- ✓ Idle cleanup removes stale non-ASR entries (10+ min timeout)
- ✓ Concurrent requests deduplicate via shared warming task

**ModelCacheDirectoryTests.swift**
- ✓ MLX cache directory resolution (HF_HUB_CACHE, HF_HOME, defaults)
- ✓ HuggingFace directory handling

### Qwen3-Specific Tests

- **Qwen3PerSegmentAlignTests.swift** - ForcedAligner pipeline tests
- **Qwen3StreamingSpeechAccumulatorTests.swift** - Streaming text accumulation
- **SpeechSegmenterTests.swift** - VAD segmentation
- **ModelDownloadManagerTests.swift** - Download orchestration

### Test Gap Analysis

❌ **NO existing tests** directly cover `ParakeetTranscriptionModule` streaming behavior
- No mock of `StreamingAsrManager`
- No buffer → chunk conversion tests
- No callback delivery tests
- Opportunity for clean TDD implementation

---

## 5. DOCUMENTATION

### Primary Documents

**docs/plans/2026-02-09-qwen3-asr-integration.md**
- mlx-audio-swift dependency setup
- Qwen3ASR/ForcedAligner model variants
- HuggingFace repository IDs & file sizes
- Integration with existing Transcriber protocol

**CLAUDE.md**
- Architecture overview
- Key components: VoiceTranscriber (main), ModelCacheManager (cache), Transcriber protocol
- Development conventions
- **Key Note:** "Use ModelCacheManager.shared instead of TranscriberPool"

### Supporting Documents

- `docs/plans/2026-02-09-qwen3-ui-integration-design.md` - UI layer for Qwen3
- `docs/plans/2026-02-28-vad-asr-align-implementation.md` - VAD + ASR alignment
- `docs/plans/2026-02-28-asr-dictionary-filter-design.md` - Dictionary/filter for qwen3/whisper/parakeet
- `docs/models-page.md` - Model listing & metadata

---

## 6. RECOMMENDED FILES FOR TDD REPLACEMENT

### Priority 1: Core Replacements

**1. FluidAudioStreamModule.swift** (429 lines)
```
Purpose: Implements FluidAudioTranscriber (Transcriber protocol)
Action: Replace with MLX-based Parakeet transcriber
Tests Needed:
  - warmUpModelWithProgress() loads models correctly
  - transcribeChunk() returns correct text
  - Model state transitions (loading → ready)
  - Language validation
```

**2. FluidAudioTranscriptionModule.swift** (429 lines)
```
Purpose: Implements ParakeetTranscriptionModule (streaming)
Action: Replace with MLX-based streaming module
Tests Needed:
  - Audio buffer → chunk conversion
  - Chunk processing rate (handle timing)
  - Callback delivery (onAudioLevel, onInterimText)
  - Pipeline start/stop/reset state management
  - Concurrent chunk processing
```

**3. DataTypes.swift**
```
Purpose: Define TranscriberType enum + model variants
Action: Update if adding new Parakeet models or changing classifications
Tests Needed:
  - isParakeetModel property correctly identifies all Parakeet variants
  - TranscriberType.createTranscriber() dispatches to correct class
  - Model → engine mapping consistency
```

**4. VoiceTranscriber.swift** (750+ lines)
```
Purpose: Main @MainActor transcription controller
Action: 
  - Update imports (FluidAudio → MLXAudioSTT if removing FluidAudio)
  - Verify .parakeet case statements in:
    - configureEngine() [line 433]
    - startTranscriptionPipeline() [line 474]
Tests Needed:
  - Engine configuration dispatches to correct module
  - Module lifecycle (start/stop) works
  - Error handling for mismatched engine types
```

**5. ModelCacheManager.swift** (350+ lines)
```
Status: NO CHANGES NEEDED ✓
Reason: Already handles any Transcriber type via factory pattern
Confidence: High (getASRTranscriber() is engine-agnostic)
```

### Priority 2: Supporting Updates

**6. ModelDownloadManager.swift**
```
Purpose: Currently handles FluidAudio model downloads
Action: May need updates for MLX Parakeet model downloads
Dependency: On whether mlx-audio-swift has model download helpers
```

**7. Package.swift**
```
Purpose: Swift Package Manager configuration
Action: Verify/update dependencies
  - Keep or remove: FluidAudio dependency
  - Ensure: MLXAudioSTT is available
```

### New Test Files to Create

**ParakeetMLXTranscriberTests.swift**
```swift
@Suite("MLX-based Parakeet transcriber")
struct ParakeetMLXTranscriberTests {
  @Test func warmUpLoadsModelsFromHuggingFace() async throws { ... }
  @Test func transcribeChunkReturnsText() async throws { ... }
  @Test func languageValidationWorks() async throws { ... }
  @Test func concurrentWarmupRequestsReuse() async throws { ... }
}
```

**ParakeetMLXStreamingModuleTests.swift**
```swift
@Suite("MLX-based Parakeet streaming")
struct ParakeetMLXStreamingModuleTests {
  @Test func audioPipelineConfiguresSuccessfully() async throws { ... }
  @Test func chunkProcessingCallsTranscriber() async throws { ... }
  @Test func callbacksDeliveredOnMainThread() async throws { ... }
  @Test func bufferCleanupOnStop() async throws { ... }
  @Test func concurrentChunkProcessing() async throws { ... }
}
```

**Update: ModelSelectionUIFlowTests.swift**
```
Add: Tests for new Parakeet implementation
Add: Verify language support still works after migration
```

---

## 7. KEY INSIGHTS FOR REPLACEMENT

### ✓ Protocol Consistency (No Changes Needed!)
Both Qwen3 and new Parakeet must implement:
```swift
public protocol Transcriber: AnyObject, Sendable {
  func warmUpModelWithProgress(...) async throws
  func transcribeWithProgress(...) async throws -> TranscriptionResult
}

public protocol ChunkTranscriber: Transcriber {
  func transcribeChunk(samples: [Float], language: Language) async throws -> String
}
```
**→ No protocol changes required**  
**→ Replacement automatically compatible**

### ✓ Pattern Template Available
`Qwen3StreamingModule` provides perfect reference:
- Chunk-based audio processing (similar to Parakeet's ~0.1s chunks)
- AVAudioEngine input tap → buffer → process → accumulate
- Callback delivery pattern (onAudioLevel, onInterimText)
- @MainActor coordination
**→ Copy this pattern for MLX-based Parakeet**

### ✓ Model Cache Already Works
`ModelCacheManager.getASRTranscriber()`:
- Generic handler for all engine types
- Returns `Transcriber` protocol (engine-agnostic)
- Lazy loading + cleanup automatic
**→ No changes needed if replacement returns Transcriber**

### ⚠ FluidAudio Removal Complexity
If fully removing FluidAudio:
- **9+ files import it** (not just ASR)
- **KokoroTTSService** uses FluidAudio for TTS (separate concern)
- **Options:**
  1. Keep FluidAudio for Kokoro TTS only
  2. Migrate Kokoro to mlx-audio TTS
  3. Remove both FluidAudio + Parakeet together

### ✓ Testing Opportunity
**No existing tests directly cover ParakeetTranscriptionModule**
- Clean slate for TDD
- Reference: `Qwen3StreamingSpeechAccumulatorTests.swift`
- Can implement without legacy test constraints

### ✓ Build System Ready
- mlx-audio-swift already in Package.swift ✓
- No new dependencies needed (unless using new Parakeet models)
- SPM resolution already handles multi-platform builds

---

## 8. SUMMARY COMPARISON TABLE

| Aspect | Whisper | Parakeet (Current) | Qwen3 ASR |
|--------|---------|-------------------|-----------|
| **Implementation Files** | WhisperTranscriber.swift | FluidAudioStreamModule.swift (429L) FluidAudioTranscriptionModule.swift (429L) | Qwen3ASRTranscriber.swift (300L) Qwen3StreamingModule.swift (372L) |
| **Streaming Module** | WhisperStreamingModule | ParakeetTranscriptionModule | Qwen3StreamingModule |
| **Protocol** | Transcriber, ChunkTranscriber | Transcriber, ChunkTranscriber | Transcriber, ChunkTranscriber |
| **Library** | WhisperKit | FluidAudio | mlx-audio-swift |
| **Chunk Processing** | Segment-based | 0.1s chunks + FluidAudio StreamingAsrManager | 2.0s chunks + direct MLX |
| **Audio Pipeline** | Batch file | AVAudioEngine tap | AVAudioEngine tap |
| **Model Variants** | 10+ (base, small, medium, large, v3, v3-turbo, etc.) | 2 (v2 English-only, v3 25-langs) | 10+ (ASR: 6 variants, ForcedAligner: 5 variants) |
| **Cache Integration** | ModelCacheManager ✓ | ModelCacheManager ✓ | ModelCacheManager ✓ |
| **Test Coverage** | Some | None (streaming untested) | Some |
| **Replacement Ready** | - | Yes, ready for MLX-audio | Already MLX-audio ✓ |

---

## 9. Implementation Checklist for TDD

- [ ] **Write unit tests first** for new MLX Parakeet transcriber
- [ ] **Implement warmUpModelWithProgress()** to pass tests
- [ ] **Implement transcribeStreamingChunk()** to pass tests
- [ ] **Write streaming module tests**
- [ ] **Implement audio pipeline** and chunk processing
- [ ] **Update VoiceTranscriber.swift** to use new classes
- [ ] **Verify all tests pass**
- [ ] **Update ModelSelectionUIFlowTests** for new implementation
- [ ] **Test model switching** (parakeet ↔ qwen3, etc.)
- [ ] **Test language fallback** for unsupported languages
- [ ] **Verify memory cleanup** on module reset
- [ ] **Test concurrent streaming** (multiple chunks in flight)
- [ ] **Update imports** throughout codebase
- [ ] **Remove FluidAudio** if no longer needed (or keep for Kokoro TTS)

---

## References

**Full Technical Document:**
- `docs/architecture/archive/ARCHITECTURE_ANALYSIS.md` (598 lines)

**Source Files:**
- `Sources/Cliptate/Models/DataTypes.swift` - Core data types
- `Sources/Cliptate/Services/VoiceTranscriber.swift` - Main controller
- `Sources/Cliptate/Services/ModelCacheManager.swift` - Model lifecycle
- `Sources/Cliptate/Services/FluidAudioStreamModule.swift` - Current Parakeet transcriber
- `Sources/Cliptate/Services/FluidAudioTranscriptionModule.swift` - Current Parakeet streaming
- `Sources/Cliptate/Services/Qwen3ASRTranscriber.swift` - MLX reference impl
- `Sources/Cliptate/Services/Qwen3StreamingModule.swift` - MLX streaming reference

**Documentation:**
- `docs/plans/2026-02-09-qwen3-asr-integration.md` - MLX integration guide
- `CLAUDE.md` - Architecture overview

---

**End of Investigation Summary**
