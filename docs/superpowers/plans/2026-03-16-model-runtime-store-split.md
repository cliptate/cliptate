# Model Runtime Store Split Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ModelCacheManager` with focused runtime, lifecycle, and language-support services while preserving preload/cache-status UI and current runtime reuse behavior.

**Architecture:** Introduce dedicated stores for ASR, align, and TTS runtime loading, plus separate lifecycle aggregation and language-support services. Migrate callers incrementally so behavior remains stable while the monolithic cache actor is reduced and then removed.

**Tech Stack:** Swift, SwiftUI, actors, async/await, Swift Testing, Xcodebuild

**Verified command note:** Use the existing verified Xcode scheme `VoicePinkPro` for all `xcodebuild` commands in this plan.

---

## File Structure

- Create: `Sources/VoiceFlowPro/Services/ASRRuntimeStore.swift`
  - Own ASR transcriber runtime loading, warmup deduplication, readiness checks, and access tracking.
- Create: `Sources/VoiceFlowPro/Services/AlignRuntimeStore.swift`
  - Own Qwen3 aligner runtime loading, preload, reuse, and access tracking.
- Create: `Sources/VoiceFlowPro/Services/TTSRuntimeStore.swift`
  - Own Kokoro / MLX TTS runtime loading, preload, reuse, and access tracking.
- Create: `Sources/VoiceFlowPro/Services/ModelLifecycleStore.swift`
  - Aggregate runtime status, memory estimates, last access, errors, and clear-idle behaviors for UI.
- Create: `Sources/VoiceFlowPro/Services/ModelLanguageSupportService.swift`
  - Serve supported-language lookups and caching by model context.
- Create: `Sources/VoiceFlowPro/Services/ModelRuntimeTypes.swift`
  - Hold shared types currently coupled to `ModelCacheManager`, such as `ModelLifecycleState`, `ModelLifecycleKind`, `ModelLifecycleKey`, `ModelLifecycleStatus`, `ModelCacheSnapshot`, `ModelCachePerformanceSnapshot`, `ModelLanguageContext`, and `ModelCacheError`.
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`
  - Replace `ModelCacheManager` calls with `ASRRuntimeStore`.
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`
  - Replace ASR runtime loading calls with `ASRRuntimeStore`.
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
  - Replace ASR and aligner loading calls with `ASRRuntimeStore` / `AlignRuntimeStore`.
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
  - Route preload/retry/clear-cache/status refresh through new lifecycle/runtime stores.
- Modify: `Sources/VoiceFlowPro/Views/ModelAwareLanguageSelectionView.swift`
  - Switch language queries to `ModelLanguageSupportService`.
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`
  - Refresh lifecycle state via `ModelLifecycleStore`.
- Modify: `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift`
  - Depend on `ASRRuntimeStore` instead of `ModelCacheManager`.
- Modify: `Sources/VoiceFlowPro/VoiceFlowPro.swift`
  - Bootstrap timeout / initial preload through new stores.
- Delete: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
  - Remove after all callers and tests are migrated.
- Test: `Sources/VoiceFlowProTests/Services/ASRRuntimeStoreTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/AlignRuntimeStoreTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/TTSRuntimeStoreTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelLifecycleStoreTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelLanguageSupportServiceTests.swift`
- Modify Test: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift`
  - Replace with new runtime/lifecycle store coverage or rename if needed.
- Modify Test: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift`
  - Replace with language-support service tests or rename if needed.

## Chunk 1: Runtime Stores and Language Service

### Task 0: Extract shared runtime and lifecycle types

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ModelRuntimeTypes.swift`
- Modify: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift`

- [ ] **Step 1: Write the failing compile-first migration change**

Move the shared enums/structs out of `ModelCacheManager.swift` into `ModelRuntimeTypes.swift` and keep imports compiling by updating references in place.

Minimal extracted surface:

```swift
enum ModelLifecycleState: Equatable, Sendable
enum ModelLifecycleKind: String, Sendable
struct ModelLifecycleKey: Hashable, Sendable
struct ModelLifecycleStatus: Identifiable, Sendable
struct ModelCacheSnapshot: Sendable
struct ModelCachePerformanceSnapshot: Sendable
enum ModelLanguageContext: Sendable
enum ModelCacheError: LocalizedError, Equatable
```

Copy the existing definitions unchanged first; do not redesign them in this extraction step.

- [ ] **Step 2: Run the lifecycle tests as a no-behavior-change check**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/ModelCacheManagerLifecycleTests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS if the extraction is clean; otherwise FAIL with compile/reference errors that must be fixed before continuing.

- [ ] **Step 3: Complete the extraction**

Ensure all existing references build against `ModelRuntimeTypes.swift` without changing behavior.

- [ ] **Step 4: Run the lifecycle tests again**

Run: same command as Step 2

Expected: PASS, proving the shared types are available before store migration starts.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelRuntimeTypes.swift Sources/VoiceFlowPro/Services/ModelCacheManager.swift Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift
git commit -m "refactor: extract shared model runtime types"
```

### Task 1: Create `ASRRuntimeStore`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ASRRuntimeStore.swift`
- Test: `Sources/VoiceFlowProTests/Services/ASRRuntimeStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("ASRRuntimeStore")
struct ASRRuntimeStoreTests {
  @Test("deduplicates concurrent ASR loads for the same model")
  func deduplicatesConcurrentLoads() async throws {
    let type = TranscriberType.whisper
    let model = ModelVariant.base
    let store = ASRRuntimeStore.testInstance()

    async let first = store.testLoadMockTranscriber(type: type, model: model, delayNanoseconds: 150_000_000)
    async let second = store.testLoadMockTranscriber(type: type, model: model, delayNanoseconds: 150_000_000)
    _ = try await (first, second)

    let key = ASRRuntimeStore.testKey(type: type, model: model)
    let loadCount = await store.testLoadCount(for: key)
    #expect(loadCount == 1)
    #expect(await store.hasReadyTranscriber(type: type, model: model))
  }

  @Test("reports loading state while warmup is in flight")
  func reportsLoadingState() async throws {
    let type = TranscriberType.whisper
    let model = ModelVariant.base
    let store = ASRRuntimeStore.testInstance()

    let task = Task {
      try await store.testLoadMockTranscriber(type: type, model: model, delayNanoseconds: 300_000_000)
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(await store.isLoading(type: type, model: model))
    _ = try await task.value
    #expect(!(await store.isLoading(type: type, model: model)))
  }

  @Test("preload stores a ready ASR transcriber")
  func preloadMarksModelReady() async throws {
    let store = ASRRuntimeStore.testInstance()
    try await store.testPreloadMockTranscriber(type: .whisper, model: .base)
    #expect(await store.hasReadyTranscriber(type: .whisper, model: .base))
  }

  @Test("preload surfaces failures")
  func preloadPropagatesFailure() async throws {
    let store = ASRRuntimeStore.testInstance()
    await #expect(throws: Error.self) {
      try await store.testPreloadMockTranscriber(type: .whisper, model: .base, failMessage: "intentional preload failure")
    }
  }

  @Test("failed preload transitions to error and recovers on retry")
  func preloadRecoversAfterFailure() async throws {
    let store = ASRRuntimeStore.testInstance()
    await #expect(throws: Error.self) {
      try await store.testPreloadMockTranscriber(type: .whisper, model: .base, failMessage: "intentional preload failure")
    }
    try await store.testPreloadMockTranscriber(type: .whisper, model: .base)
    #expect(await store.hasReadyTranscriber(type: .whisper, model: .base))
  }

  @Test("noteAccess updates last access timestamp")
  func noteAccessUpdatesTimestamp() async throws {
    let store = ASRRuntimeStore.testInstance()
    try await store.testPreloadMockTranscriber(type: .whisper, model: .base)
    let before = await store.testLastAccess(type: .whisper, model: .base)
    try await Task.sleep(nanoseconds: 10_000_000)
    await store.noteAccess(type: .whisper, model: .base)
    let after = await store.testLastAccess(type: .whisper, model: .base)
    #expect(after > before)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/ASRRuntimeStoreTests CODE_SIGNING_ALLOWED=NO`

Expected: FAIL because `ASRRuntimeStore` does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
actor ASRRuntimeStore {
  static let shared = ASRRuntimeStore()

  func getTranscriber(
    type: TranscriberType,
    model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Transcriber

  func preload(type: TranscriberType, model: ModelVariant) async throws
  func hasReadyTranscriber(type: TranscriberType, model: ModelVariant) -> Bool
  func isLoading(type: TranscriberType, model: ModelVariant) -> Bool
  func noteAccess(type: TranscriberType, model: ModelVariant)
}
```

Also add test-only helpers mirroring the old `ModelCacheManagerLifecycleTests` seam so concurrency and state behavior can be verified without loading real models.

Required test helpers:

```swift
static func testInstance() -> ASRRuntimeStore
static func testKey(type: TranscriberType, model: ModelVariant) -> ModelLifecycleKey
func testLoadMockTranscriber(...)
func testPreloadMockTranscriber(...)
func testLoadCount(for key: ModelLifecycleKey) async -> Int
func testLastAccess(type: TranscriberType, model: ModelVariant) async -> Date
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same command as Step 2

Expected: PASS for `ASRRuntimeStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ASRRuntimeStore.swift Sources/VoiceFlowProTests/Services/ASRRuntimeStoreTests.swift
git commit -m "refactor: add ASR runtime store"
```

### Task 2: Create `AlignRuntimeStore`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/AlignRuntimeStore.swift`
- Test: `Sources/VoiceFlowProTests/Services/AlignRuntimeStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("AlignRuntimeStore")
struct AlignRuntimeStoreTests {
  @Test("rejects non-align models")
  func rejectsInvalidModel() async throws {
    let store = AlignRuntimeStore.testInstance()
    await #expect(throws: ModelCacheError.self) {
      try await store.getAligner(model: .base) { _ in }
    }
  }

  @Test("deduplicates concurrent aligner warmups")
  func deduplicatesAlignerWarmups() async throws {
    let store = AlignRuntimeStore.testInstance()

    async let first = store.testLoadMockAligner(model: .qwen3ForcedAligner, delayNanoseconds: 150_000_000)
    async let second = store.testLoadMockAligner(model: .qwen3ForcedAligner, delayNanoseconds: 150_000_000)
    _ = try await (first, second)

    #expect(await store.testLoadCount(model: .qwen3ForcedAligner) == 1)
    #expect(await store.hasReadyAligner(model: .qwen3ForcedAligner))
  }

  @Test("reports loading state for an in-flight aligner warmup")
  func reportsLoadingState() async throws {
    let store = AlignRuntimeStore.testInstance()
    let task = Task {
      try await store.testLoadMockAligner(model: .qwen3ForcedAligner, delayNanoseconds: 300_000_000)
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(await store.isLoading(model: .qwen3ForcedAligner))
    _ = try await task.value
    #expect(!(await store.isLoading(model: .qwen3ForcedAligner)))
  }

  @Test("preload stores a ready aligner")
  func preloadMarksAlignerReady() async throws {
    let store = AlignRuntimeStore.testInstance()
    try await store.testPreloadMockAligner(model: .qwen3ForcedAligner)
    #expect(await store.hasReadyAligner(model: .qwen3ForcedAligner))
  }

  @Test("preload surfaces aligner failures")
  func preloadPropagatesFailure() async throws {
    let store = AlignRuntimeStore.testInstance()
    await #expect(throws: Error.self) {
      try await store.testPreloadMockAligner(
        model: .qwen3ForcedAligner,
        failMessage: "intentional preload failure"
      )
    }
  }

  @Test("failed aligner preload recovers on retry")
  func preloadRecoversAfterFailure() async throws {
    let store = AlignRuntimeStore.testInstance()
    await #expect(throws: Error.self) {
      try await store.testPreloadMockAligner(
        model: .qwen3ForcedAligner,
        failMessage: "intentional preload failure"
      )
    }
    try await store.testPreloadMockAligner(model: .qwen3ForcedAligner)
    #expect(await store.hasReadyAligner(model: .qwen3ForcedAligner))
  }

  @Test("noteAccess updates aligner last access timestamp")
  func noteAccessUpdatesTimestamp() async throws {
    let store = AlignRuntimeStore.testInstance()
    try await store.testLoadMockAligner(model: .qwen3ForcedAligner)
    let before = await store.testLastAccess(model: .qwen3ForcedAligner)
    try await Task.sleep(nanoseconds: 10_000_000)
    await store.noteAccess(model: .qwen3ForcedAligner)
    let after = await store.testLastAccess(model: .qwen3ForcedAligner)
    #expect(after > before)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/AlignRuntimeStoreTests CODE_SIGNING_ALLOWED=NO`

Expected: FAIL because `AlignRuntimeStore` does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
actor AlignRuntimeStore {
  static let shared = AlignRuntimeStore()

  func getAligner(
    model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Qwen3ASRTranscriber

  func preload(model: ModelVariant, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws
  func hasReadyAligner(model: ModelVariant) -> Bool
  func isLoading(model: ModelVariant) -> Bool
  func noteAccess(model: ModelVariant)
}
```

Required test helpers:

```swift
static func testInstance() -> AlignRuntimeStore
func testLoadMockAligner(...)
func testPreloadMockAligner(...)
func testLoadCount(model: ModelVariant) async -> Int
func testLastAccess(model: ModelVariant) async -> Date
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same command as Step 2

Expected: PASS for `AlignRuntimeStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/AlignRuntimeStore.swift Sources/VoiceFlowProTests/Services/AlignRuntimeStoreTests.swift
git commit -m "refactor: add align runtime store"
```

### Task 3: Create `TTSRuntimeStore`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/TTSRuntimeStore.swift`
- Test: `Sources/VoiceFlowProTests/Services/TTSRuntimeStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("TTSRuntimeStore")
struct TTSRuntimeStoreTests {
  @Test("loads Kokoro when assets are ready")
  func loadsKokoro() async throws {
    let store = TTSRuntimeStore.testInstance()
    let modelID = try await store.testEnsureMockModel(engine: .kokoro, modelID: "kokoro", defaultVoice: .afHeart)
    #expect(modelID == "kokoro")
    #expect(await store.hasReadyModel(engine: .kokoro, modelID: "kokoro"))
  }

  @Test("fails clearly when MLX TTS model is missing")
  func failsWhenMLXAssetsMissing() async throws {
    let store = TTSRuntimeStore.testInstance()
    await #expect(throws: ModelCacheError.self) {
      try await store.ensureModel(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
        defaultVoice: .afHeart
      )
    }
  }

  @Test("reports loading state during preload")
  func reportsLoadingState() async throws {
    let store = TTSRuntimeStore.testInstance()
    let task = Task {
      try await store.testEnsureMockModel(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
        defaultVoice: .afHeart,
        delayNanoseconds: 300_000_000
      )
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(await store.isLoading(engine: .qwen3TTS, modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"))
    _ = try await task.value
    #expect(!(await store.isLoading(engine: .qwen3TTS, modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")))
  }

  @Test("deduplicates concurrent TTS loads for the same model")
  func deduplicatesConcurrentLoads() async throws {
    let store = TTSRuntimeStore.testInstance()

    async let first = store.testEnsureMockModel(
      engine: .qwen3TTS,
      modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
      defaultVoice: .afHeart,
      delayNanoseconds: 150_000_000
    )
    async let second = store.testEnsureMockModel(
      engine: .qwen3TTS,
      modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
      defaultVoice: .afHeart,
      delayNanoseconds: 150_000_000
    )
    _ = try await (first, second)

    #expect(await store.testLoadCount(engine: .qwen3TTS, modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit") == 1)
  }

  @Test("preload stores a ready TTS runtime")
  func preloadMarksModelReady() async throws {
    let store = TTSRuntimeStore.testInstance()
    try await store.testPreloadMockModel(
      engine: .qwen3TTS,
      modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
      defaultVoice: .afHeart
    )
    #expect(await store.hasReadyModel(engine: .qwen3TTS, modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"))
  }

  @Test("preload surfaces TTS failures")
  func preloadPropagatesFailure() async throws {
    let store = TTSRuntimeStore.testInstance()
    await #expect(throws: Error.self) {
      try await store.testPreloadMockModel(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
        defaultVoice: .afHeart,
        failMessage: "intentional preload failure"
      )
    }
  }

  @Test("failed TTS preload recovers on retry")
  func preloadRecoversAfterFailure() async throws {
    let store = TTSRuntimeStore.testInstance()
    await #expect(throws: Error.self) {
      try await store.testPreloadMockModel(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
        defaultVoice: .afHeart,
        failMessage: "intentional preload failure"
      )
    }
    try await store.testPreloadMockModel(
      engine: .qwen3TTS,
      modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
      defaultVoice: .afHeart
    )
    #expect(await store.hasReadyModel(engine: .qwen3TTS, modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"))
  }

  @Test("noteAccess updates TTS last access timestamp")
  func noteAccessUpdatesTimestamp() async throws {
    let store = TTSRuntimeStore.testInstance()
    _ = try await store.testEnsureMockModel(engine: .kokoro, modelID: "kokoro", defaultVoice: .afHeart)
    let before = await store.testLastAccess(engine: .kokoro, modelID: "kokoro")
    try await Task.sleep(nanoseconds: 10_000_000)
    await store.noteAccess(engine: .kokoro, modelID: "kokoro")
    let after = await store.testLastAccess(engine: .kokoro, modelID: "kokoro")
    #expect(after > before)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/TTSRuntimeStoreTests CODE_SIGNING_ALLOWED=NO`

Expected: FAIL because `TTSRuntimeStore` does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
actor TTSRuntimeStore {
  static let shared = TTSRuntimeStore()

  func ensureModel(
    engine: TTSEngine,
    modelID: String,
    defaultVoice: KokoroVoice
  ) async throws -> String

  func preload(engine: TTSEngine, modelID: String, defaultVoice: KokoroVoice) async throws
  func hasReadyModel(engine: TTSEngine, modelID: String) -> Bool
  func isLoading(engine: TTSEngine, modelID: String) -> Bool
  func noteAccess(engine: TTSEngine, modelID: String)
}
```

Required test helpers:

```swift
static func testInstance() -> TTSRuntimeStore
func testEnsureMockModel(...)
func testPreloadMockModel(...)
func testLoadCount(engine: TTSEngine, modelID: String) async -> Int
func testLastAccess(engine: TTSEngine, modelID: String) async -> Date
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same command as Step 2

Expected: PASS for `TTSRuntimeStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/TTSRuntimeStore.swift Sources/VoiceFlowProTests/Services/TTSRuntimeStoreTests.swift
git commit -m "refactor: add TTS runtime store"
```

### Task 4: Create `ModelLanguageSupportService`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ModelLanguageSupportService.swift`
- Rename: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift` -> `Sources/VoiceFlowProTests/Services/ModelLanguageSupportServiceTests.swift`
- Modify: `Sources/VoiceFlowPro/Views/ModelAwareLanguageSelectionView.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("ModelLanguageSupportService")
struct ModelLanguageSupportServiceTests {
  @Test("returns filtered languages for ASR context")
  func filtersASRLanguages() async {
    await ModelLanguageSupportService.shared.invalidateCache()
    let languages = await ModelLanguageSupportService.shared.filteredLanguages(
      for: .asr(type: .parakeet, model: .parakeetV2)
    )
    #expect(languages == [.english])
  }

  @Test("caches repeated lookups by context identity")
  func cachesLookups() async {
    await ModelLanguageSupportService.shared.invalidateCache()
    _ = await ModelLanguageSupportService.shared.filteredLanguages(
      for: .align(model: .qwen3ForcedAligner)
    )
    _ = await ModelLanguageSupportService.shared.filteredLanguages(
      for: .align(model: .qwen3ForcedAligner)
    )
    #expect(await ModelLanguageSupportService.shared.testLookupCount(
      for: .align(model: .qwen3ForcedAligner)
    ) == 1)
  }

  @Test("align language filtering excludes auto while preserving multilingual support")
  func alignLanguageFilteringExcludesAuto() async {
    await ModelLanguageSupportService.shared.invalidateCache()
    let languages = await ModelLanguageSupportService.shared.filteredLanguages(
      for: .align(model: .qwen3ForcedAligner)
    )
    #expect(languages.contains(.english))
    #expect(languages.contains(.chinese))
    #expect(!languages.contains(.auto))
  }

  @Test("returns TTS languages for selected engine")
  func returnsTTSLanguages() async {
    await ModelLanguageSupportService.shared.invalidateCache()
    let languages = await ModelLanguageSupportService.shared.filteredLanguages(
      for: .tts(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
      )
    )
    #expect(languages.contains(.english))
    #expect(languages.contains(.chinese))
    #expect(languages.contains(.japanese))
    #expect(languages.contains(.korean))
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/ModelLanguageSupportServiceTests CODE_SIGNING_ALLOWED=NO`

Expected: FAIL because `ModelLanguageSupportService` does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
actor ModelLanguageSupportService {
  static let shared = ModelLanguageSupportService()

  func filteredLanguages(for context: ModelLanguageContext) async -> [Language]
  func invalidateCache() async
  func testLookupCount(for context: ModelLanguageContext) async -> Int
}
```

- [ ] **Step 4: Migrate the first caller**

Rename `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift` to `Sources/VoiceFlowProTests/Services/ModelLanguageSupportServiceTests.swift` and update its suite name / imports so the old manager-specific test file is fully removed.

Replace:

```swift
let supportedLanguages = await ModelCacheManager.shared.filteredLanguages(for: context)
```

With:

```swift
let supportedLanguages = await ModelLanguageSupportService.shared.filteredLanguages(for: context)
```

in `Sources/VoiceFlowPro/Views/ModelAwareLanguageSelectionView.swift`.

- [ ] **Step 5: Run the targeted tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/ModelLanguageSupportServiceTests -only-testing:VoiceFlowProTests CODE_SIGNING_ALLOWED=NO
```

Expected: new service tests PASS and the full unit target still passes with `ModelAwareLanguageSelectionView` now calling the new service.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelLanguageSupportService.swift Sources/VoiceFlowPro/Views/ModelAwareLanguageSelectionView.swift Sources/VoiceFlowProTests/Services/ModelLanguageSupportServiceTests.swift
git rm Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift
git commit -m "refactor: extract model language support service"
```

## Chunk 2: Lifecycle Store and Caller Migration

### Task 5: Create `ModelLifecycleStore`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ModelLifecycleStore.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelLifecycleStoreTests.swift`
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("ModelLifecycleStore")
struct ModelLifecycleStoreTests {
  @Test("aggregates status snapshots from runtime stores")
  func aggregatesSnapshots() async throws {}

  @Test("clears idle caches while keeping active ASR entry")
  func clearsIdleCaches() async throws {}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/ModelLifecycleStoreTests CODE_SIGNING_ALLOWED=NO`

Expected: FAIL because `ModelLifecycleStore` does not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
actor ModelLifecycleStore {
  static let shared = ModelLifecycleStore()

  func snapshot() async -> ModelCacheSnapshot
  func updateCleanupTimeout(seconds: TimeInterval) async
  func clearCache(keepASR type: TranscriberType, model: ModelVariant) async
}
```

- [ ] **Step 4: Switch lifecycle snapshot reads**

Replace:

```swift
let snapshot = await ModelCacheManager.shared.snapshot()
```

With:

```swift
let snapshot = await ModelLifecycleStore.shared.snapshot()
```

in `Sources/VoiceFlowPro/Models/AppConfiguration.swift`.

- [ ] **Step 5: Run the targeted tests**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/ModelLifecycleStoreTests CODE_SIGNING_ALLOWED=NO`

Expected: PASS for `ModelLifecycleStoreTests`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelLifecycleStore.swift Sources/VoiceFlowPro/Models/AppConfiguration.swift Sources/VoiceFlowProTests/Services/ModelLifecycleStoreTests.swift
git commit -m "refactor: add model lifecycle store"
```

### Task 6: Migrate active runtime callers

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Modify: `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift`
- Test: existing relevant tests in `Sources/VoiceFlowProTests/Services/` and `Sources/VoiceFlowProTests/Integration/`

- [ ] **Step 1: Write the failing migration tests**

Add or update tests to assert:

```swift
// VoiceTranscriber and AICut no longer reference ModelCacheManager.shared
// TranscriberWarmupCoordinator queries ASRRuntimeStore.shared
```

Use the existing migration-style pattern from:

```text
Sources/VoiceFlowProTests/Integration/TranscriberPoolMigrationTests.swift
```

- [ ] **Step 2: Run the migration tests to verify they fail**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/Integration/TranscriberPoolMigrationTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the three callers still reference `ModelCacheManager.shared`.

- [ ] **Step 3: Migrate `VoiceTranscriber`**

Replace:

```swift
await ModelCacheManager.shared.isModelLoading(...)
try await ModelCacheManager.shared.getASRTranscriber(...)
```

With corresponding `ASRRuntimeStore.shared` calls.

- [ ] **Step 4: Migrate `AICutView`**

Replace:

```swift
ModelCacheManager.shared.getASRTranscriber(...)
ModelCacheManager.shared.getAlignTranscriber(...)
```

With `ASRRuntimeStore.shared` and `AlignRuntimeStore.shared`.

- [ ] **Step 5: Migrate `TranscriberWarmupCoordinator`**

Replace:

```swift
ModelCacheManager.shared.hasReadyTranscriber(...)
ModelCacheManager.shared.isModelLoading(...)
ModelCacheManager.shared.getASRTranscriber(...)
```

With `ASRRuntimeStore.shared` APIs.

- [ ] **Step 6: Migrate `VoiceToTextView`**

Replace:

```swift
ModelCacheManager.shared.getASRTranscriber(...)
```

With:

```swift
ASRRuntimeStore.shared.getTranscriber(...)
```

- [ ] **Step 7: Run the caller-focused tests**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/Integration/TranscriberPoolMigrationTests -only-testing:VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS, or rename/remove obsolete `ModelCacheManagerLifecycleTests` as part of the next task if the suite no longer matches the architecture.

- [ ] **Step 7: Commit**
- [ ] **Step 8: Commit**

```bash
git add Sources/VoiceFlowPro/Services/VoiceTranscriber.swift Sources/VoiceFlowPro/Views/VoiceToTextView.swift Sources/VoiceFlowPro/Views/AICutView.swift Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift Sources/VoiceFlowProTests/Integration/TranscriberPoolMigrationTests.swift Sources/VoiceFlowProTests/Services
git commit -m "refactor: migrate ASR and align callers to runtime stores"
```

### Task 7: Migrate Models UI lifecycle actions

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
- Modify: `Sources/VoiceFlowPro/VoiceFlowPro.swift`
- Test: `Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift`

- [ ] **Step 1: Write/update failing UI flow tests**

Add expectations that:

- preload buttons call the new runtime/lifecycle stores
- retry failed cache loads uses the new stores
- clear cache routes through `ModelLifecycleStore`

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests/Integration/ModelSelectionUIFlowTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `ModelsView` and bootstrap still depend on `ModelCacheManager`.

- [ ] **Step 3: Migrate `ModelsView`**

Replace:

```swift
ModelCacheManager.shared.preloadAlignModel(...)
ModelCacheManager.shared.preloadTTSModel(...)
ModelCacheManager.shared.preloadASRModel(...)
ModelCacheManager.shared.clearCache(...)
```

With:

```swift
AlignRuntimeStore.shared.preload(...)
TTSRuntimeStore.shared.preload(...)
ASRRuntimeStore.shared.preload(...)
ModelLifecycleStore.shared.clearCache(...)
```

- [ ] **Step 4: Migrate app bootstrap**

Replace:

```swift
await ModelCacheManager.shared.updateCleanupTimeout(...)
try? await ModelCacheManager.shared.preloadASRModel(...)
```

With:

```swift
await ModelLifecycleStore.shared.updateCleanupTimeout(...)
try? await ASRRuntimeStore.shared.preload(...)
```

in `Sources/VoiceFlowPro/VoiceFlowPro.swift`.

- [ ] **Step 5: Run the targeted tests**

Run: same command as Step 2

Expected: PASS for updated UI flow coverage.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ModelsView.swift Sources/VoiceFlowPro/VoiceFlowPro.swift Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift
git commit -m "refactor: migrate models UI lifecycle actions"
```

### Task 8: Remove `ModelCacheManager`

**Files:**
- Delete: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
- Modify: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift`
- Modify: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift`
- Modify: any residual callers found by ripgrep

- [ ] **Step 1: Write a failing guard test**

Add or update a migration test that asserts:

```swift
// No production source references ModelCacheManager.shared
// ModelCacheManager.swift no longer exists
```

- [ ] **Step 2: Run the guard test to verify it fails**

Run:

```bash
rg -n "ModelCacheManager\\.shared|actor ModelCacheManager|ModelCacheManager\\b" Sources/VoiceFlowPro Sources/VoiceFlowProTests
```

Expected: matches remain.

- [ ] **Step 3: Remove the final references and delete the file**

Delete `Sources/VoiceFlowPro/Services/ModelCacheManager.swift` and either:

- rename old manager-specific tests to the new store names, or
- replace them with store-focused tests created in previous tasks.

- [ ] **Step 4: Run the guard command again**

Run:

```bash
rg -n "ModelCacheManager\\.shared|actor ModelCacheManager|ModelCacheManager\\b" Sources/VoiceFlowPro Sources/VoiceFlowProTests
```

Expected: no matches.

- [ ] **Step 5: Run the full unit suite**

Run:

```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS for all unit tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro Sources/VoiceFlowProTests
git commit -m "refactor: remove model cache manager"
```

### Task 9: Final verification

**Files:**
- Modify: docs only if implementation behavior changed materially

- [ ] **Step 1: Run repository verification**

Run:

```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS'
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:VoiceFlowProTests CODE_SIGNING_ALLOWED=NO
```

Expected: both commands succeed.

- [ ] **Step 2: Review the diff**

Run:

```bash
git --no-pager diff --stat
git --no-pager diff -- Sources/VoiceFlowPro Sources/VoiceFlowProTests
```

Expected: only the planned runtime/lifecycle/language split changes appear.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro Sources/VoiceFlowProTests docs/superpowers
git commit -m "refactor: split runtime stores from model lifecycle management"
```
