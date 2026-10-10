# MLX Audio Parakeet Unification Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `FluidAudio`-based Parakeet implementation with an MLX-backed flow that matches the existing `Qwen3` engine architecture, while preserving the `TranscriberType.parakeet` product surface.

**Architecture:** First prove the pinned Swift MLX dependency exposes a real Parakeet runtime surface. If that prerequisite is satisfied, move Parakeet onto the same ASR classification, cache, warmup, download, and dictation flow as other MLX-backed models. Drive each layer with deterministic failing tests before production changes, and keep Whisper and unrelated alignment behavior unchanged.

**Tech Stack:** Swift 6, Swift Testing (`@Suite` / `@Test`), Xcode project `Sources/VoiceFlowPro.xcodeproj`, `MLXAudioSTT` / `MLXAudioCore` / `MLXAudioVAD`, existing `ModelCacheManager`, `ModelDownloadManager`, `VoiceTranscriber`, and `xcodebuild` with scheme `VoicePinkPro`

---

## File Structure

### Runtime files

- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
  - Reclassify Parakeet as MLX-backed where appropriate without changing `provider == .parakeet`
- Create: `Sources/VoiceFlowPro/Services/MLXParakeetRuntimeSupport.swift`
  - Concrete wrapper around the actual Swift Parakeet MLX loader/type discovered in Phase 0
- Create: `Sources/VoiceFlowPro/Services/MLXAudioASRTranscriber.swift`
  - Shared MLX-backed ASR transcriber for Parakeet, Qwen3 ASR, and Qwen3 forced aligner if the extraction stays readable
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
  - Convert to a thin wrapper around `MLXAudioASRTranscriber` or remove after callers move
- Create: `Sources/VoiceFlowPro/Services/MLXAudioModelDownloadSupport.swift`
  - Shared MLX model artifact/cache helper if `Qwen3ModelDownloadManager.swift` would otherwise remain misleading
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`
  - Route Parakeet artifact and readiness checks through MLX-aware logic instead of FluidAudio-only assumptions
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift`
  - Either broaden it into MLX ASR download support or delegate shared logic to `MLXAudioModelDownloadSupport.swift`
- Modify: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
  - Ensure Parakeet is created, cached, and reused through the MLX-backed transcriber path
- Modify: `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift`
  - Key Parakeet streaming warmup by `ModelVariant` instead of `AsrModelVersion`
- Create: `Sources/VoiceFlowPro/Services/ParakeetMLXStreamingModule.swift`
  - MLX-backed live dictation module for Parakeet
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`
  - Stop depending on `FluidAudioTranscriber` for `.parakeet`; route setup/start/stop through the MLX-backed transcriber and streaming module
- Delete or reduce: `Sources/VoiceFlowPro/Models/ModelVariant+AsrModelVersion.swift`
  - Remove only if no remaining production code needs it after migration
- Delete or reduce: `Sources/VoiceFlowPro/Services/FluidAudioStreamModule.swift`
  - Remove Parakeet runtime responsibilities once no production path uses them
- Delete or reduce: `Sources/VoiceFlowPro/Services/FluidAudioTranscriptionModule.swift`
  - Remove Parakeet runtime responsibilities once replaced by MLX-backed streaming

### Test files

- Modify: `Sources/VoiceFlowProTests/Models/DataTypesTests.swift`
  - Lock model classification and supported-model behavior
- Create: `Sources/VoiceFlowProTests/Services/MLXAudioParakeetCapabilityTests.swift`
  - Verify the chosen Swift MLX dependency exposes a concrete Parakeet loading path; this is the hard gate
- Create: `Sources/VoiceFlowProTests/Services/MLXAudioASRTranscriberTests.swift`
  - Assert shared MLX ASR routing for Parakeet, Qwen3 ASR, and forced aligner
- Create: `Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift`
  - Assert `.parakeet` no longer creates `FluidAudioTranscriber`
- Modify: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
  - Cover deterministic Parakeet MLX artifact detection and readiness using injected test doubles
- Create: `Sources/VoiceFlowProTests/Services/ModelCacheManagerParakeetRoutingTests.swift`
  - Assert `ModelCacheManager` creates and reuses Parakeet through the MLX-backed transcriber path
- Modify: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift`
  - Preserve language filtering for `parakeet-v2` and `parakeet-v3`
- Create: `Sources/VoiceFlowProTests/Services/TranscriberWarmupCoordinatorParakeetTests.swift`
  - Assert Parakeet warmup keys off `ModelVariant`, not `AsrModelVersion`
- Create: `Sources/VoiceFlowProTests/Services/VoiceTranscriberParakeetRoutingTests.swift`
  - Assert runtime routing no longer depends on `FluidAudioTranscriber`

## Chunk 1: Runtime prerequisite and model-selection foundation

### Task 1: Verify Swift MLX Parakeet capability before refactoring app code

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/MLXAudioParakeetCapabilityTests.swift`
- Create: `Sources/VoiceFlowPro/Services/MLXParakeetRuntimeSupport.swift`
- Modify: `Sources/VoiceFlowPro.xcodeproj/project.pbxproj` only if the current `mlx-audio-swift` revision does not expose Parakeet support and a newer revision is required
- Modify: `Sources/VoiceFlowPro.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` if the dependency revision changes
- Reference: `docs/superpowers/specs/2026-03-16-mlx-audio-parakeet-unification-design.md`

- [ ] **Step 1: Identify the concrete importable Parakeet runtime entry point in the project-specific checkout**

Run:

```bash
xcodebuild -resolvePackageDependencies -project Sources/VoiceFlowPro.xcodeproj
DERIVED_DATA="$(xcodebuild -showBuildSettings -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro | awk -F' = ' '/BUILD_DIR = / { sub(/\\/Build\\/Products.*/, "", $2); print $2; exit }')"
CHECKOUT="$DERIVED_DATA/SourcePackages/checkouts/mlx-audio-swift"
test -n "$CHECKOUT" && echo "$CHECKOUT"
rg -n "public .*Parakeet|public .*parakeet|fromPretrained" "$CHECKOUT/Sources/MLXAudioSTT" | tee /tmp/parakeet-mlx-symbols.txt
```

Expected:

- Either real Swift Parakeet support is visible in the importable `MLXAudioSTT` sources
- Or there are no hits, which means implementation is blocked pending dependency upgrade or bridge work
- Record the exact public type and public async loading entry point needed to load a Parakeet model, and reuse those symbols verbatim in Step 4
- If the public type exists but the async loading entry point is not public/importable from app code, treat that as unsupported and do not continue

- [ ] **Step 2: Write the failing capability test against a concrete runtime wrapper**

Create `Sources/VoiceFlowProTests/Services/MLXAudioParakeetCapabilityTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("MLX Audio Parakeet capability")
struct MLXAudioParakeetCapabilityTests {
  @Test("project can load and run a Parakeet MLX smoke probe")
  func parakeetMLXSmokeProbe() async throws {
    let result = try await MLXParakeetRuntimeSupport.smokeProbe(
      modelID: "mlx-community/parakeet-tdt-0.6b-v2"
    )
    #expect(result.modelID == "mlx-community/parakeet-tdt-0.6b-v2")
    #expect(result.completedInference)
  }
}
```

Rules:

- `MLXParakeetRuntimeSupport.smokeProbe(modelID:)` must be derived from the actual Swift MLX Parakeet type or loader discovered in Step 1
- Do **not** use a hardcoded `true` flag or placeholder string
- The probe must actually load the chosen model ID and execute a minimal inference path, such as transcribing a generated silence buffer or tiny fixture
- If no such type exists, stop execution and report the blocker instead of continuing the plan

- [ ] **Step 3: Run the capability test to verify the red state**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/MLXAudioParakeetCapabilityTests -parallel-testing-enabled NO
```

Expected:

- FAIL because `MLXParakeetRuntimeSupport` is not defined yet, or because the dependency does not expose a concrete Parakeet runtime that can load/run the target model

- [ ] **Step 4: Add the minimal real capability wrapper, dependency upgrade, or local bridge**

If the checkout proves Swift Parakeet support exists, create `Sources/VoiceFlowPro/Services/MLXParakeetRuntimeSupport.swift`:

```swift
enum MLXParakeetRuntimeSupport {
  struct SmokeProbeResult: Equatable {
    let modelID: String
    let completedInference: Bool
  }

  static func smokeProbe(modelID: String) async throws -> SmokeProbeResult {
    let model = try await ConcreteParakeetMLXLoader.fromPretrained(modelID)
    _ = try await model.transcribe(samples: generatedSilence16k)
    return SmokeProbeResult(modelID: modelID, completedInference: true)
  }
}
```

Use the exact symbol recorded in Step 1 in place of `ConcreteParakeetMLXLoader`.

If upstream Swift support is absent but a project-local bridge is the chosen implementation path:

- create the bridge in `MLXParakeetRuntimeSupport.swift`
- make the test exercise that bridge directly
- note in the commit message or handoff that the migration now depends on the local bridge rather than upstream `mlx-audio-swift`

If the checkout does **not** prove support exists:

- update `Sources/VoiceFlowPro.xcodeproj/project.pbxproj` and the Xcode SwiftPM lockfile to a revision that does
- re-resolve packages
- repeat Step 1
- if support still does not exist, stop execution and report the blocker instead of continuing the plan

- [ ] **Step 5: Verify at least one Parakeet model artifact is consumable by the chosen MLX path**

Use the same test file to validate the chosen runtime can load and run a smoke probe for the target model ID `mlx-community/parakeet-tdt-0.6b-v2`.

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/MLXAudioParakeetCapabilityTests -parallel-testing-enabled NO
```

Expected:

- PASS only if the chosen runtime path can load the target model and complete the smoke inference path without faking the result

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro.xcodeproj/project.pbxproj Sources/VoiceFlowPro.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Sources/VoiceFlowPro/Services/MLXParakeetRuntimeSupport.swift Sources/VoiceFlowProTests/Services/MLXAudioParakeetCapabilityTests.swift
git commit -m "test: verify parakeet mlx runtime availability"
```

### Task 2: Lock model classification and supported-model behavior with failing tests

**Files:**
- Modify: `Sources/VoiceFlowProTests/Models/DataTypesTests.swift`
- Create: `Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift`
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
- Create: `Sources/VoiceFlowPro/Services/MLXAudioASRTranscriber.swift`

- [ ] **Step 1: Extend `DataTypesTests` with the new model expectations**

Add tests like:

```swift
@Test("Parakeet models are treated as MLX-backed ASR models")
func parakeetModelsAreMLXBacked() {
  #expect(ModelVariant.parakeetV2.isMLXAudioModel)
  #expect(ModelVariant.parakeetV3.isMLXAudioModel)
  #expect(ModelVariant.parakeetV2.provider == .parakeet)
}

@Test("Parakeet engine keeps the same supported model list")
func parakeetSupportedModelsStayStable() {
  #expect(TranscriberType.parakeet.supportedModels == [.parakeetV2, .parakeetV3])
}
```

Create `Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("Transcriber factory")
struct TranscriberFactoryTests {
  @Test("parakeet engine no longer creates FluidAudioTranscriber")
  func parakeetFactoryStopsUsingFluidAudio() {
    let transcriber = TranscriberType.parakeet.createTranscriber(model: .parakeetV2)
    #expect(transcriber is MLXAudioASRTranscriber)
    #expect(String(describing: type(of: transcriber)) != "FluidAudioTranscriber")
  }
}
```

- [ ] **Step 2: Run the targeted tests and confirm they fail for the expected reason**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelVariantAccessLevelTests -only-testing:VoiceFlowProTests/TranscriberFactoryTests -parallel-testing-enabled NO
```

Expected:

- FAIL because `isMLXAudioModel` still excludes Parakeet and the factory still returns `FluidAudioTranscriber`

- [ ] **Step 3: Implement the minimal classification and factory changes**

Update `Sources/VoiceFlowPro/Models/DataTypes.swift`:

- make `isMLXAudioModel` include Parakeet ASR models
- add `isMLXAudioASRModel` if it keeps later conditionals cleaner
- keep `provider == .parakeet`

Create the smallest possible `Sources/VoiceFlowPro/Services/MLXAudioASRTranscriber.swift` shell so the factory can go green in this phase:

```swift
public final class MLXAudioASRTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber {
  public let model: ModelVariant

  public init(validatedModel model: ModelVariant) throws {
    self.model = model
  }
}
```

Then update `TranscriberType.createTranscriber(model:)` so `.parakeet` returns that shell instead of `FluidAudioTranscriber`.

Minimal shape:

```swift
var isMLXAudioModel: Bool {
  isParakeetModel || isQwen3Model || isSortformerVADModel
}
```

- [ ] **Step 4: Re-run the targeted tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelVariantAccessLevelTests -only-testing:VoiceFlowProTests/TranscriberFactoryTests -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift Sources/VoiceFlowPro/Services/MLXAudioASRTranscriber.swift Sources/VoiceFlowProTests/Models/DataTypesTests.swift Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift
git commit -m "refactor: classify parakeet as mlx-backed asr"
```

## Chunk 2: Shared MLX ASR transcriber, download, cache, and warmup

### Task 3: Introduce the shared MLX ASR transcriber under TDD

**Files:**
- Create: `Sources/VoiceFlowPro/Services/MLXAudioASRTranscriber.swift`
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- Create: `Sources/VoiceFlowProTests/Services/MLXAudioASRTranscriberTests.swift`
- Create: `Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift`
- Modify: `Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift`

- [ ] **Step 1: Add failing tests for supported-family routing, rejection, and chunk reuse**

Create `Sources/VoiceFlowProTests/Services/MLXAudioASRTranscriberTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("MLXAudioASRTranscriber routing")
struct MLXAudioASRTranscriberTests {
  @Test("parakeet models route through the shared MLX transcriber")
  func parakeetModelsUseSharedTranscriber() {
    let transcriber = try! MLXAudioASRTranscriber(validatedModel: .parakeetV2)
    #expect(transcriber.model == .parakeetV2)
  }

  @Test("qwen3 asr models route through the shared MLX transcriber")
  func qwen3ModelsUseSharedTranscriber() {
    let transcriber = try! MLXAudioASRTranscriber(validatedModel: .qwen3ASR)
    #expect(transcriber.model == .qwen3ASR)
  }

  @Test("non-mlx asr models are rejected")
  func unsupportedModelsAreRejected() {
    #expect(throws: Error.self) {
      _ = try MLXAudioASRTranscriber(validatedModel: .small)
    }
  }

  @Test("chunk transcription is available for streaming reuse")
  func chunkTranscriptionAPIExists() {
    let transcriber = try! MLXAudioASRTranscriber(validatedModel: .parakeetV2)
    #expect(transcriber is any ChunkTranscriber)
  }
}
```

Create `Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("Transcriber factory")
struct TranscriberFactoryTests {
  @Test("parakeet engine uses MLX-backed transcriber")
  func parakeetUsesMLXTranscriber() {
    let transcriber = TranscriberType.parakeet.createTranscriber(model: .parakeetV2)
    #expect(transcriber is MLXAudioASRTranscriber)
    #expect(String(describing: type(of: transcriber)) != "FluidAudioTranscriber")
  }
}
```

Extend `Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift` with one regression case that proves forced-aligner-specific behavior still stays in the Qwen3 path after the shared ASR refactor.

- [ ] **Step 2: Run the transcriber tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/MLXAudioASRTranscriberTests -only-testing:VoiceFlowProTests/TranscriberFactoryTests -only-testing:VoiceFlowProTests/Qwen3PerSegmentAlignTests -parallel-testing-enabled NO
```

Expected:

- FAIL because the new shared transcriber type does not exist yet and the factory still uses `FluidAudioTranscriber`

- [ ] **Step 3: Create `MLXAudioASRTranscriber.swift` with a narrow boundary**

`MLXAudioASRTranscriber.swift` should own only dictation-capable MLX ASR models and must implement the spec-required APIs:

- Parakeet
- Qwen3 ASR
- chunk transcription reuse for streaming
- model warmup with `ModelDownloadProgress`
- offline transcription with `TranscriptionProgress`

Keep forced-aligner-specific behavior in `Qwen3ASRTranscriber.swift` for this change, and only extract helpers if that reduces duplication without creating a large god object.

Start with:

```swift
public final class MLXAudioASRTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber {
  public let model: ModelVariant

  public init(validatedModel model: ModelVariant) throws {
    self.model = model
  }
}
```

Then move loading logic behind model-family switches:

- Parakeet MLX path
- Qwen3 ASR path
- chunk transcription reuse path for live dictation

- [ ] **Step 4: Make `Qwen3ASRTranscriber` the explicit forced-aligner owner**

Required end state:

- `MLXAudioASRTranscriber.swift` handles Parakeet and Qwen3 ASR
- `Qwen3ASRTranscriber.swift` stays as the forced-aligner-specific entry point, delegating shared non-aligner helpers only if needed
- do not delete `Qwen3ASRTranscriber.swift` in this change

- [ ] **Step 5: Update the factory and re-run the transcriber tests**

Update `TranscriberType.createTranscriber(model:)` so `.parakeet` and `.qwen3` return the shared MLX-backed transcriber where appropriate.

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/MLXAudioASRTranscriberTests -only-testing:VoiceFlowProTests/TranscriberFactoryTests -only-testing:VoiceFlowProTests/Qwen3PerSegmentAlignTests -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/MLXAudioASRTranscriber.swift Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift Sources/VoiceFlowProTests/Services/MLXAudioASRTranscriberTests.swift Sources/VoiceFlowProTests/Services/TranscriberFactoryTests.swift Sources/VoiceFlowProTests/Services/Qwen3PerSegmentAlignTests.swift Sources/VoiceFlowPro/Models/DataTypes.swift
git commit -m "refactor: introduce shared mlx asr transcriber"
```

### Task 4: Move download and cache readiness to the MLX-backed Parakeet path

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift`
- Create: `Sources/VoiceFlowPro/Services/MLXAudioModelDownloadSupport.swift`
- Modify: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
- Modify: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
- Create: `Sources/VoiceFlowProTests/Services/ModelCacheManagerParakeetRoutingTests.swift`
- Modify: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift`

- [ ] **Step 1: Add deterministic readiness and language tests**

In the existing `ModelDownloadManagerPermissionTests` suite inside `ModelDownloadManagerTests.swift`, add a test using `StubFileManager` and a temp MLX cache layout derived from the Phase 0 verified runtime/artifact mapping instead of shared global state:

```swift
@Test("parakeet models use mlx-backed artifact readiness checks")
func parakeetUsesMLXArtifactChecks() async {
  let fileManager = StubFileManager(documentDirectory: tempURL)
  let manager = ModelDownloadManager(accessController: MockAccessController(), fileManager: fileManager)
  #expect(await manager.isModelDownloaded(.parakeetV2) == false)

  let parakeetCache = tempURL
    .appendingPathComponent("huggingface/hub/mlx-audio/mlx-community_parakeet-tdt-0.6b-v2", isDirectory: true)
  fileManager.existingDirectories.insert(parakeetCache.path)
  fileManager.directoryListings[parakeetCache.path] = [
    parakeetCache.appendingPathComponent("config.json"),
    parakeetCache.appendingPathComponent("model.safetensors")
  ]

  #expect(await manager.isModelDownloaded(.parakeetV2))
}
```

Create `Sources/VoiceFlowProTests/Services/ModelCacheManagerParakeetRoutingTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("ModelCacheManager Parakeet routing")
struct ModelCacheManagerParakeetRoutingTests {
  @Test("parakeet is created through the shared mlx transcriber path")
  func parakeetUsesSharedMLXTranscriber() async throws {
    await ModelCacheManager.shared.testInstallTranscriberFactory { type, model in
      #expect(type == .parakeet)
      #expect(model == .parakeetV2)
      return try! MLXAudioASRTranscriber(validatedModel: .parakeetV2)
    }
    let transcriber = try await ModelCacheManager.shared.getASRTranscriber(type: .parakeet, model: .parakeetV2) { _ in }
    #expect(transcriber is MLXAudioASRTranscriber)
  }
}
```

Add a `testInstallTranscriberFactory` debug seam in `ModelCacheManager.swift` under `#if DEBUG` so this test does not hit real warmup or download state.

In `ModelCacheManagerLanguageTests.swift`, keep the current language expectations and add a stronger assertion that the Parakeet path still resolves supported languages after the MLX reclassification.

- [ ] **Step 2: Run the targeted tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelDownloadManagerPermissionTests -only-testing:VoiceFlowProTests/ModelCacheManagerLanguageTests -only-testing:VoiceFlowProTests/ModelCacheManagerParakeetRoutingTests -parallel-testing-enabled NO
```

Expected:

- FAIL because Parakeet still routes through FluidAudio-specific artifact and cache assumptions

- [ ] **Step 3: Implement the minimal production changes**

Update production code so that:

- Parakeet readiness flows through MLX-backed model detection
- any download helper with a Qwen3-specific name is either generalized or wrapped by `Sources/VoiceFlowPro/Services/MLXAudioModelDownloadSupport.swift`
- `ModelCacheManager.getASRTranscriber(type:model:progress:)` can create/cache Parakeet with the shared MLX transcriber

- [ ] **Step 4: Re-run the targeted tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelDownloadManagerPermissionTests -only-testing:VoiceFlowProTests/ModelCacheManagerLanguageTests -only-testing:VoiceFlowProTests/ModelCacheManagerParakeetRoutingTests -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelDownloadManager.swift Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift Sources/VoiceFlowPro/Services/MLXAudioModelDownloadSupport.swift Sources/VoiceFlowPro/Services/ModelCacheManager.swift Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift Sources/VoiceFlowProTests/Services/ModelCacheManagerParakeetRoutingTests.swift
git commit -m "refactor: unify mlx download and cache flow for parakeet"
```

### Task 5: Remove FluidAudio-only warmup keys for Parakeet

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift`
- Create: `Sources/VoiceFlowProTests/Services/TranscriberWarmupCoordinatorParakeetTests.swift`
- Delete or reduce: `Sources/VoiceFlowPro/Models/ModelVariant+AsrModelVersion.swift`

- [ ] **Step 1: Write the failing warmup tests using an explicit debug snapshot seam**

Create `Sources/VoiceFlowProTests/Services/TranscriberWarmupCoordinatorParakeetTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("Parakeet warmup coordinator")
struct TranscriberWarmupCoordinatorParakeetTests {
  @Test("parakeet streaming warmup is keyed by model variant")
  @MainActor
  func parakeetWarmupUsesModelVariantKey() async {
    let coordinator = TranscriberWarmupCoordinator.shared
    await coordinator.testResetDebugState()
    await ModelCacheManager.shared.testInstallTranscriberFactory { type, model in
      #expect(type == .parakeet)
      #expect(model == .parakeetV2 || model == .parakeetV3)
      return try! MLXAudioASRTranscriber(validatedModel: model)
    }
    coordinator.scheduleWarmup(for: .parakeet, model: .parakeetV2, reason: .userInitiated, force: true)
    coordinator.ensureStreamingWarmup(for: .parakeet, model: .parakeetV3, force: true)
    await coordinator.testAwaitDebugState()
    let snapshot = await coordinator.debugStreamingState()
    #expect(snapshot.trackedModels.contains(.parakeetV2))
    #expect(snapshot.trackedModels.contains(.parakeetV3))
    #expect(snapshot.currentModel == .parakeetV3)
    #expect(snapshot.preloadedViaModelCacheManager)
  }
}
```

The debug seam lives in `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift` under `#if DEBUG` and returns:

```swift
struct DebugStreamingState: Equatable {
  let currentModel: ModelVariant?
  let trackedModels: Set<ModelVariant>
  let preloadedViaModelCacheManager: Bool
}
```

Also add a `testResetDebugState()` helper under `#if DEBUG` so the singleton state is cleared before each assertion.
Also add a `testAwaitDebugState()` helper under `#if DEBUG` so the test can wait for scheduled warmup requests to be observable without sleeping blindly.
Use the existing `ModelCacheManager.testInstallTranscriberFactory` seam so the warmup test proves Parakeet preload actually flows through `ModelCacheManager`, not a hidden FluidAudio-only branch.

- [ ] **Step 2: Run the warmup tests to verify they fail**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/TranscriberWarmupCoordinatorParakeetTests -parallel-testing-enabled NO
```

Expected:

- FAIL because the debug seam does not exist yet and production warmup is still keyed by `AsrModelVersion`

- [ ] **Step 3: Refactor warmup to key by `ModelVariant`**

Change:

- `streamingTasks: [AsrModelVersion: Task<Void, Never>]`
- `streamingStatuses: [AsrModelVersion: StreamingStatus]`
- `currentStreamingVersion: AsrModelVersion?`

to model-based equivalents:

```swift
private var streamingTasks: [ModelVariant: Task<Void, Never>] = [:]
private var streamingStatuses: [ModelVariant: StreamingStatus] = [:]
private var currentStreamingModel: ModelVariant?
```

Then remove `ModelVariant+AsrModelVersion.swift` if nothing else uses it.

- [ ] **Step 4: Re-run the warmup tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/TranscriberWarmupCoordinatorParakeetTests -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add -A Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift Sources/VoiceFlowProTests/Services/TranscriberWarmupCoordinatorParakeetTests.swift Sources/VoiceFlowPro/Models/ModelVariant+AsrModelVersion.swift
git commit -m "refactor: key parakeet warmup by model variant"
```

## Chunk 3: Live dictation routing, cleanup, and verification

### Task 6: Move Parakeet live dictation off `FluidAudioTranscriber`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ParakeetMLXStreamingModule.swift`
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`
- Create: `Sources/VoiceFlowProTests/Services/VoiceTranscriberParakeetRoutingTests.swift`
- Delete or reduce: `Sources/VoiceFlowPro/Services/FluidAudioTranscriptionModule.swift`
- Delete or reduce: `Sources/VoiceFlowPro/Services/FluidAudioStreamModule.swift`

- [ ] **Step 1: Add failing routing tests around `VoiceTranscriber` configuration and finalization**

Create `VoiceTranscriberParakeetRoutingTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("VoiceTranscriber Parakeet routing")
@MainActor
struct VoiceTranscriberParakeetRoutingTests {
  @Test("parakeet configuration stores an mlx-backed transcriber")
  func parakeetConfigurationUsesMLXTranscriber() async throws {
    let snapshot = await VoiceTranscriber.TestHooks.configureParakeetAndSnapshot()
    #expect(snapshot.parakeetTranscriberType == "MLXAudioASRTranscriber")
    #expect(snapshot.activeStreamingModule == "ParakeetMLXStreamingModule")
  }

  @Test("parakeet live start routes through the mlx streaming module")
  func parakeetStartUsesMLXStreamingModule() async throws {
    let snapshot = await VoiceTranscriber.TestHooks.startParakeetAndSnapshot()
    #expect(snapshot.activeStreamingModule == "ParakeetMLXStreamingModule")
    #expect(snapshot.streamingStartCount == 1)
  }

  @Test("parakeet stop preserves final transcript semantics")
  func parakeetStopPreservesFinalText() async throws {
    let snapshot = await VoiceTranscriber.TestHooks.stopParakeetAndSnapshot(finalText: "hello world")
    #expect(snapshot.activeStreamingModule == "ParakeetMLXStreamingModule")
    #expect(snapshot.streamingStopCount == 1)
    #expect(snapshot.finalTranscript == "hello world")
  }

  @Test("parakeet stop falls back to latest stable text when final text is nil")
  func parakeetStopFallsBackToStableText() async throws {
    let snapshot = await VoiceTranscriber.TestHooks.stopParakeetAndSnapshot(
      finalText: nil,
      latestStableText: "stable text"
    )
    #expect(snapshot.activeStreamingModule == "ParakeetMLXStreamingModule")
    #expect(snapshot.finalTranscript == "stable text")
  }
}
```

The debug seam lives in `VoiceTranscriber.swift` and returns:

```swift
struct DebugParakeetRoutingSnapshot: Equatable {
  let parakeetTranscriberType: String?
  let activeStreamingModule: String?
  let streamingStartCount: Int
  let streamingStopCount: Int
  let finalTranscript: String?
}
```

- [ ] **Step 2: Run the routing test to verify it fails**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/VoiceTranscriberParakeetRoutingTests -parallel-testing-enabled NO
```

Expected:

- FAIL because `VoiceTranscriber` still stores `FluidAudioTranscriber` and uses the old Parakeet module path

- [ ] **Step 3: Add the MLX-backed Parakeet streaming module that consumes the warmed transcriber**

Create `ParakeetMLXStreamingModule.swift` with the same product contract as the old module:

- accepts audio engine, logger, configuration, callbacks
- is initialized with `transcriber: MLXAudioASRTranscriber` supplied by `VoiceTranscriber.configureEngine` after `ModelCacheManager` returns the warmed instance
- provides `start(language:)` and never loads a model internally
- provides `stop() async throws -> String?`
- emits audio level updates and interim text

Use the same chunking/finalization conventions already established in the existing Parakeet and Qwen3 streaming modules. Do not rewrite `VoiceTranscriber` behavior beyond the routing change.

- [ ] **Step 4: Replace Parakeet runtime routing in `VoiceTranscriber`**

Change:

- `private var parakeetTranscriber: FluidAudioTranscriber?`
- casts to `FluidAudioTranscriber`
- startup/stop logic that assumes the old Parakeet runtime

to MLX-backed equivalents, with `private var parakeetTranscriber: MLXAudioASRTranscriber?` as the target end state. Keep existing Whisper and Qwen3 behavior unchanged.

Make the ownership chain explicit:

- `configureEngine(type:model:language:)` fetches and stores the warmed `MLXAudioASRTranscriber`
- the stored transcriber is injected into `ParakeetMLXStreamingModule`
- `startTranscriptionPipeline` only starts streaming and must not trigger any second model load

- [ ] **Step 5: Re-run the routing test**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/VoiceTranscriberParakeetRoutingTests -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ParakeetMLXStreamingModule.swift Sources/VoiceFlowPro/Services/VoiceTranscriber.swift Sources/VoiceFlowProTests/Services/VoiceTranscriberParakeetRoutingTests.swift Sources/VoiceFlowPro/Services/FluidAudioTranscriptionModule.swift Sources/VoiceFlowPro/Services/FluidAudioStreamModule.swift
git commit -m "refactor: move parakeet dictation to mlx pipeline"
```

### Task 7: Run focused regression checks and perform final cleanup

**Files:**
- Modify: any touched files from prior tasks only if regressions require it
- Reference: `docs/superpowers/specs/2026-03-16-mlx-audio-parakeet-unification-design.md`

- [ ] **Step 1: Run the focused feature test batch**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' \
  -only-testing:VoiceFlowProTests/MLXAudioParakeetCapabilityTests \
  -only-testing:VoiceFlowProTests/ModelVariantAccessLevelTests \
  -only-testing:VoiceFlowProTests/MLXAudioASRTranscriberTests \
  -only-testing:VoiceFlowProTests/TranscriberFactoryTests \
  -only-testing:VoiceFlowProTests/Qwen3PerSegmentAlignTests \
  -only-testing:VoiceFlowProTests/ModelDownloadManagerPermissionTests \
  -only-testing:VoiceFlowProTests/ModelCacheManagerParakeetRoutingTests \
  -only-testing:VoiceFlowProTests/ModelCacheManagerLanguageTests \
  -only-testing:VoiceFlowProTests/TranscriberWarmupCoordinatorParakeetTests \
  -only-testing:VoiceFlowProTests/VoiceTranscriberParakeetRoutingTests \
  -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 2: Run adjacent regression tests already covering model selection and migration boundaries**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' \
  -only-testing:VoiceFlowProTests/ModelSelectionUIFlowTests \
  -only-testing:VoiceFlowProTests/TranscriberPoolMigrationTests \
  -parallel-testing-enabled NO
```

Expected:

- PASS

- [ ] **Step 3: Inspect the final diff for leftover FluidAudio Parakeet references**

Run:

```bash
git --no-pager diff --stat
rg -n "FluidAudioTranscriber|ParakeetTranscriptionModule" Sources/VoiceFlowPro
```

Expected:

- no remaining production references to removed Parakeet-only runtime seams such as `FluidAudioTranscriber` or `ParakeetTranscriptionModule`
- any remaining `FluidAudio`, `AsrModelVersion`, `StreamingAsrManager`, or model-mapping usage is intentional and unrelated to active Parakeet runtime behavior

- [ ] **Step 4: Commit the final cleanup**

```bash
git add Sources/VoiceFlowPro Sources/VoiceFlowProTests
git commit -m "feat: unify parakeet with mlx audio asr flow"
```

- [ ] **Step 5: Record verification evidence in the final implementation handoff message**

Include:

- exact MLX runtime support path chosen for Parakeet
- targeted test commands and results
- any intentionally retained `FluidAudio` usages
