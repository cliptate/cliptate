# WhisperCutPro Transcription Engine Architecture Report

## Executive Summary

This document provides a comprehensive analysis of the WhisperCutPro transcription engine architecture, focusing on the current FluidAudio-based Parakeet implementation and the mlx-audio-based Qwen3 ASR support. The application supports three transcription engines: Whisper (OpenAI), Parakeet (FluidAudio), and Qwen3 ASR (mlx-audio).

---

## 1. TRANSCRIPTION ENGINE DEFINITION & SELECTION

### 1.1 Engine Enumeration
**File:** `Sources/Cliptate/Models/DataTypes.swift` (lines 748-802)

```swift
public enum TranscriberType: String, CaseIterable, Identifiable, Codable, Sendable {
  case whisper
  case parakeet = "parakeet"
  case qwen3 = "qwen3"
  
  public var displayName: String { ... }
  public var supportedModels: [ModelVariant] { ... }
  
  public func createTranscriber(model: ModelVariant = .base) -> Transcriber {
    switch self {
    case .whisper: return WhisperTranscriber(model: model)
    case .parakeet: return FluidAudioTranscriber(model: parakeetModel)
    case .qwen3: return Qwen3ASRTranscriber(model: qwenModel)
    }
  }
}
```

### 1.2 Transcriber Protocol
**File:** `Sources/Cliptate/Models/DataTypes.swift` (lines 160-175)

```swift
public protocol Transcriber: AnyObject, Sendable {
  func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws
  func transcribeWithProgress(
    audioPath: String, language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult
}

public protocol ChunkTranscriber: Transcriber {
  func transcribeChunk(samples: [Float], language: Language) async throws -> String
}
```

### 1.3 Engine Selection Flow
**File:** `Sources/Cliptate/Services/VoiceTranscriber.swift` (lines 160+)

**Key Methods:**
- `start(type: TranscriberType, model: ModelVariant, language: Language)` - Main entry point
- `configureEngine()` - Retrieves transcriber from ModelCacheManager and assigns to type-specific property
- `startTranscriptionPipeline()` - Routes to appropriate streaming module

**Selection Logic:**
1. Call `ModelCacheManager.shared.getASRTranscriber(type:, model:)` 
2. Type check and assign to `parakeetTranscriber`, `whisperTranscriber`, or `qwen3Transcriber`
3. Call appropriate module: `parakeetModule.start()`, `whisperModule.start()`, or `qwen3Module.start()`

---

## 2. MLXAUDIO/QWEN3 ASR SUPPORT

### 2.1 Qwen3ASR Transcriber
**File:** `Sources/Cliptate/Services/Qwen3ASRTranscriber.swift`

**Implementation Details:**
- **Pattern:** Direct MLX library usage (not wrapped through FluidAudio)
- **Models:** Two variants supported:
  - `.qwen3ASR` (normal ASR, ~600MB)
  - `.qwen3ForcedAligner` (forced alignment for word-level timestamps, ~400MB)

**Key Methods:**
- `warmUpModelWithProgress()` - Loads from HuggingFace via mlx-audio-swift
- `transcribeStreamingChunk(samples16k:, language:)` - Direct MLX inference on samples
- `transcribeWithProgress(audioPath:)` - Full file transcription with VAD integration

**Imports:**
```swift
import MLX
import MLXAudioCore
import MLXAudioSTT
```

**Model Loading:**
```swift
case _ where modelVariant.isQwen3AlignerModel:
  let model = try await Qwen3ForcedAlignerModel.fromPretrained(
    modelVariant.huggingFaceRepoId
  )
  forcedAlignerModel = model
default:
  let model = try await Qwen3ASRModel.fromPretrained(
    modelVariant.huggingFaceRepoId
  )
  asrModel = model
```

### 2.2 Qwen3 Streaming Module
**File:** `Sources/Cliptate/Services/Qwen3StreamingModule.swift` (372 lines)

**Architecture:**
- **Approach:** Chunk-based processing (differs from Parakeet's native streaming)
- **Chunk Duration:** 2.0 seconds (configurable)
- **Audio Pipeline:** AVAudioEngine with input tap → buffer → transcribe chunk → accumulate

**Key Components:**
```swift
@MainActor final class Qwen3StreamingModule {
  struct Configuration {
    let chunkDuration: Double
    let levelCalculator: ([Float]) -> CGFloat
  }
  
  struct Callbacks {
    let onAudioLevel: (CGFloat) -> Void
    let onInterimText: (String) -> Void
  }
  
  private var asrTranscriber: Qwen3ASRTranscriber?  // Shared cached instance
}
```

**Flow:**
1. `start(language:, using transcriber:)` - Receives warmed transcriber from cache
2. `configureAudioPipeline()` - Sets up AVAudioEngine input tap
3. `processBuffer()` - Accumulates audio into chunk buffer
4. `processChunkBuffer()` - Calls `transcriber.transcribeStreamingChunk()`
5. Callbacks deliver audio level and interim text to UI

### 2.3 Model Variants (MLXAudio)
**File:** `Sources/Cliptate/Models/DataTypes.swift`

```swift
// ASR Models
case qwen3ASR = "qwen3-asr-0.6b-8bit"
case qwen3ASR06B4bit = "qwen3-asr-0.6b-4bit"
case qwen3ASR06B5bit = "qwen3-asr-0.6b-5bit"
case qwen3ASR06B6bit = "qwen3-asr-0.6b-6bit"
case qwen3ASR06Bbf16 = "qwen3-asr-0.6b-bf16"
case qwen3ASR17B4bit = "qwen3-asr-1.7b-4bit"
// ... more variants

// Forced Aligner Models
case qwen3ForcedAligner = "qwen3-forcedaligner-0.6b-4bit"
case qwen3ForcedAligner06B5bit = "qwen3-forcedaligner-0.6b-5bit"
// ... more variants

var isQwen3ASRModel: Bool { ... }
var isQwen3AlignerModel: Bool { ... }
var isQwen3Model: Bool { isQwen3ASRModel || isQwen3AlignerModel }
var isMLXAudioModel: Bool { isQwen3Model || isSortformerVADModel }
```

### 2.4 Model Cache Integration
**File:** `Sources/Cliptate/Services/ModelCacheManager.swift` (150+)

**ASR Transcriber Retrieval:**
```swift
func getASRTranscriber(
  type: TranscriberType,
  model: ModelVariant,
  progress: @escaping (ModelDownloadProgress) -> Void
) async throws -> Transcriber {
  let key = asrKey(type: type, model: model)
  let resource = try await loadResource(
    key: key,
    displayName: "\(type.displayName) • \(model.displayName)",
    estimatedMemoryMB: model.fileSize
  ) { [weak self] in
    try await self?.validateModelReadiness(for: model)
    let transcriber = type.createTranscriber(model: model)
    try await transcriber.warmUpModelWithProgress { step in progress(step) }
    return .asr(transcriber)
  }
  guard case .asr(let transcriber) = resource else {
    throw ModelCacheError.typeMismatch(expected: "ASR transcriber")
  }
  return transcriber
}
```

**Forced Aligner Retrieval:**
```swift
func getAlignTranscriber(
  model: ModelVariant,
  progress: @escaping (ModelDownloadProgress) -> Void
) async throws -> Qwen3ASRTranscriber {
  guard model.isQwen3AlignerModel else {
    throw ModelCacheError.invalidAlignModel(model)
  }
  // Load via getASRTranscriber, returns Qwen3ASRTranscriber
}
```

**Lifecycle Management:**
- Lazy loading with concurrent request deduplication
- 10-minute idle timeout (configurable via `updateCleanupTimeout()`)
- Memory usage tracking per model

### 2.5 Documentation
**File:** `docs/plans/2026-02-09-qwen3-asr-integration.md`

- mlx-audio-swift dependency integration guide
- Model variant definitions
- Integration with existing Transcriber protocol

---

## 3. PARAKEET SUPPORT (FLUIDAUDIO-BASED)

### 3.1 Current Parakeet Implementation

**File Structure:**
- `FluidAudioTranscriber` (Transcriber protocol impl): `FluidAudioStreamModule.swift`
- `ParakeetTranscriptionModule` (Streaming logic): `FluidAudioTranscriptionModule.swift` (429 lines)
- Usage in `VoiceTranscriber.swift`: lines 46, 63, 433, 474

### 3.2 FluidAudioTranscriber (The Protocol Impl)
**File:** `Sources/Cliptate/Services/FluidAudioStreamModule.swift` (lines 1-19)

```swift
public final class FluidAudioTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber {
  private var asrManager: AsrManager?
  private var vadManager: VadManager?
  private let selectedModel: ModelVariant
  
  public init(model: ModelVariant = .parakeetV2) { ... }
  
  public func warmUpModelWithProgress(...) async throws {
    // Initialize AsrManager and VadManager
    // Load ASR + VAD models from FluidAudio cache
  }
  
  public func transcribeWithProgress(...) async throws -> TranscriptionResult {
    // Uses VAD for segmentation, then transcribes each segment
  }
}
```

**Model Support:**
```swift
private func asrModelVersion(for model: ModelVariant) -> AsrModelVersion {
  switch model {
  case .parakeetV2: return .v2
  case .parakeetV3: return .v3
  default: return .v2
  }
}
```

### 3.3 ParakeetTranscriptionModule (Streaming Module)
**File:** `Sources/Cliptate/Services/FluidAudioTranscriptionModule.swift` (429 lines)

**Architecture:**
- Uses FluidAudio's `StreamingAsrManager` (not MLX)
- Native streaming with confirmation thresholds
- Separate VAD not used (FluidAudio includes VAD internally)

**Key Components:**
```swift
@MainActor
final class ParakeetTranscriptionModule {
  struct Configuration {
    let chunkDuration: Double
    let levelCalculator: ([Float]) -> CGFloat
  }
  
  struct Callbacks {
    let onAudioLevel: (CGFloat) -> Void
    let onInterimText: (String) -> Void
  }
  
  private var streamingAsr: StreamingAsrManager?
  private var streamingModelCache: [AsrModelVersion: AsrModels] = [:]
}
```

**Flow:**
```swift
func start(language: Language, model: ModelVariant) async throws {
  let streaming = StreamingAsrConfig(
    chunkSeconds: configuration.chunkDuration,
    hypothesisChunkSeconds: 1.0,
    leftContextSeconds: 2.0,
    rightContextSeconds: 2.0,
    minContextForConfirmation: 10.0,
    confirmationThreshold: 0.80
  )
  let manager = StreamingAsrManager(config: streaming)
  streamingAsr = manager
  
  let asrVersion = model.streamingAsrModelVersion ?? .v3
  let streamingModels = try await loadStreamingModels(for: asrVersion)
  try await manager.start(models: streamingModels, source: .microphone)
  
  startForwardingUpdates(from: manager)
  try configureAudioPipeline()
}
```

**Audio Chunking:**
- Configurable chunk duration (default 1.0s)
- Audio buffer → scratch buffer → reusable AVAudioPCMBuffer
- Per-chunk level calculation for visualization

### 3.4 Model Variants (Parakeet)
**File:** `Sources/Cliptate/Models/DataTypes.swift`

```swift
// Parakeet Models
case parakeetV2 = "parakeet-v2"
case parakeetV3 = "parakeet-v3"

var isParakeetModel: Bool {
  switch self {
  case .parakeetV2, .parakeetV3: return true
  default: return false
  }
}

var provider: TranscriberType {
  if isParakeetModel { return .parakeet }
  ...
}
```

**Supported Languages:**
- Parakeet v2: English only
- Parakeet v3: 25 European languages

### 3.5 FluidAudio Imports
**Used in:**
- `FluidAudioStreamModule.swift`
- `FluidAudioTranscriptionModule.swift`
- `VoiceTranscriber.swift`
- `WhisperTranscriber.swift`
- `ModelDownloadManager.swift`
- `KokoroTTSService.swift` (for TTS, not ASR)
- `TranscriberWarmupCoordinator.swift`
- `SpeechSegmenter.swift`

---

## 4. EXISTING TESTS

### 4.1 Engine/Transcriber Tests
**Test Files:**

1. **TranscriberPoolMigrationTests.swift**
   - Verifies legacy `TranscriberPool.shared` is deprecated
   - Ensures main workflows don't reference old pool
   - Files checked: `VoiceTranscriber`, `TranscriberWarmupCoordinator`, `AICutView`, etc.

2. **ModelSelectionUIFlowTests.swift**
   - Tests language fallback when switching between `.parakeet` and `.qwen3`
   - Tests language preservation across model context changes
   - Context: `.asr(type: .parakeet, model: .parakeetV2)`

3. **DataTypesTests.swift** (`ModelVariantAccessLevelTests`)
   - Verifies all models are currently free (no pro models yet)
   - Sortformer VAD models classified correctly

4. **ModelCacheManagerLifecycleTests.swift**
   - Lazy loading reuses cached instances
   - Idle cleanup removes stale non-ASR entries
   - Concurrent requests deduplication

5. **ModelCacheDirectoryTests.swift**
   - MLX audio cache directory resolution
   - HuggingFace cache directory handling

### 4.2 Service Tests
- `Qwen3PerSegmentAlignTests.swift` - Alignment pipeline tests
- `Qwen3StreamingSpeechAccumulatorTests.swift` - Streaming accumulation
- `SpeechSegmenterTests.swift` - VAD segmentation
- `ModelAccessControllerTests.swift` - Subscription checks
- `ModelDownloadManagerTests.swift` - Download orchestration

---

## 5. DOCUMENTATION

### 5.1 Planning Documents
**File:** `docs/plans/2026-02-09-qwen3-asr-integration.md`
- mlx-audio-swift dependency setup
- Qwen3ASR model variants
- Integration with existing Transcriber protocol
- HuggingFace model IDs and sizes

**Other Relevant Docs:**
- `docs/plans/2026-02-09-qwen3-ui-integration-design.md` - UI integration
- `docs/plans/2026-02-28-asr-dictionary-filter-design.md` - Dictionary/filter applied to qwen3/whisper/parakeet flows
- `docs/plans/2026-02-28-vad-asr-align-implementation.md` - VAD + ASR alignment pipeline
- `CLAUDE.md` - Architecture overview and development conventions

### 5.2 CLAUDE.md Key Points
- VoiceTranscriber is the main @MainActor controller
- ModelCacheManager handles lazy loading and lifecycle
- Three transcriber types: Whisper (WhisperKit), Parakeet (FluidAudio), Qwen3 (MLXAudio)
- Use ModelCacheManager.shared instead of deprecated TranscriberPool

---

## 6. TDD IMPLEMENTATION RECOMMENDATIONS

### 6.1 Primary Files for Changes

**High Priority (Core Architecture):**

1. **`DataTypes.swift`** (1000+ lines)
   - Update `TranscriberType` enum if adding new Parakeet variant
   - Model variant classifications (update `isParakeetModel` logic if needed)
   - File path: `Sources/Cliptate/Models/DataTypes.swift`

2. **`FluidAudioTranscriber.swift`** (429 lines)
   - Replace FluidAudio imports with MLX imports
   - Implement Qwen3-based streaming for Parakeet
   - File path: `Sources/Cliptate/Services/FluidAudioStreamModule.swift`

3. **`ParakeetTranscriptionModule.swift`** (429 lines)
   - Replace FluidAudio's StreamingAsrManager with MLX-based Parakeet implementation
   - File path: `Sources/Cliptate/Services/FluidAudioTranscriptionModule.swift`

4. **`VoiceTranscriber.swift`** (750+ lines)
   - Update imports from FluidAudio to MLXAudioSTT (if removing FluidAudio)
   - Verify case statements still match after changes
   - File path: `Sources/Cliptate/Services/VoiceTranscriber.swift`

5. **`ModelCacheManager.swift`** (350+ lines)
   - Already handles Qwen3ASRTranscriber in `getAlignTranscriber()`
   - Verify Parakeet creation still works or update
   - File path: `Sources/Cliptate/Services/ModelCacheManager.swift`

**Medium Priority (Supporting):**

6. **`ModelDownloadManager.swift`**
   - Currently handles FluidAudio model downloads
   - May need updates if switching to mlx-audio for Parakeet downloads

7. **`Qwen3ModelDownloadManager.swift`**
   - Already handles MLX model downloads
   - Reference for implementation pattern

8. **Package.swift**
   - Verify dependencies (FluidAudio vs MLXAudioSTT)
   - Add/remove packages as needed

**Test Files to Create/Update:**

9. **New: `ParakeetMLXTranscriberTests.swift`**
   - Test MLX-based Parakeet implementation
   - Mock MLX dependencies
   - Test streaming callbacks and state management

10. **New: `ParakeetMLXStreamingModuleTests.swift`**
    - Test chunk processing
    - Test audio pipeline setup/teardown
    - Test concurrent audio + transcription

11. **Update: `ModelSelectionUIFlowTests.swift`**
    - Add tests for new Parakeet implementation
    - Verify language support still works

12. **Update: `TranscriberPoolMigrationTests.swift`**
    - Verify no legacy FluidAudio-specific code remains

### 6.2 Test Strategy (TDD Approach)

**Phase 1: Unit Tests**
```
- ParakeetMLXTranscriber.warmUpModelWithProgress()
- ParakeetMLXTranscriber.transcribeStreamingChunk()
- ParakeetMLXStreamingModule initialization
- Audio buffer → chunk conversion
- Streaming callback delivery
```

**Phase 2: Integration Tests**
```
- Engine selection: TranscriberType.parakeet → ParakeetMLXTranscriber
- ModelCacheManager integration
- Streaming pipeline end-to-end
- Language support verification
```

**Phase 3: E2E Tests**
```
- Full transcription workflow with UI
- Multi-engine switching
- Model caching and reuse

```

### 6.3 Key Test Files & Patterns

**Reference Qwen3 Tests:**
- `Qwen3PerSegmentAlignTests.swift` - How to test MLX-based transcription
- `Qwen3StreamingSpeechAccumulatorTests.swift` - Streaming state management

**Reference Integration Tests:**
- `ModelSelectionUIFlowTests.swift` - UI + model context testing
- `TranscriberPoolMigrationTests.swift` - Migration verification

**Testing Framework:**
- Use Swift's `@Suite` and `@Test` (not XCTest)
- Mock dependencies with `@unchecked Sendable` box types
- Actor-based concurrency testing with async/await

---

## 7. SUMMARY TABLE

| Component | Current Implementation | File(s) | Approach |
|-----------|----------------------|---------|----------|
| **Engine Selection** | `TranscriberType` enum + factory | `DataTypes.swift` | Factory pattern with type dispatch |
| **Parakeet Transcriber** | `FluidAudioTranscriber` | `FluidAudioStreamModule.swift` | FluidAudio library (ASR + VAD) |
| **Parakeet Streaming** | `ParakeetTranscriptionModule` | `FluidAudioTranscriptionModule.swift` | FluidAudio's StreamingAsrManager |
| **Qwen3 Transcriber** | `Qwen3ASRTranscriber` | `Qwen3ASRTranscriber.swift` | Direct MLX library usage |
| **Qwen3 Streaming** | `Qwen3StreamingModule` | `Qwen3StreamingModule.swift` | Chunk-based with MLX inference |
| **Model Cache** | `ModelCacheManager` | `ModelCacheManager.swift` | Actor-based lazy loading + cleanup |
| **Model Variants** | Enum cases + properties | `DataTypes.swift` | Classification via computed properties |
| **Download Manager** | Type-specific managers | `ModelDownloadManager.swift`, `Qwen3ModelDownloadManager.swift` | Separate per engine |

---

## 8. KEY INSIGHTS FOR REPLACEMENT

1. **Protocol Consistency:** Both implementations must conform to existing `Transcriber` and `ChunkTranscriber` protocols—no changes needed to protocol definitions.

2. **Streaming Module Pattern:** `Qwen3StreamingModule` provides a good template for chunk-based streaming; Parakeet's mlx-audio replacement should follow similar structure.

3. **Model Caching:** `ModelCacheManager` already handles multiple transcriber types via `CachedResource` enum and `loadResource()` method—no changes needed if Parakeet still returns a `Transcriber`.

4. **FluidAudio Dependency:** Currently pervasive (9+ files import it). If fully removing, must also update:
   - KokoroTTSService (uses FluidAudio for TTS)
   - SpeechSegmenter, TranscriberWarmupCoordinator
   - Package.swift dependencies

5. **Test Migration Path:** No existing tests directly mock Parakeet; migration tests mainly check that old pool is deprecated. New tests can focus on mlx-audio-based implementation without legacy baggage.

---

## Appendix: File Locations

```
Sources/Cliptate/
├── Models/
│   ├── DataTypes.swift (TranscriberType, ModelVariant, Transcriber protocol)
│   ├── AppConfiguration.swift (engine type + model selection storage)
│   └── ModelVariant+AsrModelVersion.swift
├── Services/
│   ├── VoiceTranscriber.swift (Main @MainActor controller)
│   ├── FluidAudioStreamModule.swift (FluidAudioTranscriber impl)
│   ├── FluidAudioTranscriptionModule.swift (ParakeetTranscriptionModule, StreamingAsrManager wrapper)
│   ├── Qwen3ASRTranscriber.swift (MLX-based transcriber)
│   ├── Qwen3StreamingModule.swift (Chunk-based streaming with MLX)
│   ├── ModelCacheManager.swift (Unified cache for all engines)
│   ├── ModelDownloadManager.swift (FluidAudio downloads)
│   ├── Qwen3ModelDownloadManager.swift (MLX-audio downloads)
│   ├── WhisperTranscriber.swift (WhisperKit impl)
│   ├── WhisperStreamingModule.swift
│   ├── TranscriberPool.swift (DEPRECATED)
│   ├── TranscriberWarmupCoordinator.swift
│   └── [other services]
├── Views/
│   ├── ModelsView.swift
│   ├── ModelSelectionView.swift
│   ├── VoiceToTextView.swift
│   └── [other views]
└── Utilities/
    └── [utilities]

Sources/CliptateTests/
├── Integration/
│   ├── TranscriberPoolMigrationTests.swift
│   └── ModelSelectionUIFlowTests.swift
├── Services/
│   ├── ModelCacheManagerLifecycleTests.swift
│   ├── Qwen3PerSegmentAlignTests.swift
│   ├── Qwen3StreamingSpeechAccumulatorTests.swift
│   └── [other service tests]
├── Models/
│   ├── DataTypesTests.swift
│   └── [other model tests]
└── [other tests]

docs/plans/
├── 2026-02-09-qwen3-asr-integration.md
├── 2026-02-09-qwen3-ui-integration-design.md
└── [other plans]
```

