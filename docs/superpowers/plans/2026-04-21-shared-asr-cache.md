# Shared ASR Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI Cut and Voice To Text reuse the same loaded ASR model instance, and release that shared ASR model only after a dedicated idle timeout expires.

**Architecture:** Keep `ModelCacheManager` as the only owner of loaded ASR instances. Unify Voice To Text runtime selection onto the shared ASR configuration already used by AI Cut, then give ASR its own cleanup timeout instead of relying on the generic non-ASR cleanup path.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, Swift Package Manager

---

### Task 1: Unify Voice To Text runtime selection with the shared ASR configuration

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`
- Test: `Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift`

- [ ] **Step 1: Write the failing AppConfiguration test for shared Voice To Text ASR selection**

```swift
@Test("voice to text active ASR selection follows shared model selection")
func voiceToTextActiveSelectionTracksSharedASRConfiguration() throws {
  let original = AppConfiguration.shared.makeSnapshot()
  defer {
    AppConfiguration.shared.applySnapshot(original)
  }

  var changed = original
  changed.transcriberType = .qwen3
  changed.modelVariant = .qwen3ASR
  changed.voiceToTextTranscriberType = .parakeet
  changed.voiceToTextModelVariant = .parakeetV3

  AppConfiguration.shared.applySnapshot(changed)

  #expect(AppConfiguration.shared.activeVoiceToTextTranscriberType == .qwen3)
  #expect(AppConfiguration.shared.activeVoiceToTextModelVariant == .qwen3ASR)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter voiceToTextActiveSelectionTracksSharedASRConfiguration`

Expected: FAIL because `activeVoiceToTextTranscriberType` and `activeVoiceToTextModelVariant` do not exist yet.

- [ ] **Step 3: Add shared runtime accessors in `AppConfiguration`**

```swift
@Published var asrIdleTimeoutSeconds: TimeInterval {
  didSet {
    if asrIdleTimeoutSeconds < 60 {
      asrIdleTimeoutSeconds = 60
    }
    Task {
      await ModelCacheManager.shared.updateASRIdleTimeout(seconds: asrIdleTimeoutSeconds)
    }
  }
}

var activeVoiceToTextTranscriberType: TranscriberType { transcriberType }
var activeVoiceToTextModelVariant: ModelVariant { modelVariant }
```

Also thread `asrIdleTimeoutSeconds` through:

```swift
struct Snapshot: Equatable, Codable, Sendable {
  var asrIdleTimeoutSeconds: TimeInterval = 600
}
```

and:

```swift
static let defaultSnapshot = Snapshot(
  // ...
  asrIdleTimeoutSeconds: 600,
  // ...
)
```

- [ ] **Step 4: Rewire `VoiceToTextView` to use the shared runtime ASR selection**

Replace Voice To Text-specific model selectors in the runtime path:

```swift
private var selectedSignature: (TranscriberType, ModelVariant) {
  (config.activeVoiceToTextTranscriberType, config.activeVoiceToTextModelVariant)
}
```

```swift
private var selectedModelStatus: ModelDownloadStatus {
  selectionModelStatuses[config.activeVoiceToTextModelVariant] ?? .checking
}
```

```swift
Text("\(config.activeVoiceToTextTranscriberType.displayName) • \(config.activeVoiceToTextModelVariant.displayName)")
```

```swift
contextProvider: {
  .asr(
    type: config.activeVoiceToTextTranscriberType,
    model: config.activeVoiceToTextModelVariant
  )
}
```

```swift
await transcriber.toggle(
  type: config.activeVoiceToTextTranscriberType,
  model: config.activeVoiceToTextModelVariant,
  language: config.voiceToTextLanguage
)
```

```swift
let targetType = config.activeVoiceToTextTranscriberType
let targetModel = config.activeVoiceToTextModelVariant
```

- [ ] **Step 5: Run the focused AppConfiguration test and the existing persistence regression**

Run:

```bash
swift test --filter voiceToTextActiveSelectionTracksSharedASRConfiguration
swift test --filter snapshotPersistenceRoundTripForModelLifecycleSettings
```

Expected: PASS for both tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift \
  Sources/VoiceFlowPro/Views/VoiceToTextView.swift \
  Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift
git commit -m "feat: unify Voice To Text ASR selection"
```

---

### Task 2: Add a dedicated ASR idle-timeout path to `ModelCacheManager`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
- Modify: `Sources/VoiceFlowPro/VoiceFlowPro.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift`

- [ ] **Step 1: Write the failing cache lifecycle tests**

```swift
@Test("idle cleanup removes stale ASR entries after ASR timeout expires")
func cleanupPurgesIdleASRModelsAfterASRTimeout() async throws {
  let key = ModelLifecycleKey(kind: .asr, identifier: "parakeet:shared-test")

  try await ModelCacheManager.shared.testLoadMockResource(
    key: key,
    displayName: "Shared ASR Test",
    estimatedMemoryMB: 80,
    asASRResource: true
  )
  await ModelCacheManager.shared.testSetASRCleanupTimeout(seconds: 1)
  await ModelCacheManager.shared.testSetLastAccess(Date().addingTimeInterval(-5), for: key)
  await ModelCacheManager.shared.testPurgeExpiredEntries()

  let exists = await ModelCacheManager.shared.testContainsEntry(for: key)
  #expect(exists == false)
}

@Test("idle cleanup keeps ASR entries before ASR timeout expires")
func cleanupKeepsRecentASRModelsBeforeASRTimeout() async throws {
  let key = ModelLifecycleKey(kind: .asr, identifier: "parakeet:recent-test")

  try await ModelCacheManager.shared.testLoadMockResource(
    key: key,
    displayName: "Recent ASR Test",
    estimatedMemoryMB: 80,
    asASRResource: true
  )
  await ModelCacheManager.shared.testSetASRCleanupTimeout(seconds: 600)
  await ModelCacheManager.shared.testSetLastAccess(Date().addingTimeInterval(-5), for: key)
  await ModelCacheManager.shared.testPurgeExpiredEntries()

  let exists = await ModelCacheManager.shared.testContainsEntry(for: key)
  #expect(exists == true)
  await ModelCacheManager.shared.testRemoveEntry(for: key)
}
```

- [ ] **Step 2: Run the focused lifecycle tests to verify they fail**

Run:

```bash
swift test --filter cleanupPurgesIdleASRModelsAfterASRTimeout
swift test --filter cleanupKeepsRecentASRModelsBeforeASRTimeout
```

Expected: FAIL because ASR entries are currently skipped by `purgeExpiredEntries()` and there is no dedicated ASR timeout setter.

- [ ] **Step 3: Implement dedicated ASR timeout state and cleanup rules**

Add a dedicated timeout and updater:

```swift
private var asrCleanupTimeout: TimeInterval = 600

func updateASRIdleTimeout(seconds: TimeInterval) {
  asrCleanupTimeout = max(60, seconds)
}
```

Change cleanup logic from:

```swift
if key.kind == .asr {
  continue
}
let idle = now.timeIntervalSince(entry.lastAccess)
if idle > cleanupTimeout {
```

to:

```swift
let timeout: TimeInterval = switch key.kind {
case .asr:
  asrCleanupTimeout
case .align, .tts:
  cleanupTimeout
}

let idle = now.timeIntervalSince(entry.lastAccess)
if idle > timeout {
```

Also extend DEBUG helpers:

```swift
func testSetASRCleanupTimeout(seconds: TimeInterval) {
  asrCleanupTimeout = max(1, seconds)
}
```

and reset it in `testResetState()`.

- [ ] **Step 4: Sync the new timeout during app bootstrap**

Update `VoiceFlowPro.swift` startup wiring:

```swift
let (asrType, asrModel, cleanupTimeout, asrIdleTimeout) = await MainActor.run {
  (
    sharedConfig.transcriberType,
    sharedConfig.modelVariant,
    sharedConfig.modelCleanupTimeoutSeconds,
    sharedConfig.asrIdleTimeoutSeconds
  )
}
await ModelCacheManager.shared.updateCleanupTimeout(seconds: cleanupTimeout)
await ModelCacheManager.shared.updateASRIdleTimeout(seconds: asrIdleTimeout)
try? await ModelCacheManager.shared.preloadASRModel(type: asrType, model: asrModel)
```

- [ ] **Step 5: Run the focused lifecycle suite**

Run:

```bash
swift test --filter cleanupPurgesIdleASRModelsAfterASRTimeout
swift test --filter cleanupKeepsRecentASRModelsBeforeASRTimeout
swift test --filter lazyLoadingReusesCache
```

Expected: PASS for all three tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelCacheManager.swift \
  Sources/VoiceFlowPro/VoiceFlowPro.swift \
  Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift
git commit -m "feat: add ASR-specific cache timeout"
```

---

### Task 3: Expose the ASR timeout in Models and run regression validation

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
- Verify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Verify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`

- [ ] **Step 1: Add a small cache-lifecycle control for the ASR idle timeout**

Insert the control near the existing cache summary in `ModelsView.swift`:

```swift
VStack(alignment: .leading, spacing: 8) {
  Text("ASR Idle Timeout")
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)

  HStack(spacing: 12) {
    Slider(
      value: Binding(
        get: { config.asrIdleTimeoutSeconds },
        set: { config.asrIdleTimeoutSeconds = $0.rounded() }
      ),
      in: 60...3600,
      step: 60
    )
    Text("\(Int(config.asrIdleTimeoutSeconds / 60)) min")
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      .frame(width: 56, alignment: .trailing)
  }

  Text("Shared ASR models used by AI Cut and Voice To Text are released after this idle period.")
    .font(.caption)
    .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Update cache-related copy so the new behavior is explicit**

Adjust the confirmation/help text from:

```swift
Text("This keeps the active ASR model and clears idle align/TTS models from memory.")
```

to:

```swift
Text("This keeps the currently selected ASR model available until its idle timeout expires, and clears idle align/TTS models immediately.")
```

Also verify the cache badge still keys off:

```swift
ModelLifecycleKey(
  kind: .asr,
  identifier: "\(config.transcriberType.rawValue):\(config.modelVariant.rawValue)"
)
```

- [ ] **Step 3: Re-run focused regression tests after the UI wiring**

Run:

```bash
swift test --filter voiceToTextActiveSelectionTracksSharedASRConfiguration
swift test --filter snapshotPersistenceRoundTripForModelLifecycleSettings
swift test --filter "ModelCacheManager lifecycle and concurrency"
```

Expected: PASS for the targeted suites. If the suite name filter matches too broadly or returns zero tests, run the three explicit test names from Tasks 1 and 2 instead.

- [ ] **Step 4: Run a build smoke check**

Run: `swift build`

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ModelsView.swift
git commit -m "feat: surface shared ASR timeout controls"
```

- [ ] **Step 6: Final verification commit (only if needed)**

If the working tree still contains changes across multiple tasks:

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift \
  Sources/VoiceFlowPro/Services/ModelCacheManager.swift \
  Sources/VoiceFlowPro/Views/ModelsView.swift \
  Sources/VoiceFlowPro/Views/VoiceToTextView.swift \
  Sources/VoiceFlowPro/VoiceFlowPro.swift \
  Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift \
  Sources/VoiceFlowProTests/Services/ModelCacheManagerLifecycleTests.swift
git commit -m "feat: share ASR cache across AI Cut and Voice To Text"
```

If all changes are already committed task-by-task, skip this step.
