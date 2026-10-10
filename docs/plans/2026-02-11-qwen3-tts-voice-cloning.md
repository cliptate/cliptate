# Qwen3 TTS + Voice Cloning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate Qwen3 TTS models via mlx-audio-swift, support voice design and voice cloning with reference audio, unify the TTS Studio with an engine switcher, and add MLX TTS model management to the Models page.

**Architecture:** Add `MLXAudioTTS` as a Swift Package dependency. Create a new `MLXTTSService` actor that wraps the `SpeechGenerationModel` protocol for model loading, audio generation, and WAV conversion. Define `MLXTTSModelDefinition` structs describing available HuggingFace model repos with capability flags (supportsVoiceDesign, supportsVoiceClone). Extend `TTSEngine` enum to include `.qwen3TTS`. Update the unified `TTSSynthesisView` with an engine picker at top, plus dynamic voice controls (text description for VoiceDesign, audio file picker + transcript for VoiceClone). Update `ModelsView` TTS tab to show MLX model download cards alongside Kokoro.

**Tech Stack:** Swift 6.2, SwiftUI, mlx-audio-swift (MLXAudioTTS, MLXAudioCore), HuggingFace Hub, AVFoundation

---

## Task 1: Add MLXAudioTTS Dependency to Package.swift

**Files:**
- Modify: `Package.swift`

**Step 1: Add MLXAudioTTS product dependency**

In `Package.swift`, add `MLXAudioTTS` to the target dependencies. The `mlx-audio-swift` package is already declared as a dependency (branch: main). We just need to add the TTS product.

```swift
// In targets[0].dependencies, add after MLXAudioCore:
.product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
```

**Step 2: Verify the build resolves**

Run:
```bash
cd <repository>
swift package resolve 2>&1 | tail -5
```
Expected: Dependencies resolve successfully.

**Step 3: Verify compilation**

Run:
```bash
swift build 2>&1 | tail -20
```
Expected: Build succeeds (or existing warnings only, no new errors).

**Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "feat: add MLXAudioTTS dependency from mlx-audio-swift"
```

---

## Task 2: Extend TTSEngine Enum and Define MLX TTS Models

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/TextToSpeechModels.swift`

**Step 1: Write failing test for new TTSEngine case**

Create test file:
- Create: `Sources/VoiceFlowProTests/Models/TextToSpeechModelsTests.swift`

```swift
import Testing
@testable import VoiceFlowPro

@Suite("TextToSpeechModels Tests")
struct TextToSpeechModelsTests {

    @Test("TTSEngine has qwen3TTS case")
    func testTTSEngineHasQwen3TTS() {
        let engine = TTSEngine.qwen3TTS
        #expect(engine.displayName == "Qwen3 TTS")
        #expect(engine.rawValue == "qwen3TTS")
    }

    @Test("TTSEngine qwen3TTS subtitle")
    func testQwen3TTSSubtitle() {
        let engine = TTSEngine.qwen3TTS
        #expect(engine.subtitle.contains("MLX"))
    }

    @Test("MLXTTSModelDefinition has expected models")
    func testMLXTTSModelDefinitions() {
        let models = MLXTTSModelDefinition.availableModels
        #expect(models.count >= 1)

        let voiceDesign = models.first { $0.id == "qwen3-tts-voicedesign" }
        #expect(voiceDesign != nil)
        #expect(voiceDesign?.supportsVoiceDesign == true)
        #expect(voiceDesign?.huggingFaceRepo != nil)
    }

    @Test("MLXTTSModelDefinition voice cloning model")
    func testVoiceCloningModel() {
        let models = MLXTTSModelDefinition.availableModels
        let cloneModel = models.first { $0.supportsVoiceClone }
        #expect(cloneModel != nil)
        #expect(cloneModel?.huggingFaceRepo != nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
swift test --filter TextToSpeechModelsTests 2>&1 | tail -10
```
Expected: FAIL - `qwen3TTS` not found, `MLXTTSModelDefinition` not found.

**Step 3: Implement TTSEngine extension and MLXTTSModelDefinition**

Add to `TextToSpeechModels.swift`:

```swift
// --- Extend TTSEngine enum ---
public enum TTSEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case kokoro
    case qwen3TTS

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kokoro: return "Kokoro"
        case .qwen3TTS: return "Qwen3 TTS"
        }
    }

    public var subtitle: String {
        switch self {
        case .kokoro:
            return "FluidAudio Kokoro 82M CoreML voice synthesis"
        case .qwen3TTS:
            return "MLX Qwen3 TTS with voice design & cloning"
        }
    }

    public var recommendedVoices: [KokoroVoice] {
        switch self {
        case .kokoro:
            return KokoroVoice.americanEnglishVoices
        case .qwen3TTS:
            return []
        }
    }
}

// --- MLX TTS Model Definitions ---
public struct MLXTTSModelDefinition: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let huggingFaceRepo: String
    public let parameterSize: String
    public let estimatedSizeMB: Int
    public let supportsVoiceDesign: Bool
    public let supportsVoiceClone: Bool
    public let description: String

    public static let availableModels: [MLXTTSModelDefinition] = [
        MLXTTSModelDefinition(
            id: "qwen3-tts-voicedesign",
            displayName: "Qwen3 TTS VoiceDesign",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
            parameterSize: "1.7B",
            estimatedSizeMB: 3400,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Design voices with text descriptions. 'A warm female voice with confident tone.'"
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-base",
            displayName: "Qwen3 TTS Base",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit",
            parameterSize: "1.7B (4-bit)",
            estimatedSizeMB: 1700,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Clone any voice from a 3-second audio sample. High-fidelity multilingual."
        ),
    ]
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter TextToSpeechModelsTests 2>&1 | tail -10
```
Expected: All 4 tests PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Models/TextToSpeechModels.swift Sources/VoiceFlowProTests/Models/TextToSpeechModelsTests.swift
git commit -m "feat: add Qwen3 TTS engine and MLX model definitions"
```

---

## Task 3: Create MLXTTSService Actor

**Files:**
- Create: `Sources/VoiceFlowPro/Services/MLXTTSService.swift`
- Create: `Sources/VoiceFlowProTests/Services/MLXTTSServiceTests.swift`

**Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import VoiceFlowPro

@Suite("MLXTTSService Tests")
struct MLXTTSServiceTests {

    @Test("Service is singleton actor")
    func testSingleton() async {
        let service = MLXTTSService.shared
        #expect(service != nil)
    }

    @Test("isModelLoaded returns false initially")
    func testInitialState() async {
        let loaded = await MLXTTSService.shared.isModelLoaded
        #expect(loaded == false)
    }

    @Test("convertToWAVData converts float samples to WAV")
    func testConvertToWAVData() async throws {
        // Generate 1 second of silence at 24kHz
        let sampleRate = 24000
        let samples = [Float](repeating: 0.0, count: sampleRate)
        let wavData = try MLXTTSService.createWAVData(from: samples, sampleRate: sampleRate)
        #expect(wavData.count > 44) // WAV header is 44 bytes
    }

    @Test("synthesize throws when model not loaded")
    func testSynthesizeWithoutModel() async {
        do {
            _ = try await MLXTTSService.shared.synthesize(
                text: "Hello",
                modelDefinition: MLXTTSModelDefinition.availableModels[0],
                voiceDescription: nil,
                referenceAudioURL: nil,
                referenceText: nil,
                language: "en"
            )
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter MLXTTSServiceTests 2>&1 | tail -10
```
Expected: FAIL - `MLXTTSService` not found.

**Step 3: Implement MLXTTSService**

```swift
import Foundation
import AVFoundation
@preconcurrency import MLXAudioTTS
@preconcurrency import MLXAudioCore
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

/// Coordinates MLX-based TTS model loading, synthesis, and WAV conversion.
actor MLXTTSService {
    static let shared = MLXTTSService()

    private var currentModel: (any SpeechGenerationModel)?
    private var currentModelRepo: String?
    private var loadTask: Task<Void, Error>?

    var isModelLoaded: Bool { currentModel != nil }
    var loadedModelRepo: String? { currentModelRepo }

    /// Load a TTS model from HuggingFace.
    func loadModel(definition: MLXTTSModelDefinition) async throws {
        if currentModelRepo == definition.huggingFaceRepo, currentModel != nil { return }

        loadTask?.cancel()
        let task = Task {
            let model = try await TTSModelUtils.loadModel(modelRepo: definition.huggingFaceRepo)
            self.currentModel = model
            self.currentModelRepo = definition.huggingFaceRepo
        }
        loadTask = task
        try await task.value
        loadTask = nil
    }

    /// Synthesize speech. Supports VoiceDesign (voiceDescription) and VoiceClone (referenceAudioURL + referenceText).
    func synthesize(
        text: String,
        modelDefinition: MLXTTSModelDefinition,
        voiceDescription: String?,
        referenceAudioURL: URL?,
        referenceText: String?,
        language: String?
    ) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MLXTTSError.emptyInput
        }

        // Ensure model is loaded
        if currentModelRepo != modelDefinition.huggingFaceRepo || currentModel == nil {
            try await loadModel(definition: modelDefinition)
        }

        guard let model = currentModel else {
            throw MLXTTSError.modelNotLoaded
        }

        // Prepare reference audio for voice cloning
        var refAudio: MLXArray? = nil
        var refText: String? = nil
        if let audioURL = referenceAudioURL {
            let (_, audioData) = try loadAudioArray(from: audioURL)
            refAudio = audioData
            refText = referenceText
        }

        let params = GenerateParameters(
            temperature: 0.9,
            topP: 0.95,
            repetitionPenalty: 1.05
        )

        let audioArray = try await model.generate(
            text: trimmed,
            voice: voiceDescription,
            refAudio: refAudio,
            refText: refText,
            language: language,
            generationParameters: params
        )

        let samples = audioArray.asArray(Float.self)
        return try Self.createWAVData(from: samples, sampleRate: model.sampleRate)
    }

    /// Reset loaded model to free memory.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentModel = nil
        currentModelRepo = nil
    }

    /// Convert float samples to WAV Data.
    static func createWAVData(from samples: [Float], sampleRate: Int) throws -> Data {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw MLXTTSError.audioConversionFailed
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for i in 0..<samples.count {
                channelData[0][i] = samples[i]
            }
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }
}

enum MLXTTSError: LocalizedError {
    case emptyInput
    case modelNotLoaded
    case audioConversionFailed
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "Please enter text before synthesizing."
        case .modelNotLoaded: return "TTS model is not loaded. Download it from the Models page."
        case .audioConversionFailed: return "Failed to convert audio to WAV format."
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter MLXTTSServiceTests 2>&1 | tail -10
```
Expected: All 4 tests PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/MLXTTSService.swift Sources/VoiceFlowProTests/Services/MLXTTSServiceTests.swift
git commit -m "feat: add MLXTTSService actor for MLX-based TTS synthesis"
```

---

## Task 4: Create MLXTTSDownloadManager

**Files:**
- Create: `Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift`

**Step 1: Write failing test**

- Create: `Sources/VoiceFlowProTests/Services/MLXTTSDownloadManagerTests.swift`

```swift
import Testing
import Foundation
@testable import VoiceFlowPro

@Suite("MLXTTSDownloadManager Tests")
struct MLXTTSDownloadManagerTests {

    @Test("Manager is singleton actor")
    func testSingleton() async {
        let manager = MLXTTSDownloadManager.shared
        #expect(manager != nil)
    }

    @Test("isModelCached returns false for unknown repo")
    func testIsModelCachedFalse() async {
        let cached = await MLXTTSDownloadManager.shared.isModelCached(
            repoId: "nonexistent/model-that-does-not-exist"
        )
        #expect(cached == false)
    }

    @Test("cacheSizeInMB returns 0 for unknown model")
    func testCacheSizeMBZero() async {
        let size = await MLXTTSDownloadManager.shared.cacheSizeInMB(
            repoId: "nonexistent/model-that-does-not-exist"
        )
        #expect(size == 0)
    }
}
```

**Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter MLXTTSDownloadManagerTests 2>&1 | tail -10
```
Expected: FAIL - `MLXTTSDownloadManager` not found.

**Step 3: Implement MLXTTSDownloadManager**

```swift
import Foundation
@preconcurrency import MLXAudioCore

/// Manages downloading and caching of MLX TTS models from HuggingFace.
actor MLXTTSDownloadManager {
    static let shared = MLXTTSDownloadManager()

    private var activeDownloads: [String: Task<Void, Error>] = [:]

    /// Base cache directory for MLX Audio models.
    private var cacheBaseURL: URL {
        URL.cachesDirectory.appendingPathComponent("mlx-audio")
    }

    /// Check if a model is already cached locally.
    func isModelCached(repoId: String) -> Bool {
        let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = cacheBaseURL.appendingPathComponent(modelSubdir)
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelDir.path) else { return false }
        let files = try? fm.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
        return files?.contains { $0.pathExtension == "safetensors" } ?? false
    }

    /// Get disk usage for a cached model in MB.
    func cacheSizeInMB(repoId: String) -> Int {
        let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = cacheBaseURL.appendingPathComponent(modelSubdir)
        return Self.directorySizeInMB(modelDir)
    }

    /// Download a model. Uses MLXAudioCore ModelUtils internally.
    /// Progress is estimated: 0.0 → model loading starts, 1.0 → complete.
    func download(
        definition: MLXTTSModelDefinition,
        progressHandler: @Sendable @escaping (ModelDownloadProgress) -> Void
    ) async throws {
        let repoId = definition.huggingFaceRepo

        // Deduplicate active downloads
        if let existing = activeDownloads[repoId] {
            try await existing.value
            return
        }

        let task = Task {
            progressHandler(ModelDownloadProgress(
                currentStep: "Downloading \(definition.displayName)…",
                progress: 0.05
            ))

            // ModelUtils.resolveOrDownloadModel handles caching internally
            _ = try await ModelUtils.resolveOrDownloadModel(
                repoID: .init(rawValue: repoId)!,
                requiredExtension: "safetensors"
            )

            progressHandler(ModelDownloadProgress(
                currentStep: "Download complete",
                progress: 1.0
            ))
        }

        activeDownloads[repoId] = task
        defer { activeDownloads[repoId] = nil }
        try await task.value
    }

    /// Cancel an active download.
    func cancelDownload(repoId: String) {
        activeDownloads[repoId]?.cancel()
        activeDownloads[repoId] = nil
    }

    /// Delete a cached model.
    func deleteModel(repoId: String) throws {
        let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = cacheBaseURL.appendingPathComponent(modelSubdir)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        // Also reset the service if this model was loaded
        Task { await MLXTTSService.shared.reset() }
    }

    /// Total disk usage for all MLX TTS models in MB.
    func totalCacheSizeInMB() -> Int {
        Self.directorySizeInMB(cacheBaseURL)
    }

    private static func directorySizeInMB(_ url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalBytes += Int64(size)
            }
        }
        return Int(totalBytes / (1024 * 1024))
    }
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter MLXTTSDownloadManagerTests 2>&1 | tail -10
```
Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift Sources/VoiceFlowProTests/Services/MLXTTSDownloadManagerTests.swift
git commit -m "feat: add MLXTTSDownloadManager for HuggingFace model caching"
```

---

## Task 5: Update AppConfiguration with New TTS Properties

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`

**Step 1: Add new TTS properties**

Add these published properties alongside existing TTS properties (around line 200):

```swift
@Published var ttsMLXModelId: String = "qwen3-tts-voicedesign"
@Published var ttsVoiceDescription: String = ""
@Published var ttsReferenceAudioPath: String = ""
@Published var ttsReferenceText: String = ""
@Published var ttsLanguage: String = "auto"
```

**Step 2: Add to Snapshot struct** (after `ttsSpeakingRate`):

```swift
var ttsMLXModelId: String
var ttsVoiceDescription: String
var ttsReferenceAudioPath: String
var ttsReferenceText: String
var ttsLanguage: String
```

**Step 3: Update defaultSnapshot** (after `ttsSpeakingRate: 1.0`):

```swift
ttsMLXModelId: "qwen3-tts-voicedesign",
ttsVoiceDescription: "",
ttsReferenceAudioPath: "",
ttsReferenceText: "",
ttsLanguage: "auto",
```

**Step 4: Update `snapshot` computed property** (getter, after ttsSpeakingRate):

```swift
ttsMLXModelId: ttsMLXModelId,
ttsVoiceDescription: ttsVoiceDescription,
ttsReferenceAudioPath: ttsReferenceAudioPath,
ttsReferenceText: ttsReferenceText,
ttsLanguage: ttsLanguage,
```

**Step 5: Update `applySnapshot(_:)`** (after ttsSpeakingRate):

```swift
ttsMLXModelId = snap.ttsMLXModelId
ttsVoiceDescription = snap.ttsVoiceDescription
ttsReferenceAudioPath = snap.ttsReferenceAudioPath
ttsReferenceText = snap.ttsReferenceText
ttsLanguage = snap.ttsLanguage
```

**Step 6: Build to verify**

Run:
```bash
swift build 2>&1 | tail -20
```
Expected: Build succeeds.

**Step 7: Commit**

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift
git commit -m "feat: add Qwen3 TTS config properties to AppConfiguration"
```

---

## Task 6: Update ModelsView TTS Tab with MLX Model Cards

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`

**Step 1: Add MLX TTS state variables** (after existing kokoro state vars ~line 59):

```swift
@State private var mlxModelCachedMap: [String: Bool] = [:]
@State private var mlxModelProgressMap: [String: ModelDownloadProgress] = [:]
@State private var mlxModelErrorMap: [String: String] = [:]
@State private var mlxModelSizeMap: [String: Int] = [:]
```

**Step 2: Add MLX TTS section** in `ttsLibrarySection` (after the existing KokoroDownloadCard, before the closing `}`):

```swift
ForEach(MLXTTSModelDefinition.availableModels) { model in
    MLXTTSDownloadCard(
        definition: model,
        isCached: mlxModelCachedMap[model.huggingFaceRepo] ?? false,
        progress: mlxModelProgressMap[model.huggingFaceRepo],
        errorMessage: mlxModelErrorMap[model.huggingFaceRepo],
        diskUsageMB: mlxModelSizeMap[model.huggingFaceRepo] ?? 0,
        onDownload: { startMLXDownload(model) },
        onDelete: { deleteMLXModel(model) },
        onCancel: { cancelMLXDownload(model) }
    )
}
```

**Step 3: Add MLX download helper functions** (after `deleteKokoroAssets()`):

```swift
private func startMLXDownload(_ definition: MLXTTSModelDefinition) {
    mlxModelErrorMap[definition.huggingFaceRepo] = nil
    Task {
        do {
            try await MLXTTSDownloadManager.shared.download(definition: definition) { progress in
                Task { @MainActor in
                    mlxModelProgressMap[definition.huggingFaceRepo] = progress
                }
            }
            await MainActor.run {
                mlxModelProgressMap[definition.huggingFaceRepo] = nil
                mlxModelCachedMap[definition.huggingFaceRepo] = true
            }
        } catch is CancellationError {
            await MainActor.run {
                mlxModelProgressMap[definition.huggingFaceRepo] = nil
            }
        } catch {
            await MainActor.run {
                mlxModelProgressMap[definition.huggingFaceRepo] = nil
                mlxModelErrorMap[definition.huggingFaceRepo] = error.localizedDescription
            }
        }
    }
}

private func cancelMLXDownload(_ definition: MLXTTSModelDefinition) {
    Task {
        await MLXTTSDownloadManager.shared.cancelDownload(repoId: definition.huggingFaceRepo)
    }
}

private func deleteMLXModel(_ definition: MLXTTSModelDefinition) {
    Task {
        do {
            try await MLXTTSDownloadManager.shared.deleteModel(repoId: definition.huggingFaceRepo)
            await refreshStatuses(force: true)
        } catch {
            await MainActor.run {
                mlxModelErrorMap[definition.huggingFaceRepo] = error.localizedDescription
            }
        }
    }
}
```

**Step 4: Update `refreshStatuses()`** to include MLX model cache status (add after kokoro status checks):

```swift
// Refresh MLX TTS model statuses
for model in MLXTTSModelDefinition.availableModels {
    let cached = await MLXTTSDownloadManager.shared.isModelCached(repoId: model.huggingFaceRepo)
    let size = await MLXTTSDownloadManager.shared.cacheSizeInMB(repoId: model.huggingFaceRepo)
    await MainActor.run {
        mlxModelCachedMap[model.huggingFaceRepo] = cached
        mlxModelSizeMap[model.huggingFaceRepo] = size
    }
}
```

**Step 5: Create MLXTTSDownloadCard** (add as private struct at end of file, similar to KokoroDownloadCard):

```swift
private struct MLXTTSDownloadCard: View {
    let definition: MLXTTSModelDefinition
    let isCached: Bool
    let progress: ModelDownloadProgress?
    let errorMessage: String?
    let diskUsageMB: Int
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: definition.supportsVoiceClone ? "mic.badge.plus" : "text.bubble.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(definition.displayName)
                            .font(.title3.weight(.semibold))
                        Text(definition.parameterSize)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(definition.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if definition.supportsVoiceDesign {
                            Label("Voice Design", systemImage: "text.bubble")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                        }
                        if definition.supportsVoiceClone {
                            Label("Voice Clone", systemImage: "mic.badge.plus")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple.opacity(0.12)))
                        }
                    }
                }

                Spacer()

                if let progress {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(progress.currentStep)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(progress.progress), total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                    }
                } else if isCached {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Installed")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.green)
                        if diskUsageMB > 0 {
                            Text("(\(diskUsageMB) MB)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 12) {
                if progress != nil {
                    Button(role: .cancel, action: onCancel) {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                } else if isCached {
                    Button(role: .destructive, action: onDelete) {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onDownload) {
                        Label("Download (~\(definition.estimatedSizeMB) MB)", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
    }
}
```

**Step 6: Update ttsLibrarySection header text** to be more generic:

Change:
```swift
Text("Install Kokoro models for FluidAudio TTS")
```
To:
```swift
Text("Install text-to-speech voice engines")
```

**Step 7: Build to verify**

Run:
```bash
swift build 2>&1 | tail -20
```
Expected: Build succeeds.

**Step 8: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ModelsView.swift
git commit -m "feat: add MLX TTS model download cards to Models page"
```

---

## Task 7: Update TTSSynthesisView with Unified Engine Switcher and Voice Cloning UI

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/TTSSynthesisView.swift`

This is the largest UI task. The view needs:
1. Engine picker at top (Kokoro / Qwen3 TTS)
2. When Qwen3 TTS selected: model selector, voice design text field OR reference audio picker
3. When Kokoro selected: existing voice picker (unchanged)

**Step 1: Add new state variables** (after existing state vars, ~line 15):

```swift
// MLX TTS state
@State private var mlxModelReady = false
@State private var isLoadingMLXModel = false
@State private var mlxModelLoadError: String?
@State private var selectedMLXModel: MLXTTSModelDefinition = MLXTTSModelDefinition.availableModels[0]
@State private var voiceDescriptionText: String = "A warm female voice with a confident, friendly tone and clear enunciation."
@State private var referenceAudioURL: URL?
@State private var referenceTranscript: String = ""
```

**Step 2: Update header** to show "TTS Studio" with engine subtitle:

```swift
private var header: some View {
    HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text-to-Speech Studio")
                .font(.system(size: 32, weight: .bold))
            Text(config.ttsEngine == .kokoro
                ? "Craft narration with FluidAudio's Kokoro voices and export WAV clips"
                : "Generate speech with MLX Qwen3 TTS — voice design & cloning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Button(action: { Task { await refreshStatus(force: true) } }) {
            Label("Check Assets", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(isCheckingKokoro || isLoadingMLXModel)
    }
}
```

**Step 3: Add engine picker card** as first item in ScrollView content (before kokoroStatusCard):

```swift
private var enginePickerCard: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Engine")
            .font(.headline)
        Picker("TTS Engine", selection: $config.ttsEngine) {
            ForEach(TTSEngine.allCases) { engine in
                HStack {
                    Text(engine.displayName)
                    Text("— \(engine.subtitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(engine)
            }
        }
        .pickerStyle(.radioGroup)
    }
    .padding(18)
    .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(NSColor.windowBackgroundColor))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
    )
}
```

**Step 4: Add MLX model status card** (shown when engine is .qwen3TTS):

```swift
@ViewBuilder
private var mlxStatusCard: some View {
    if config.ttsEngine == .qwen3TTS && !mlxModelReady {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MLX TTS model not loaded")
                        .font(.headline)
                    Text("Download the model from the Models page, then it will auto-load here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let error = mlxModelLoadError {
                Label(error, systemImage: "xmark.circle")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
                } label: {
                    Label("Open Models Library", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await loadMLXModel() }
                } label: {
                    Label(isLoadingMLXModel ? "Loading…" : "Retry Load", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingMLXModel)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
```

**Step 5: Add MLX voice controls card** (voice design + voice clone tabs):

```swift
@ViewBuilder
private var mlxVoiceControlsCard: some View {
    if config.ttsEngine == .qwen3TTS {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Settings")
                .font(.headline)

            // Model selector
            HStack {
                Text("Model")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("MLX Model", selection: $selectedMLXModel.id) {
                    ForEach(MLXTTSModelDefinition.availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMLXModel.id) { _, _ in
                    mlxModelReady = false
                    Task { await loadMLXModel() }
                }
            }

            Divider()

            if selectedMLXModel.supportsVoiceDesign {
                voiceDesignSection
            }
            if selectedMLXModel.supportsVoiceClone {
                voiceCloneSection
            }

            // Language picker
            HStack {
                Text("Language")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Language", selection: $config.ttsLanguage) {
                    Text("Auto").tag("auto")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("Français").tag("fr")
                    Text("Español").tag("es")
                }
                .pickerStyle(.menu)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.15))
        )
    }
}

private var voiceDesignSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Label("Voice Design", systemImage: "text.bubble")
            .font(.subheadline.weight(.medium))
        Text("Describe the voice you want to generate")
            .font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $voiceDescriptionText)
            .font(.system(size: 14))
            .frame(minHeight: 60, maxHeight: 100)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private var voiceCloneSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Label("Voice Clone", systemImage: "mic.badge.plus")
            .font(.subheadline.weight(.medium))
        Text("Upload a reference audio clip (3-20s) and its transcript to clone the voice")
            .font(.caption).foregroundStyle(.secondary)

        HStack(spacing: 12) {
            Button {
                pickReferenceAudio()
            } label: {
                Label(
                    referenceAudioURL != nil ? referenceAudioURL!.lastPathComponent : "Select Audio File",
                    systemImage: "waveform"
                )
            }
            .buttonStyle(.bordered)

            if referenceAudioURL != nil {
                Button(role: .destructive) {
                    referenceAudioURL = nil
                    referenceTranscript = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }

        if referenceAudioURL != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reference Transcript")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Enter the exact text spoken in the reference audio…", text: $referenceTranscript)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
```

**Step 6: Add helper methods for MLX model loading and reference audio picking**:

```swift
private func loadMLXModel() async {
    isLoadingMLXModel = true
    mlxModelLoadError = nil
    do {
        try await MLXTTSService.shared.loadModel(definition: selectedMLXModel)
        await MainActor.run {
            mlxModelReady = true
            isLoadingMLXModel = false
        }
    } catch {
        await MainActor.run {
            mlxModelLoadError = error.localizedDescription
            mlxModelReady = false
            isLoadingMLXModel = false
        }
    }
}

private func pickReferenceAudio() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.wav, .mp3, .aiff, .m4a, .audio]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK {
        referenceAudioURL = panel.url
    }
}

private func refreshStatus(force: Bool = false) async {
    await refreshKokoroStatus(force: force)
    if config.ttsEngine == .qwen3TTS {
        let cached = await MLXTTSDownloadManager.shared.isModelCached(repoId: selectedMLXModel.huggingFaceRepo)
        if cached {
            await loadMLXModel()
        }
    }
}
```

**Step 7: Update `generateAudio(shouldExport:)`** to dispatch based on engine:

```swift
private func generateAudio(shouldExport: Bool) {
    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        errorMessage = "Enter some text to synthesize."
        return
    }
    guard !isSynthesizing else { return }

    isSynthesizing = true
    pendingExportAfterSynthesis = shouldExport
    statusMessage = "Synthesizing…"
    errorMessage = nil

    Task {
        do {
            let audio: Data
            if config.ttsEngine == .kokoro {
                guard kokoroReady else {
                    throw TTSError.processingFailed("Install Kokoro models before synthesizing.")
                }
                audio = try await KokoroTTSService.shared.synthesize(
                    text: trimmed,
                    voice: config.ttsVoice,
                    variantPreference: config.ttsVariantPreference,
                    speakingRate: config.ttsSpeakingRate
                )
            } else {
                audio = try await MLXTTSService.shared.synthesize(
                    text: trimmed,
                    modelDefinition: selectedMLXModel,
                    voiceDescription: selectedMLXModel.supportsVoiceDesign ? voiceDescriptionText : nil,
                    referenceAudioURL: selectedMLXModel.supportsVoiceClone ? referenceAudioURL : nil,
                    referenceText: selectedMLXModel.supportsVoiceClone ? referenceTranscript : nil,
                    language: config.ttsLanguage
                )
            }
            await MainActor.run {
                synthesizedAudio = audio
                let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                statusMessage = "Preview updated (\(timestamp))."
                preparePlayback(with: audio)
                isSynthesizing = false
            }
            if shouldExport {
                await MainActor.run {
                    presentSavePanel(with: audio)
                    pendingExportAfterSynthesis = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                statusMessage = nil
                isSynthesizing = false
                pendingExportAfterSynthesis = false
            }
        }
    }
}
```

**Step 8: Update the ScrollView body** to conditionally show engine-specific cards:

```swift
ScrollView {
    VStack(spacing: 24) {
        enginePickerCard

        if config.ttsEngine == .kokoro {
            kokoroStatusCard
        } else {
            mlxStatusCard
        }

        textEditorCard

        if config.ttsEngine == .kokoro {
            voiceControlsCard
        } else {
            mlxVoiceControlsCard
        }

        actionBar

        previewCard
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 30)
}
```

**Step 9: Update actionBar disabled state** to handle both engines:

```swift
Button(action: { generateAudio(shouldExport: false) }) {
    Label("Generate Preview", systemImage: "sparkles")
        .frame(minWidth: 160)
}
.buttonStyle(.borderedProminent)
.disabled(
    (config.ttsEngine == .kokoro && !kokoroReady)
    || (config.ttsEngine == .qwen3TTS && !mlxModelReady)
    || isSynthesizing
)
```

**Step 10: Update .task modifier** to also check MLX model:

```swift
.task {
    await refreshStatus(force: false)
}
.onChange(of: config.ttsEngine) { _, newValue in
    synthesizedAudio = nil
    stopPlayback()
    if newValue == .qwen3TTS {
        Task { await refreshStatus(force: false) }
    }
}
```

**Step 11: Update defaultFilename** to reflect current engine:

```swift
private func defaultFilename() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let prefix = config.ttsEngine == .kokoro ? "Kokoro" : "Qwen3TTS"
    return "\(prefix)-\(formatter.string(from: Date())).wav"
}
```

**Step 12: Build to verify**

Run:
```bash
swift build 2>&1 | tail -20
```
Expected: Build succeeds.

**Step 13: Commit**

```bash
git add Sources/VoiceFlowPro/Views/TTSSynthesisView.swift
git commit -m "feat: unified TTS Studio with engine switcher, voice design & voice cloning UI"
```

---

## Task 8: Integration Testing and Polish

**Files:**
- All modified files

**Step 1: Run full test suite**

```bash
swift test 2>&1 | tail -30
```
Expected: All existing and new tests pass.

**Step 2: Build the full project**

```bash
swift build 2>&1 | tail -20
```
Expected: Build succeeds with no new errors.

**Step 3: Verify no regressions** by checking existing Kokoro flow still compiles:
- `KokoroTTSService.swift` is untouched
- `KokoroDownloadManager.swift` is untouched
- Existing Kokoro voices and settings are preserved

**Step 4: Commit final changes**

```bash
git add -A
git commit -m "feat: complete Qwen3 TTS integration with voice design and cloning support"
```

---

## Summary of Files Changed/Created

| Action | File | Purpose |
|--------|------|---------|
| Modify | `Package.swift` | Add MLXAudioTTS dependency |
| Modify | `Sources/VoiceFlowPro/Models/TextToSpeechModels.swift` | Add `qwen3TTS` engine, `MLXTTSModelDefinition` |
| Create | `Sources/VoiceFlowPro/Services/MLXTTSService.swift` | Actor for MLX TTS synthesis |
| Create | `Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift` | HuggingFace model download/cache |
| Modify | `Sources/VoiceFlowPro/Models/AppConfiguration.swift` | New TTS config properties |
| Modify | `Sources/VoiceFlowPro/Views/ModelsView.swift` | MLX TTS download cards |
| Modify | `Sources/VoiceFlowPro/Views/TTSSynthesisView.swift` | Unified engine switcher, voice design & clone UI |
| Create | `Sources/VoiceFlowProTests/Models/TextToSpeechModelsTests.swift` | Unit tests |
| Create | `Sources/VoiceFlowProTests/Services/MLXTTSServiceTests.swift` | Unit tests |
| Create | `Sources/VoiceFlowProTests/Services/MLXTTSDownloadManagerTests.swift` | Unit tests |

## Key Design Decisions

1. **Voice Design vs Voice Clone**: Two distinct modes handled by different MLX model variants. VoiceDesign uses text description → `voice` parameter. VoiceClone uses reference audio → `refAudio`/`refText` parameters.
2. **Model Loading**: Lazy loading via `MLXTTSService.loadModel()` — models are only loaded into memory when first used, not on app launch.
3. **HuggingFace Caching**: Uses `ModelUtils.resolveOrDownloadModel()` from MLXAudioCore which caches in `~/.cache/mlx-audio/`.
4. **Backward Compatibility**: Kokoro TTS is completely untouched. Engine switcher defaults to Kokoro.
5. **Extensibility**: `MLXTTSModelDefinition.availableModels` array can be extended with new models without code changes elsewhere.
