# Merge TTS Downloads into ModelVariant — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 6 TTS cases to `ModelVariant`, delete `MLXTTSDownloadManager`, and route all TTS download/status/delete operations through `ModelDownloadManager` with unified path resolution and config.json validation.

**Architecture:** `MLXTTSModelDefinition` keeps UI-only metadata and gains a `modelVariant: ModelVariant` property. `ModelDownloadManager` gains a TTS download path and a `modelSizeInMB` helper. All 11 `MLXTTSDownloadManager` call sites in Views/Services are updated to use `ModelDownloadManager.shared`.

**Tech Stack:** Swift/SwiftUI, MLXAudioCore (`ModelUtils.resolveOrDownloadModel`), HuggingFace (`HubCache`), Swift Testing framework.

---

### Task 1: Add TTS ModelVariant cases and properties

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`
- Test: `Sources/VoiceFlowProTests/Models/ModelVariantTTSTests.swift` *(create new)*

- [ ] **Step 1.1: Write failing tests for new TTS cases**

Create `Sources/VoiceFlowProTests/Models/ModelVariantTTSTests.swift`:

```swift
import Testing
@testable import VoiceFlowPro

@Suite("ModelVariant TTS cases")
struct ModelVariantTTSTests {
    @Test func isTTSModelTrueForTTSCases() {
        let ttsCases: [ModelVariant] = [
            .qwen3TTS06B4bit, .qwen3TTS06B8bit, .qwen3TTS06Bbf16,
            .qwen3TTS17B4bit, .qwen3TTS17B8bit, .qwen3TTS17Bbf16,
        ]
        for c in ttsCases {
            #expect(c.isTTSModel, "\(c) should be a TTS model")
        }
    }

    @Test func isTTSModelFalseForNonTTSCases() {
        #expect(!ModelVariant.parakeetV3.isTTSModel)
        #expect(!ModelVariant.qwen3ASR.isTTSModel)
        #expect(!ModelVariant.sortformerStreaming.isTTSModel)
        #expect(!ModelVariant.qwen3ForcedAligner.isTTSModel)
    }

    @Test func ttsModelsStaticGroupContainsSixModels() {
        #expect(ModelVariant.ttsModels.count == 6)
        #expect(ModelVariant.ttsModels.allSatisfy { $0.isTTSModel })
    }

    @Test func huggingFaceRepoIdCorrectForTTSCases() {
        #expect(ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit")
        #expect(ModelVariant.qwen3TTS06B8bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")
        #expect(ModelVariant.qwen3TTS06Bbf16.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
        #expect(ModelVariant.qwen3TTS17B4bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit")
        #expect(ModelVariant.qwen3TTS17B8bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit")
        #expect(ModelVariant.qwen3TTS17Bbf16.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    }

    @Test func displayNameNonEmptyForTTSCases() {
        for c in ModelVariant.ttsModels {
            #expect(!c.displayName.isEmpty)
        }
    }
}
```

- [ ] **Step 1.2: Run tests — expect FAIL (cases don't exist yet)**

```bash
swift test --filter ModelVariantTTSTests 2>&1 | tail -10
```
Expected: compile error "type 'ModelVariant' has no member 'qwen3TTS06B4bit'"

- [ ] **Step 1.3: Add TTS cases to ModelVariant enum**

In `Sources/VoiceFlowPro/Models/DataTypes.swift`, after the `sortformerOffline` case (around line 240), add:

```swift
  // MARK: - TTS models
  case qwen3TTS06B4bit = "qwen3-tts-0.6b-4bit"
  case qwen3TTS06B8bit = "qwen3-tts-0.6b-8bit"
  case qwen3TTS06Bbf16 = "qwen3-tts-0.6b-bf16"
  case qwen3TTS17B4bit = "qwen3-tts-1.7b-4bit"
  case qwen3TTS17B8bit = "qwen3-tts-1.7b-8bit"
  case qwen3TTS17Bbf16 = "qwen3-tts-1.7b-bf16"
```

- [ ] **Step 1.4: Add isTTSModel and ttsModels to DataTypes.swift**

In the `AccessLevel helpers` extension (after `vadModels`), add:

```swift
  /// All TTS model variants.
  public static var ttsModels: [ModelVariant] {
    allCases.filter { $0.isTTSModel }
  }
```

In the main `ModelVariant` body, add computed property near `isSortformerVADModel`:

```swift
  var isTTSModel: Bool {
    switch self {
    case .qwen3TTS06B4bit, .qwen3TTS06B8bit, .qwen3TTS06Bbf16,
         .qwen3TTS17B4bit, .qwen3TTS17B8bit, .qwen3TTS17Bbf16:
      return true
    default:
      return false
    }
  }
```

Also update `isMLXAudioModel`:

```swift
  var isMLXAudioModel: Bool {
    isQwen3Model || isSortformerVADModel || isTTSModel
  }
```

- [ ] **Step 1.5: Add TTS cases to all exhaustive switch statements in DataTypes.swift**

Add to `displayName` switch:
```swift
    case .qwen3TTS06B4bit: return "Qwen3 TTS 0.6B (4-bit)"
    case .qwen3TTS06B8bit: return "Qwen3 TTS 0.6B (8-bit)"
    case .qwen3TTS06Bbf16: return "Qwen3 TTS 0.6B (bf16)"
    case .qwen3TTS17B4bit: return "Qwen3 TTS 1.7B (4-bit)"
    case .qwen3TTS17B8bit: return "Qwen3 TTS 1.7B (8-bit)"
    case .qwen3TTS17Bbf16: return "Qwen3 TTS 1.7B (bf16)"
```

Add to `huggingFaceRepoId` switch (in `Qwen3ASRTranscriber.swift` extension or wherever defined):
```swift
    case .qwen3TTS06B4bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"
    case .qwen3TTS06B8bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    case .qwen3TTS06Bbf16: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    case .qwen3TTS17B4bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit"
    case .qwen3TTS17B8bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
    case .qwen3TTS17Bbf16: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
```

Add to `summary` switch:
```swift
    case _ where self.isTTSModel:
      return "MLX-based TTS model for voice cloning and synthesis on Apple Silicon."
```

Add to `fileSize` switch:
```swift
    case .qwen3TTS06B4bit: return 400
    case .qwen3TTS06B8bit: return 500
    case .qwen3TTS06Bbf16: return 900
    case .qwen3TTS17B4bit: return 700
    case .qwen3TTS17B8bit: return 900
    case .qwen3TTS17Bbf16: return 2000
```

Add to `speedScore` switch:
```swift
    case .qwen3TTS06B4bit: return 9.0
    case .qwen3TTS06B8bit: return 8.5
    case .qwen3TTS06Bbf16: return 7.5
    case .qwen3TTS17B4bit: return 8.0
    case .qwen3TTS17B8bit: return 7.5
    case .qwen3TTS17Bbf16: return 6.5
```

Add to `accuracyScore` switch:
```swift
    case .qwen3TTS06B4bit: return 8.5
    case .qwen3TTS06B8bit: return 9.0
    case .qwen3TTS06Bbf16: return 9.2
    case .qwen3TTS17B4bit: return 9.0
    case .qwen3TTS17B8bit: return 9.3
    case .qwen3TTS17Bbf16: return 9.5
```

`supportedLanguages`, `languageSummary`, `featureHighlights`, `accuracy` all have `default:` branches that cover TTS correctly — no changes needed.

`isHiddenFromSelection` `default: return false` covers TTS correctly (they don't appear in ASR selector since ASR uses `ModelVariant.alignerModels` / `vadModels` explicitly).

- [ ] **Step 1.6: Build to confirm no exhaustiveness errors**

```bash
swift build 2>&1 | grep -E "error:|warning:" | grep -v "deprecated" | head -20
```
Expected: no errors (warnings about TTS cases in switch statements would show if any were missed).

- [ ] **Step 1.7: Run TTS case tests — expect PASS**

```bash
swift test --filter ModelVariantTTSTests 2>&1 | tail -10
```
Expected: `Test run with 5 tests passed`

- [ ] **Step 1.8: Commit**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift \
        Sources/VoiceFlowProTests/Models/ModelVariantTTSTests.swift
git commit -m "feat: add TTS ModelVariant cases with isTTSModel and ttsModels

- Add qwen3TTS06B4bit/8bit/bf16 and qwen3TTS17B4bit/8bit/bf16 cases
- Add isTTSModel computed property and ttsModels static group
- Update isMLXAudioModel to include TTS models
- Add TTS values to all exhaustive switch statements

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add modelVariant to MLXTTSModelDefinition

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/TextToSpeechModels.swift`
- Test: `Sources/VoiceFlowProTests/Models/ModelVariantTTSTests.swift` *(extend)*

- [ ] **Step 2.1: Write failing tests**

Append to `ModelVariantTTSTests.swift`:

```swift
    @Test func ttsDefinitionModelVariantMappings() {
        let models = MLXTTSModelDefinition.availableModels
        #expect(models.count == 6)
        let variants = models.map { $0.modelVariant }
        #expect(variants.contains(.qwen3TTS06B4bit))
        #expect(variants.contains(.qwen3TTS06B8bit))
        #expect(variants.contains(.qwen3TTS06Bbf16))
        #expect(variants.contains(.qwen3TTS17B4bit))
        #expect(variants.contains(.qwen3TTS17B8bit))
        #expect(variants.contains(.qwen3TTS17Bbf16))
    }

    @Test func ttsDefinitionRepoIdMatchesVariantRepoId() {
        for def in MLXTTSModelDefinition.availableModels {
            #expect(
                def.huggingFaceRepo == def.modelVariant.huggingFaceRepoId,
                "\(def.id): huggingFaceRepo mismatch"
            )
        }
    }
```

- [ ] **Step 2.2: Run tests — expect FAIL**

```bash
swift test --filter ModelVariantTTSTests 2>&1 | tail -10
```
Expected: compile error "value of type 'MLXTTSModelDefinition' has no member 'modelVariant'"

- [ ] **Step 2.3: Add modelVariant property to MLXTTSModelDefinition**

In `Sources/VoiceFlowPro/Models/TextToSpeechModels.swift`, add to `MLXTTSModelDefinition`:

```swift
    public let modelVariant: ModelVariant
```

Update `init` to include the new parameter:

```swift
    public init(
        id: String,
        displayName: String,
        huggingFaceRepo: String,
        parameterSize: String,
        estimatedSizeMB: Int,
        supportsVoiceDesign: Bool,
        supportsVoiceClone: Bool,
        description: String,
        family: TTSModelFamily,
        quantization: String,
        modelVariant: ModelVariant
    ) {
        self.id = id
        self.displayName = displayName
        self.huggingFaceRepo = huggingFaceRepo
        self.parameterSize = parameterSize
        self.estimatedSizeMB = estimatedSizeMB
        self.supportsVoiceDesign = supportsVoiceDesign
        self.supportsVoiceClone = supportsVoiceClone
        self.description = description
        self.family = family
        self.quantization = quantization
        self.modelVariant = modelVariant
    }
```

- [ ] **Step 2.4: Update all 6 MLXTTSModelDefinition instances in availableModels**

Add `modelVariant:` to each definition in the `availableModels` array:

```swift
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-base-4bit",
            displayName: "Qwen3 TTS 0.6B Base (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 400,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Lightweight base model for fast voice cloning.",
            family: .base,
            quantization: "4-bit",
            modelVariant: .qwen3TTS06B4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-base-8bit",
            displayName: "Qwen3 TTS 0.6B Base (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 500,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Balanced quality and speed for everyday synthesis.",
            family: .base,
            quantization: "8-bit",
            modelVariant: .qwen3TTS06B8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-base-bf16",
            displayName: "Qwen3 TTS 0.6B Base (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16",
            parameterSize: "0.6B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Full-precision base model with higher fidelity.",
            family: .base,
            quantization: "bf16",
            modelVariant: .qwen3TTS06Bbf16
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-base-4bit",
            displayName: "Qwen3 TTS 1.7B Base (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 700,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Larger base model with stronger voice quality.",
            family: .base,
            quantization: "4-bit",
            modelVariant: .qwen3TTS17B4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-base-8bit",
            displayName: "Qwen3 TTS 1.7B Base (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "High-quality 1.7B base model for richer synthesis.",
            family: .base,
            quantization: "8-bit",
            modelVariant: .qwen3TTS17B8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-base-bf16",
            displayName: "Qwen3 TTS 1.7B Base (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
            parameterSize: "1.7B",
            estimatedSizeMB: 2000,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Highest-fidelity 1.7B base model.",
            family: .base,
            quantization: "bf16",
            modelVariant: .qwen3TTS17Bbf16
        ),
```

- [ ] **Step 2.5: Run tests — expect PASS**

```bash
swift test --filter ModelVariantTTSTests 2>&1 | tail -10
```
Expected: all 7 tests pass.

- [ ] **Step 2.6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/TextToSpeechModels.swift \
        Sources/VoiceFlowProTests/Models/ModelVariantTTSTests.swift
git commit -m "feat: add modelVariant to MLXTTSModelDefinition

Each TTS definition now maps to its corresponding ModelVariant case,
enabling unified download/status/delete via ModelDownloadManager.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Add TTS download path and modelSizeInMB to ModelDownloadManager

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift` *(extend)*

- [ ] **Step 3.1: Write failing tests**

Append to `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift` inside the `"ModelDownloadManager MLX Audio model detection"` suite:

```swift
    @Test("modelSizeInMB returns 0 for non-existent TTS model")
    func modelSizeInMBZeroForMissingTTSModel() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            accessController: MockAccessController(permissionQueue: []),
            fileManager: .default
        )
        let size = await manager.modelSizeInMB(for: .qwen3TTS06B4bit)
        #expect(size == 0)
    }

    @Test("modelSizeInMB returns non-zero for seeded TTS model")
    func modelSizeInMBNonZeroForSeededTTSModel() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data(count: 1024 * 1024).write(to: modelDir.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            accessController: MockAccessController(permissionQueue: []),
            fileManager: .default
        )
        let size = await manager.modelSizeInMB(for: .qwen3TTS06B4bit)
        #expect(size >= 1)
    }

    @Test("hasLocalArtifacts returns false for TTS model without config.json")
    func hasLocalArtifactsTTSReturnsFalseWithoutConfig() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            accessController: MockAccessController(permissionQueue: []),
            fileManager: .default
        )
        let result = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(!result, "TTS model without config.json should not be considered cached")
    }

    @Test("hasLocalArtifacts returns true for TTS model with config.json and safetensors")
    func hasLocalArtifactsTTSReturnsTrueWithBothFiles() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        try Data("{\"model_type\":\"qwen3_tts\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            accessController: MockAccessController(permissionQueue: []),
            fileManager: .default
        )
        let result = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(result, "TTS model with config.json and safetensors should be considered cached")
    }
```

- [ ] **Step 3.2: Run tests — expect FAIL**

```bash
swift test --filter ModelDownloadManagerTests 2>&1 | grep -E "error:|Expectation failed|passed|failed" | tail -10
```
Expected: compile error "value of type 'ModelDownloadManager' has no member 'modelSizeInMB'"

- [ ] **Step 3.3: Add modelSizeInMB to ModelDownloadManager**

In `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`, add after `getModelDirectorySync`:

```swift
  /// On-disk size of a model's directory in megabytes.
  func modelSizeInMB(for model: ModelVariant) -> Int {
    let dir = mlxAudioDirectory(forRepo: model.huggingFaceRepoId)
    return Self.directorySizeInMB(dir)
  }

  private static func directorySizeInMB(_ url: URL) -> Int {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
    else { return 0 }
    var totalBytes: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        totalBytes += Int64(size)
      }
    }
    return Int(totalBytes / (1024 * 1024))
  }
```

- [ ] **Step 3.4: Add TTS case to downloadMLXAudioModel switch**

In `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`, find the `switch model` block inside `downloadMLXAudioModel` (around line 161) and add before `default:`:

```swift
          case _ where model.isTTSModel:
            _ = try await ModelUtils.resolveOrDownloadModel(
              repoID: .init(rawValue: model.huggingFaceRepoId)!,
              requiredExtension: "safetensors"
            )
```

- [ ] **Step 3.5: Run tests — expect PASS**

```bash
swift test --filter ModelDownloadManagerTests 2>&1 | tail -10
```
Expected: all tests pass (including the 4 new ones).

- [ ] **Step 3.6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelDownloadManager.swift \
        Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift
git commit -m "feat: add TTS download path and modelSizeInMB to ModelDownloadManager

- TTS models now download via downloadMLXAudioModel (ModelUtils path)
- modelSizeInMB(for:) computes directory size using FileManager
- hasLocalArtifacts already covers TTS via unified hasLocalModel

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Migrate MLXTTSDownloadManager tests, then delete the file

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTTSTests.swift`
- Delete: `Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift`
- Delete: `Sources/VoiceFlowProTests/Services/MLXTTSDownloadManagerTests.swift`

- [ ] **Step 4.1: Create ModelDownloadManagerTTSTests.swift**

Create `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTTSTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceFlowPro

@Suite("ModelDownloadManager TTS model detection")
struct ModelDownloadManagerTTSTests {
    private func makeManager(hubRoot: URL) -> ModelDownloadManager {
        ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            accessController: MockAccessController(permissionQueue: []),
            fileManager: .default
        )
    }

    @Test("isModelCached returns false for non-existent TTS repo")
    func isModelCachedFalseForMissingRepo() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = makeManager(hubRoot: hubRoot)
        let cached = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(!cached)
    }

    @Test("isModelCached returns false when only safetensors present (no config.json)")
    func isModelCachedFalseWhenMissingConfig() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = makeManager(hubRoot: hubRoot)
        let cached = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(!cached, "config.json is required; safetensors-only should not be considered cached")
    }

    @Test("isModelCached returns true when safetensors and config.json present")
    func isModelCachedTrueWithBothFiles() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        try Data("{\"model_type\":\"qwen3_tts\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = makeManager(hubRoot: hubRoot)
        let cached = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(cached, "Both safetensors and config.json present — should be cached")
    }

    @Test("cacheSizeInMB returns 0 for empty directory")
    func cacheSizeMBZero() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = makeManager(hubRoot: hubRoot)
        let size = await manager.modelSizeInMB(for: .qwen3TTS06B8bit)
        #expect(size == 0)
    }

    @Test("cacheSizeInMB returns non-zero for seeded 1MB file")
    func cacheSizeMBNonZero() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B8bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data(count: 1024 * 1024).write(to: modelDir.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = makeManager(hubRoot: hubRoot)
        let size = await manager.modelSizeInMB(for: .qwen3TTS06B8bit)
        #expect(size >= 1)
    }

    @Test("delete removes TTS model directory")
    func deleteTTSModel() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let subdir = ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId
            .replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = makeManager(hubRoot: hubRoot)
        #expect(FileManager.default.fileExists(atPath: modelDir.path))
        try await manager.delete(model: .qwen3TTS06B4bit)
        #expect(!FileManager.default.fileExists(atPath: modelDir.path))
    }
}
```

- [ ] **Step 4.2: Verify new tests compile and pass**

```bash
swift test --filter ModelDownloadManagerTTSTests 2>&1 | tail -10
```
Expected: all 7 tests pass.

- [ ] **Step 4.3: Delete MLXTTSDownloadManager.swift and its test file**

```bash
rm Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift
rm Sources/VoiceFlowProTests/Services/MLXTTSDownloadManagerTests.swift
```

- [ ] **Step 4.4: Confirm build still works (callers not yet migrated — expect errors)**

```bash
swift build 2>&1 | grep "error:" | grep -v "deprecated" | head -20
```
Expected: errors referencing `MLXTTSDownloadManager` — these will be fixed in Task 5.

- [ ] **Step 4.5: Commit the test migration (before fixing callers)**

```bash
git add Sources/VoiceFlowProTests/Services/ModelDownloadManagerTTSTests.swift
git rm Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift
git rm Sources/VoiceFlowProTests/Services/MLXTTSDownloadManagerTests.swift
git commit -m "test: migrate MLXTTSDownloadManager tests to ModelDownloadManagerTTSTests

Tests now use cacheRootProvider injection. isModelCached semantics updated
to require config.json + safetensors (matches ModelUtils cache validation).

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Update call sites in ModelsView, TTSSynthesisView, ModelCacheManager

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
- Modify: `Sources/VoiceFlowPro/Views/TTSSynthesisView.swift`
- Modify: `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`

- [ ] **Step 5.1: Update ModelsView — refreshStatuses (status and size dicts)**

Find the loop that populates `mlxStatuses` / `mlxSizes` (around line 1083):

```swift
    // OLD
    for def in MLXTTSModelDefinition.availableModels {
      mlxStatuses[def.huggingFaceRepo] = await MLXTTSDownloadManager.shared.isModelCached(repoId: def.huggingFaceRepo)
      mlxSizes[def.huggingFaceRepo] = await MLXTTSDownloadManager.shared.cacheSizeInMB(repoId: def.huggingFaceRepo)
    }
```

Replace with:

```swift
    // NEW
    for def in MLXTTSModelDefinition.availableModels {
      mlxStatuses[def.huggingFaceRepo] = await ModelDownloadManager.shared.hasLocalArtifacts(for: def.modelVariant)
      mlxSizes[def.huggingFaceRepo] = await ModelDownloadManager.shared.modelSizeInMB(for: def.modelVariant)
    }
```

- [ ] **Step 5.2: Update ModelsView — startMLXDownload**

```swift
    // OLD
    try await MLXTTSDownloadManager.shared.download(definition: definition) { progress in ... }
```

Replace with:

```swift
    // NEW
    try await ModelDownloadManager.shared.download(model: definition.modelVariant) { progress in ... }
```

- [ ] **Step 5.3: Update ModelsView — cancelMLXDownload**

```swift
    // OLD
    await MLXTTSDownloadManager.shared.cancelDownload(repoId: definition.huggingFaceRepo)
```

Replace with:

```swift
    // NEW
    await ModelDownloadManager.shared.cancelDownload(for: definition.modelVariant)
```

- [ ] **Step 5.4: Update ModelsView — deleteMLXModel**

```swift
    // OLD
    try await MLXTTSDownloadManager.shared.deleteModel(repoId: repoId)
```

Replace with:

```swift
    // NEW
    try await ModelDownloadManager.shared.delete(model: definition.modelVariant)
```

- [ ] **Step 5.5: Update ModelsView — openMLXModelFolder**

```swift
    // OLD
    let cacheDir = await MLXTTSDownloadManager.shared.modelDirectory(repoId: definition.huggingFaceRepo)
```

Replace with:

```swift
    // NEW
    let cacheDir = await ModelDownloadManager.shared.getModelDirectory(for: definition.modelVariant)
                   ?? ModelDownloadManager.shared.mlxAudioDirectory(forRepo: definition.modelVariant.huggingFaceRepoId)
```

- [ ] **Step 5.6: Update TTSSynthesisView — isModelCached check**

Find the loop in `refreshStatus` (around line 688):

```swift
    // OLD
    let cached = await MLXTTSDownloadManager.shared.isModelCached(repoId: def.huggingFaceRepo)
```

Replace with:

```swift
    // NEW
    let cached = await ModelDownloadManager.shared.hasLocalArtifacts(for: def.modelVariant)
```

- [ ] **Step 5.7: Update ModelCacheManager — isModelCached and cacheSizeInMB**

Line ~242:
```swift
    // OLD
    let isCached = await MLXTTSDownloadManager.shared.isModelCached(repoId: modelID)
```
Replace with:
```swift
    // NEW
    let isCached: Bool
    if let def = MLXTTSModelDefinition.availableModels.first(where: { $0.huggingFaceRepo == modelID }) {
        isCached = await ModelDownloadManager.shared.hasLocalArtifacts(for: def.modelVariant)
    } else {
        isCached = false
    }
```

Lines ~610, ~617:
```swift
    // OLD
    return await MLXTTSDownloadManager.shared.cacheSizeInMB(repoId: modelID)
    return await MLXTTSDownloadManager.shared.cacheSizeInMB(repoId: resource.modelID)
```
Replace with (for each):
```swift
    // NEW — line ~610
    if let def = MLXTTSModelDefinition.availableModels.first(where: { $0.huggingFaceRepo == modelID }) {
        return await ModelDownloadManager.shared.modelSizeInMB(for: def.modelVariant)
    }
    return 0
    // NEW — line ~617
    if let def = MLXTTSModelDefinition.availableModels.first(where: { $0.huggingFaceRepo == resource.modelID }) {
        return await ModelDownloadManager.shared.modelSizeInMB(for: def.modelVariant)
    }
    return 0
```

- [ ] **Step 5.8: Build — expect zero errors**

```bash
swift build 2>&1 | grep "error:" | grep -v "deprecated" | head -20
```
Expected: no errors.

- [ ] **Step 5.9: Run all tests**

```bash
swift test 2>&1 | tail -15
```
Expected: all test suites pass.

- [ ] **Step 5.10: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ModelsView.swift \
        Sources/VoiceFlowPro/Views/TTSSynthesisView.swift \
        Sources/VoiceFlowPro/Services/ModelCacheManager.swift \
        docs/superpowers/specs/2026-04-20-merge-tts-into-modelvariant-design.md
git commit -m "feat: route TTS download/status/delete through ModelDownloadManager

- ModelsView, TTSSynthesisView, ModelCacheManager now use
  ModelDownloadManager.shared instead of MLXTTSDownloadManager.shared
- isModelCached now requires config.json + safetensors (bug fix)
- deleteModel now fires ModelArtifactStatusNotifier.postChange (bug fix)
- All path resolution unified through cacheRootProvider

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
