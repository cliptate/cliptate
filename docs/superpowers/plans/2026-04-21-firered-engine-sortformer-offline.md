# FireRed Engine and Sortformer Offline Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add FireRed ASR 2 as a first-class ASR engine, remove Sortformer Offline from the user workflow, and complete the change with internationalized UI copy, configuration migration, and tests.

**Architecture:** Keep the existing engine-per-model-family architecture and introduce FireRed as a separate `TranscriberType` with its own `ModelVariant` classification and dedicated transcriber. Reuse the shared `ModelDownloadManager` and `mlx-audio` cache root, while removing `Sortformer Offline` from user-visible VAD choices and migrating saved settings to a supported remaining option.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), Swift Package Manager, `MLXAudioSTT`, `MLXAudioCore`, `HuggingFace`, `NSLocalizedString`

---

## File map

### Existing files to modify

- `Package.swift:52-72` — register any new Swift test files in the explicit `VoiceFlowProTests` source list.
- `Sources/VoiceFlowPro/Models/DataTypes.swift` — add FireRed model metadata, engine wiring, capability summaries, and remove `Sortformer Offline` from user-visible VAD options.
- `Sources/VoiceFlowPro/Models/AppConfiguration.swift` — support FireRed as a persisted engine/model pairing and migrate `sortformerOffline` defaults/saved values to a supported VAD option.
- `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift` — add FireRed download/load routing under the shared `mlx-audio` root.
- `Sources/VoiceFlowPro/Services/ModelDownloadStatusChecker.swift` — ensure FireRed model status checks flow through the shared download manager path.
- `Sources/VoiceFlowPro/Views/ModelSelectionView.swift` — expose FireRed as a first-class engine and show localized language/capability guidance.
- `Sources/VoiceFlowPro/Views/ModelsView.swift` — expose FireRed in the model library and remove `Sortformer Offline` from user-visible VAD choices.
- `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift` — replace the current `.sortformerOffline` warmup/runtime default with the supported visible VAD default.

### New files to create

- `Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift` — dedicated offline FireRed transcriber using `FireRedASR2Model`.
- `Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift` — focused metadata/configuration tests for the new engine and model family.
- `Sources/VoiceFlowProTests/Services/FireRedASRTranscriberTests.swift` — transcriber construction and call-chain tests using protocol-based test seams.

### Existing tests to extend

- `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
- `Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift`
- `Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift`

### Reference files to read while implementing

- `docs/superpowers/specs/2026-04-21-firered-engine-sortformer-offline-design.md`
- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift`
- `Sources/VoiceFlowPro/Services/PaywallManager.swift` (for `NSLocalizedString` usage style)

### Task 1: Add FireRed metadata and engine wiring

**Files:**
- Create: `Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift`
- Modify: `Package.swift:52-72`
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
- Test: `Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift`

- [ ] **Step 1: Write the failing metadata tests**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("FireRed engine metadata")
struct FireRedEngineMetadataTests {
  @Test("FireRed appears as a distinct ASR engine")
  func fireRedEngineExists() {
    #expect(TranscriberType.allCases.contains(.fireRed))
    #expect(TranscriberType.fireRed.displayName == "FireRed")
  }

  @Test("FireRed exposes only FireRed models")
  func fireRedSupportedModels() {
    #expect(TranscriberType.fireRed.supportedModels == [.fireRedASR2])
    #expect(ModelVariant.fireRedASR2.isFireRedASRModel)
    #expect(!ModelVariant.fireRedASR2.isQwen3ASRModel)
    #expect(!ModelVariant.fireRedASR2.isParakeetModel)
  }

  @Test("Sortformer offline is removed from user-visible VAD models")
  func sortformerOfflineRemovedFromVisibleVADModels() {
    #expect(!ModelVariant.vadModels.contains(.sortformerOffline))
    #expect(ModelVariant.vadModels.contains(.sortformerStreaming))
  }

  @Test("FireRed capability metadata reflects product requirements")
  func fireRedCapabilities() {
    #expect(ModelVariant.fireRedASR2.languageSummary == "Chinese dialects, English, mixed speech, lyrics")
    #expect(ModelVariant.fireRedASR2.featureHighlights.contains("Mandarin + 20+ dialects / accents"))
    #expect(ModelVariant.fireRedASR2.featureHighlights.contains("Chinese-English mixed speech"))
    #expect(ModelVariant.fireRedASR2.featureHighlights.contains("Lyrics recognition"))
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
.testTarget(
    name: "VoiceFlowProTests",
    dependencies: ["VoiceFlowPro"],
    path: "Sources/VoiceFlowProTests",
    sources: [
        "Services/ModelDownloadStateStoreTests.swift",
        "Services/ModelCacheManagerLanguageTests.swift",
        "Services/ModelCacheManagerLifecycleTests.swift",
        "Services/ModelDownloadManagerTests.swift",
        "Services/SortformerVADSegmenterTests.swift",
        "Services/SegmentedAlignmentPipelineTests.swift",
        "Services/SegmentSpeakerPropagationPipelineTests.swift",
        "Services/SpeechSegmenterTests.swift",
        "Services/MLXParakeetTranscriberTests.swift",
        "Services/Qwen3ASRTranscriberContextTests.swift",
        "Services/AudioProcessorChunkTests.swift",
        "Services/FireRedASRTranscriberTests.swift",
        "Integration/ModelSelectionUIFlowTests.swift",
        "Integration/TranscriberPoolMigrationTests.swift",
        "Models/AppConfigurationModelLifecyclePersistenceTests.swift",
        "Models/SegmentTests.swift",
        "Models/ModelVariantTTSTests.swift",
        "Models/FireRedEngineMetadataTests.swift"
    ],
```

- [ ] **Step 3: Run the new metadata suite and verify it fails**

Run:

```bash
swift test --filter FireRedEngineMetadataTests
```

Expected: FAIL with missing `TranscriberType.fireRed`, missing `ModelVariant.fireRedASR2`, and/or `Sortformer Offline` still present in `ModelVariant.vadModels`.

- [ ] **Step 4: Write the minimal metadata implementation**

```swift
// Sources/VoiceFlowPro/Models/DataTypes.swift
case fireRedASR2 = "firered-asr2-aed-mlx"

var isFireRedASRModel: Bool {
  switch self {
  case .fireRedASR2: return true
  default: return false
  }
}

public enum TranscriberType: String, CaseIterable, Identifiable, Codable, Sendable {
  case whisper
  case parakeet = "parakeet"
  case qwen3 = "qwen3"
  case fireRed = "fireRed"
}

// insert into the existing supportedModels switch
case .fireRed:
  return [.fireRedASR2]

// insert into the existing displayName switch
case .fireRed:
  return "FireRed"

public static var vadModels: [ModelVariant] {
  allCases.filter { $0.isSortformerVADModel && $0 != .sortformerOffline && !$0.isHiddenFromSelection }
}
```

- [ ] **Step 5: Run the metadata suite again and verify it passes**

Run:

```bash
swift test --filter FireRedEngineMetadataTests
```

Expected: PASS.

- [ ] **Step 6: Commit the metadata work**

```bash
git add Package.swift \
  Sources/VoiceFlowPro/Models/DataTypes.swift \
  Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift
git commit -m $'feat: add firered engine metadata\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 2: Route FireRed downloads through the shared mlx-audio root

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadStatusChecker.swift`
- Modify: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`

- [ ] **Step 1: Add failing FireRed download-routing tests**

```swift
@Suite("FireRed download routing")
struct FireRedDownloadRoutingTests {
  @Test("FireRed uses a dedicated FireRed ASR backend")
  func fireRedUsesDedicatedBackend() {
    #expect(ModelDownloadManager.downloadBackend(for: .fireRedASR2) == .fireRedASR)
  }

  @Test("FireRed resolves under the shared mlx-audio root")
  func fireRedUsesSharedRoot() {
    let env: [String: String] = [:]
    let home = URL(fileURLWithPath: "/mock/home", isDirectory: true)
    let caches = URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
    let fireRed = ModelDownloadManager.mlxAudioDirectory(
      forRepo: ModelVariant.fireRedASR2.huggingFaceRepoId,
      environment: env,
      homeDirectory: home,
      cachesDirectory: caches
    )
    let qwen3 = ModelDownloadManager.mlxAudioDirectory(
      forRepo: ModelVariant.qwen3ASR.huggingFaceRepoId,
      environment: env,
      homeDirectory: home,
      cachesDirectory: caches
    )

    #expect(fireRed.deletingLastPathComponent() == qwen3.deletingLastPathComponent())
    #expect(fireRed.path.contains("/mlx-audio/"))
  }
}
```

- [ ] **Step 2: Run the FireRed download-routing tests and verify they fail**

Run:

```bash
swift test --filter FireRedDownloadRoutingTests
```

Expected: FAIL because `.fireRedASR` backend and FireRed model metadata do not exist in the download manager yet.

- [ ] **Step 3: Write the minimal download-routing implementation**

```swift
// Sources/VoiceFlowPro/Services/ModelDownloadManager.swift
enum DownloadBackend: Equatable {
  case qwen3ASR
  case qwen3Aligner
  case fireRedASR
  case sortformerVAD
  case resolver
  case unsupported
}

nonisolated static func downloadBackend(for model: ModelVariant) -> DownloadBackend {
  if model.isParakeetModel { return .resolver }
  if model.isQwen3ASRModel { return .qwen3ASR }
  if model.isFireRedASRModel { return .fireRedASR }
  if model.isQwen3AlignerModel { return .qwen3Aligner }
  if model.isSortformerVADModel { return .sortformerVAD }
  if model.isTTSModel { return .resolver }
  return .unsupported
}

// insert into the existing download(model:) backend switch
case .fireRedASR:
  _ = try await FireRedASR2Model.fromPretrained(model.huggingFaceRepoId)
```

- [ ] **Step 4: Run the download-manager tests again**

Run:

```bash
swift test --filter FireRedDownloadRoutingTests
swift test --filter ModelDownloadManager
```

Expected: PASS for the new FireRed routing tests and the existing download-manager suites.

- [ ] **Step 5: Commit the download-routing work**

```bash
git add Sources/VoiceFlowPro/Services/ModelDownloadManager.swift \
  Sources/VoiceFlowPro/Services/ModelDownloadStatusChecker.swift \
  Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift
git commit -m $'feat: add firered download routing\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 3: Add the dedicated FireRed transcriber

**Files:**
- Create: `Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift`
- Create: `Sources/VoiceFlowProTests/Services/FireRedASRTranscriberTests.swift`
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
- Test: `Sources/VoiceFlowProTests/Services/FireRedASRTranscriberTests.swift`

- [ ] **Step 1: Write the failing FireRed transcriber tests**

```swift
import Foundation
import Testing

@testable import VoiceFlowPro

@Suite("FireRedASRTranscriber")
struct FireRedASRTranscriberTests {
  @Test("FireRed engine creates a FireRed transcriber")
  func fireRedCreateTranscriber() {
    let transcriber = TranscriberType.fireRed.createTranscriber(model: .fireRedASR2)
    #expect(transcriber is FireRedASRTranscriber)
  }

  @Test("FireRed transcriber rejects non-FireRed models")
  func rejectsWrongModelFamily() {
    #expect(throws: Never.self) {
      _ = FireRedASRTranscriber(model: .fireRedASR2)
    }
  }
}
```

- [ ] **Step 2: Run the FireRed transcriber tests and verify they fail**

Run:

```bash
swift test --filter FireRedASRTranscriberTests
```

Expected: FAIL because `FireRedASRTranscriber` does not exist yet and `createTranscriber` does not support `.fireRed`.

- [ ] **Step 3: Write the minimal transcriber implementation**

```swift
// Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift
import AVFoundation
import Foundation
import MLXAudioCore
import MLXAudioSTT

public final class FireRedASRTranscriber: @unchecked Sendable, Transcriber {
  private let modelVariant: ModelVariant
  private var fireRedModel: FireRedASR2Model?
  public var model: ModelVariant { modelVariant }

  public init(model: ModelVariant = .fireRedASR2) {
    precondition(model.isFireRedASRModel, "FireRedASRTranscriber requires a FireRed ASR model variant")
    self.modelVariant = model
  }

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    progressHandler(ModelDownloadProgress(currentStep: "Loading \(modelVariant.displayName)...", progress: 0.1))
    fireRedModel = try await FireRedASR2Model.fromPretrained(modelVariant.huggingFaceRepoId)
    progressHandler(ModelDownloadProgress(currentStep: "\(modelVariant.displayName) ready", progress: 1.0))
  }
}

// Sources/VoiceFlowPro/Models/DataTypes.swift
case .fireRed:
  let fireRedModel = model.isFireRedASRModel ? model : .fireRedASR2
  return FireRedASRTranscriber(model: fireRedModel)
```

- [ ] **Step 4: Run the FireRed transcriber tests again**

Run:

```bash
swift test --filter FireRedASRTranscriberTests
```

Expected: PASS.

- [ ] **Step 5: Commit the FireRed transcriber**

```bash
git add Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift \
  Sources/VoiceFlowPro/Models/DataTypes.swift \
  Sources/VoiceFlowProTests/Services/FireRedASRTranscriberTests.swift \
  Package.swift
git commit -m $'feat: add firered transcriber\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 4: Remove Sortformer Offline from visible/default flows and migrate config

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`
- Modify: `Sources/VoiceFlowPro/Views/ModelSelectionView.swift`
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
- Modify: `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift`
- Modify: `Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift`
- Modify: `Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift`
- Test: `Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift`
- Test: `Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift`

- [ ] **Step 1: Add failing configuration and selection tests**

```swift
@Test("saved sortformerOffline selection migrates to sortformerStreaming")
func migratesOfflineVADSelection() {
  let config = AppConfiguration()
  config.vadModelVariant = .sortformerOffline
  config.normalizeModelSelections()
  #expect(config.vadModelVariant == .sortformerStreaming)
}

@Test("fireRed appears in model selection engines")
func fireRedEngineSelectionExists() {
  #expect(TranscriberType.allCases.contains(.fireRed))
  #expect(TranscriberType.fireRed.supportedModels == [.fireRedASR2])
}
```

- [ ] **Step 2: Run the config/selection tests and verify they fail**

Run:

```bash
swift test --filter AppConfigurationModelLifecyclePersistenceTests
swift test --filter ModelSelectionUIFlowTests
```

Expected: FAIL because `sortformerOffline` is not migrated away yet and FireRed is not fully surfaced in selection behavior.

- [ ] **Step 3: Write the minimal migration and UI implementation**

```swift
// Sources/VoiceFlowPro/Models/AppConfiguration.swift
if vadModelVariant == .sortformerOffline {
  vadModelVariant = .sortformerStreaming
}

// Sources/VoiceFlowPro/Views/ModelSelectionView.swift
private var languageRestrictionNotice: String? {
  switch selectedModel {
  case .fireRedASR2:
    return NSLocalizedString(
      "Supports Mandarin, 20+ Chinese dialects and accents, English, mixed Chinese-English speech, and lyrics recognition.",
      comment: "FireRed language support notice"
    )
  case .parakeetV2:
    return NSLocalizedString("Parakeet v2 is English-only.", comment: "Parakeet v2 language notice")
  case .parakeetV3:
    return NSLocalizedString("Parakeet v3 supports 25 European languages.", comment: "Parakeet v3 language notice")
  default:
    return nil
  }
}

// Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift
vadSegmenter = try await SortformerVADSegmenter.makeWithModel(variant: .sortformerStreaming)
```

- [ ] **Step 4: Run the config/selection tests again**

Run:

```bash
swift test --filter AppConfigurationModelLifecyclePersistenceTests
swift test --filter ModelSelectionUIFlowTests
```

Expected: PASS.

- [ ] **Step 5: Commit the migration and user-visible removal**

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift \
  Sources/VoiceFlowPro/Views/ModelSelectionView.swift \
  Sources/VoiceFlowPro/Views/ModelsView.swift \
  Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift \
  Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift \
  Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift
git commit -m $'fix: remove sortformer offline from user workflow\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 5: Internationalize FireRed and Sortformer removal copy

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
- Modify: `Sources/VoiceFlowPro/Views/ModelSelectionView.swift`
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
- Test: `Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift`

- [ ] **Step 1: Add failing localization-oriented assertions**

```swift
@Test("FireRed user-facing metadata is not empty")
func fireRedLocalizedMetadataIsPresent() {
  #expect(!TranscriberType.fireRed.description.isEmpty)
  #expect(!ModelVariant.fireRedASR2.summary.isEmpty)
  #expect(!ModelVariant.fireRedASR2.languageSummary.isEmpty)
  #expect(!ModelVariant.fireRedASR2.featureHighlights.isEmpty)
}
```

- [ ] **Step 2: Run the metadata suite and verify it fails where FireRed copy is still missing**

Run:

```bash
swift test --filter FireRedEngineMetadataTests
```

Expected: FAIL if any FireRed-facing copy remains unset.

- [ ] **Step 3: Wrap changed user-visible strings in the repo’s localization pattern**

```swift
// Sources/VoiceFlowPro/Models/DataTypes.swift
case .fireRed:
  return NSLocalizedString("FireRed engine for Chinese dialects, English, mixed speech, and lyrics recognition.", comment: "FireRed engine description")

case .fireRedASR2:
  return NSLocalizedString("FireRed ASR 2", comment: "FireRed model display name")

case .fireRedASR2:
  return NSLocalizedString("Chinese dialects, English, mixed speech, lyrics", comment: "FireRed language summary")

case .fireRedASR2:
  return [
    NSLocalizedString("Mandarin + 20+ dialects / accents", comment: "FireRed highlight"),
    NSLocalizedString("Chinese-English mixed speech", comment: "FireRed highlight"),
    NSLocalizedString("Lyrics recognition", comment: "FireRed highlight")
  ]
```

- [ ] **Step 4: Run the metadata suite again**

Run:

```bash
swift test --filter FireRedEngineMetadataTests
```

Expected: PASS.

- [ ] **Step 5: Commit the internationalization pass**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift \
  Sources/VoiceFlowPro/Views/ModelSelectionView.swift \
  Sources/VoiceFlowPro/Views/ModelsView.swift \
  Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift
git commit -m $'feat: localize firered engine copy\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 6: Final regression pass

**Files:**
- Modify: none
- Test: `Sources/VoiceFlowProTests/Models/FireRedEngineMetadataTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/FireRedASRTranscriberTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`
- Test: `Sources/VoiceFlowProTests/Integration/ModelSelectionUIFlowTests.swift`
- Test: `Sources/VoiceFlowProTests/Models/AppConfigurationModelLifecyclePersistenceTests.swift`

- [ ] **Step 1: Run the exact feature suites**

Run:

```bash
swift test --filter FireRedEngineMetadataTests
swift test --filter FireRedASRTranscriberTests
swift test --filter ModelDownloadManager
swift test --filter ModelSelectionUIFlowTests
swift test --filter AppConfigurationModelLifecyclePersistenceTests
```

Expected: PASS for the feature-specific suites. If the environment still has an unrelated MLX metallib failure in a pre-existing real-model test, document that explicitly and separate it from this feature’s targeted coverage.

- [ ] **Step 2: Run the full package test suite**

Run:

```bash
swift test
```

Expected: PASS for `VoiceFlowProTests`, or the same previously known environmental MLX metallib issue only if unchanged from baseline.

- [ ] **Step 3: Verify the working tree is clean**

Run:

```bash
git --no-pager status --short
```

Expected: no unexpected modified files.
