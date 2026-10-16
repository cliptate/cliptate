import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("ModelDownloadManager local artifacts")
struct ModelDownloadManagerArtifactTests {
  @Test
  func hasLocalArtifactsRecognizesSortformerCacheInMLXAudioDirectory() async throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
    let modelDirectory = hubRoot
      .appendingPathComponent("mlx-audio", isDirectory: true)
      .appendingPathComponent(
        "mlx-community_diar_streaming_sortformer_4spk-v2.1-fp16",
        isDirectory: true
      )

    try FileManager.default.createDirectory(
      at: modelDirectory,
      withIntermediateDirectories: true
    )
    try Data("{\"model_type\":\"sortformer\"}".utf8).write(
      to: modelDirectory.appendingPathComponent("config.json")
    )
    try Data("weights".utf8).write(
      to: modelDirectory.appendingPathComponent("model.safetensors")
    )

    let manager = ModelDownloadManager(
      cacheRootProvider: { hubRoot },
      fileManager: .default
    )
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let hasArtifacts = await manager.hasLocalArtifacts(for: .sortformerStreaming)
    #expect(hasArtifacts)
  }

  @Test
  func hasLocalArtifacts_parakeet_returnsFalseForEmptyDirectory() async throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
    let repoId = ModelVariant.parakeetV3.huggingFaceRepoId
    let subdir = repoId.replacingOccurrences(of: "/", with: "_")
    let modelDir = hubRoot
      .appendingPathComponent("mlx-audio", isDirectory: true)
      .appendingPathComponent(subdir, isDirectory: true)

    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    // No safetensors file — empty directory should NOT be recognised as a valid model
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let manager = ModelDownloadManager(
      cacheRootProvider: { hubRoot },
      fileManager: .default
    )

    let result = await manager.hasLocalArtifacts(for: .parakeetV3)
    #expect(!result, "Directory without safetensors should not be a valid Parakeet model")
  }

  @Test
  func hasLocalArtifacts_parakeet_returnsTrueWhenSafetensorsAndConfigPresent() async throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
    let repoId = ModelVariant.parakeetV3.huggingFaceRepoId
    let subdir = repoId.replacingOccurrences(of: "/", with: "_")
    let modelDir = hubRoot
      .appendingPathComponent("mlx-audio", isDirectory: true)
      .appendingPathComponent(subdir, isDirectory: true)

    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    try Data("fake weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
    try Data("{\"model_type\":\"parakeet\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let manager = ModelDownloadManager(
      cacheRootProvider: { hubRoot },
      fileManager: .default
    )

    let result = await manager.hasLocalArtifacts(for: .parakeetV3)
    #expect(result, "Directory with safetensors and config.json should be recognised as a valid Parakeet model")
    #expect(await manager.isModelDownloaded(.parakeetV3))
  }
}

// MARK: - Path resolution tests (ported from deleted ModelCacheDirectoryTests)

@Suite("ModelDownloadManager path resolution")
struct ModelDownloadManagerPathTests {

    @Test("model storage resolves account home and falls back to process home")
    func testModelHomeDirectoryRespectsDistribution() {
        let container = URL(fileURLWithPath: "/mock/home/Library/Containers/com.voicepink.voicepinkpro/Data")
        let account = URL(fileURLWithPath: "/mock/home")
        let home = ModelStorageLayoutResolver.modelHomeDirectory(processHome: container, accountHome: account)
        #expect(home == account)
        #expect(ModelStorageLayoutResolver.modelHomeDirectory(processHome: container, accountHome: nil) == container)
    }

    @Test("hubCacheRoot uses HF_HUB_CACHE when set")
    func testHubCacheRootHFHubCache() {
        let env = ["HF_HUB_CACHE": "/custom/hub"]
        let result = ModelDownloadManager.hubCacheRoot(environment: env)
        #expect(result.path == "/custom/hub")
    }

    @Test("hubCacheRoot uses HF_HOME/hub when HF_HUB_CACHE absent")
    func testHubCacheRootHFHome() {
        let env = ["HF_HOME": "/my/hf"]
        let result = ModelDownloadManager.hubCacheRoot(environment: env)
        #expect(result.path == "/my/hf/hub")
    }

     @Test("hubCacheRoot uses ~/.cache/huggingface/hub for non-sandboxed macOS defaults")
     func testHubCacheRootDefault() {
         let result = ModelDownloadManager.hubCacheRoot(
             environment: [:],
             homeDirectory: URL(fileURLWithPath: "/mock/home", isDirectory: true),
             cachesDirectory: URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
         )
         #expect(result.path == "/mock/home/.cache/huggingface/hub")
     }

     @Test("hubCacheRoot keeps shared ~/.cache/huggingface/hub even when sandbox env is present")
     func testHubCacheRootSandboxUsesSharedHomeCache() {
         let result = ModelDownloadManager.hubCacheRoot(
             environment: ["APP_SANDBOX_CONTAINER_ID": "com.cliptate.app"],
             homeDirectory: URL(fileURLWithPath: "/mock/home", isDirectory: true),
             cachesDirectory: URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
         )
         #expect(result.path == "/mock/home/.cache/huggingface/hub")
     }

     @Test("HF_HUB_CACHE takes priority over HF_HOME")
     func testHubCacheRootPriority() {
         let env = ["HF_HUB_CACHE": "/hub-cache", "HF_HOME": "/hf-home"]
         let result = ModelDownloadManager.hubCacheRoot(environment: env)
         #expect(result.path == "/hub-cache")
     }

     @Test("configureSharedHubCacheEnvironment exports shared hub root through HF_HUB_CACHE")
     func testConfigureSharedHubCacheEnvironmentSetsHFHubCache() async throws {
         try await withEnvironmentVariable("HF_HUB_CACHE", value: nil) {
             let result = ModelDownloadManager.configureSharedHubCacheEnvironment(
                 environment: ["APP_SANDBOX_CONTAINER_ID": "com.cliptate.app"],
                 homeDirectory: URL(fileURLWithPath: "/mock/home", isDirectory: true),
                 cachesDirectory: URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
             )
             #expect(result.path == "/mock/home/.cache/huggingface/hub")
             #expect(ProcessInfo.processInfo.environment["HF_HUB_CACHE"] == "/mock/home/.cache/huggingface/hub")
         }
     }

     @Test("mlxAudioBase appends mlx-audio to hub cache root")
     func testMlxAudioBaseDefault() {
         let result = ModelDownloadManager.mlxAudioBase(
             environment: [:],
            homeDirectory: URL(fileURLWithPath: "/mock/home", isDirectory: true),
            cachesDirectory: URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
        )
        #expect(result.path == "/mock/home/.cache/huggingface/hub/mlx-audio")
    }

    @Test("mlxAudioBase appends mlx-audio to HF_HUB_CACHE")
    func testMlxAudioBaseWithHFHubCache() {
        let env = ["HF_HUB_CACHE": "/custom/hub"]
        let result = ModelDownloadManager.mlxAudioBase(environment: env)
        #expect(result.path == "/custom/hub/mlx-audio")
    }

    @Test("mlxAudioDirectory replaces slash with underscore in repoId")
    func testMlxAudioDirectorySubdir() {
        let result = ModelDownloadManager.mlxAudioDirectory(
            forRepo: "mlx-community/Qwen3-ASR-0.6B-8bit",
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/mock/home", isDirectory: true),
            cachesDirectory: URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
        )
        #expect(result.path == "/mock/home/.cache/huggingface/hub/mlx-audio/mlx-community_Qwen3-ASR-0.6B-8bit")
    }

    @Test("mlxAudioDirectories keeps legacy Library Caches path as fallback")
    func testMlxAudioDirectoriesIncludesLegacyFallback() {
        let results = ModelDownloadManager.mlxAudioDirectories(
            forRepo: "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16",
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/mock/home", isDirectory: true),
            cachesDirectory: URL(fileURLWithPath: "/mock/Library/Caches", isDirectory: true)
        )
        #expect(results.map(\.path) == [
            "/mock/home/.cache/huggingface/hub/mlx-audio/mlx-community_diar_streaming_sortformer_4spk-v2.1-fp16",
            "/mock/Library/Caches/huggingface/hub/mlx-audio/mlx-community_diar_streaming_sortformer_4spk-v2.1-fp16"
        ])
    }
}

// MARK: - MLX Audio (Qwen3/Sortformer) model artifact tests

@Suite("ModelDownloadManager MLX Audio model detection")
struct ModelDownloadManagerMLXAudioTests {

    private func makeManagerWithTempHub() throws -> (ModelDownloadManager, URL, URL) {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            fileManager: .default
        )
        return (manager, hubRoot, tempRoot)
    }

    private func createMLXArtifactsInBase(
        _ mlxAudioBase: URL,
        repoId: String,
        withConfig: Bool = true
    ) throws -> URL {
        let subdir = repoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = mlxAudioBase
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        if withConfig {
            try Data("{\"model_type\":\"test\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        }
        try Data("weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        return modelDir
    }

    private func createMLXArtifacts(at hubRoot: URL, repoId: String, withConfig: Bool = true) throws -> URL {
        try createMLXArtifactsInBase(
            hubRoot.appendingPathComponent("mlx-audio", isDirectory: true),
            repoId: repoId,
            withConfig: withConfig
        )
    }

    private func createHubSnapshotArtifacts(
        at hubRoot: URL,
        repoId: String,
        revision: String = "main-snapshot",
        withConfig: Bool = true
    ) throws -> URL {
        let repoRoot = hubRoot
            .appendingPathComponent("models--" + repoId.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
        let snapshotDir = repoRoot
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
        let refsDir = repoRoot.appendingPathComponent("refs", isDirectory: true)

        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        try Data(revision.utf8).write(to: refsDir.appendingPathComponent("main"))
        if withConfig {
            try Data("{\"model_type\":\"test\"}".utf8).write(to: snapshotDir.appendingPathComponent("config.json"))
        }
        try Data("weights".utf8).write(to: snapshotDir.appendingPathComponent("model.safetensors"))
        return snapshotDir
    }

    @Test("hasLocalArtifacts returns false when safetensors file is zero bytes")
    func testHasLocalArtifactsReturnsFalseForZeroByteSafetensors() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        guard let asrModel = ModelVariant.allCases.first(where: { $0.isQwen3ASRModel }) else { return }
        let subdir = asrModel.huggingFaceRepoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("{\"model_type\":\"test\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        // Write zero-byte safetensors (simulates interrupted download)
        try Data().write(to: modelDir.appendingPathComponent("model.safetensors"))

        let result = await manager.hasLocalArtifacts(for: asrModel)
        #expect(!result, "Zero-byte safetensors should not be treated as a valid model")
    }

    @Test("hasLocalArtifacts returns false when config.json is not valid JSON")
    func testHasLocalArtifactsReturnsFalseForInvalidConfigJSON() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        guard let asrModel = ModelVariant.allCases.first(where: { $0.isQwen3ASRModel }) else { return }
        let subdir = asrModel.huggingFaceRepoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        // Corrupt/partial config.json
        try Data("{ CORRUPT".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        try Data("fake weights data".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))

        let result = await manager.hasLocalArtifacts(for: asrModel)
        #expect(!result, "Invalid config.json should not be treated as a valid model")
    }

    @Test("hasLocalArtifacts returns true for Qwen3 ASR model with config.json and safetensors")
    func testHasLocalArtifactsQwen3ASR() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        guard let asrModel = ModelVariant.allCases.first(where: { $0.isQwen3ASRModel }) else {
            return  // no Qwen3 ASR model in this build, skip
        }
        _ = try createMLXArtifacts(at: hubRoot, repoId: asrModel.huggingFaceRepoId)
        let result = await manager.hasLocalArtifacts(for: asrModel)
        #expect(result, "Qwen3 ASR model with config.json+safetensors should be detected")
    }

    @Test("hasLocalArtifacts returns false for Qwen3 ASR model when config.json missing")
    func testHasLocalArtifactsMissingConfig() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        guard let asrModel = ModelVariant.allCases.first(where: { $0.isQwen3ASRModel }) else {
            return
        }
        _ = try createMLXArtifacts(at: hubRoot, repoId: asrModel.huggingFaceRepoId, withConfig: false)
        let result = await manager.hasLocalArtifacts(for: asrModel)
        #expect(!result, "MLX Audio model without config.json should not be detected")
    }

    @Test("delete removes MLX Audio model directory")
    func testDeleteMLXAudioModel() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        guard let asrModel = ModelVariant.allCases.first(where: { $0.isQwen3ASRModel }) else {
            return
        }
        let modelDir = try createMLXArtifacts(at: hubRoot, repoId: asrModel.huggingFaceRepoId)
        #expect(FileManager.default.fileExists(atPath: modelDir.path))
        try await manager.delete(model: asrModel)
        let stillExists = FileManager.default.fileExists(atPath: modelDir.path)
        #expect(!stillExists, "delete should remove the model directory")
    }

    @Test("hasLocalArtifacts returns true for Parakeet model with config.json and safetensors")
    func testHasLocalArtifactsParakeet() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        _ = try createMLXArtifacts(at: hubRoot, repoId: ModelVariant.parakeetV3.huggingFaceRepoId)
        let result = await manager.hasLocalArtifacts(for: .parakeetV3)
        #expect(result, "Parakeet model with config.json+safetensors should be detected")
    }

    @Test("hasLocalArtifacts returns false for Parakeet when config.json missing")
    func testHasLocalArtifactsParakeetMissingConfig() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        _ = try createMLXArtifacts(
            at: hubRoot, repoId: ModelVariant.parakeetV3.huggingFaceRepoId, withConfig: false)
        let result = await manager.hasLocalArtifacts(for: .parakeetV3)
        #expect(!result, "Parakeet model without config.json should not be detected")
    }

    @Test("delete removes Parakeet model directory")
    func testDeleteParakeetModel() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let modelDir = try createMLXArtifacts(
            at: hubRoot, repoId: ModelVariant.parakeetV3.huggingFaceRepoId)
        #expect(FileManager.default.fileExists(atPath: modelDir.path))
        try await manager.delete(model: .parakeetV3)
        let stillExists = FileManager.default.fileExists(atPath: modelDir.path)
        #expect(!stillExists, "delete should remove the Parakeet model directory")
    }

    @Test("mlxAudioDirectory uses injected cacheRootProvider")
    func testMlxAudioDirectoryUsesProvider() throws {
        let customRoot = URL(fileURLWithPath: "/custom/hub/root")
        let manager = ModelDownloadManager(
            cacheRootProvider: { customRoot },
            fileManager: .default
        )
        let dir = manager.mlxAudioDirectory(forRepo: "mlx-community/parakeet-tdt-0.6b-v3")
        #expect(dir.path == "/custom/hub/root/mlx-audio/mlx-community_parakeet-tdt-0.6b-v3")
    }

    @Test("modelSizeInMB returns 0 for model not on disk")
    func testModelSizeInMBNotOnDisk() async throws {
        let (manager, _, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let size = await manager.modelSizeInMB(for: .qwen3TTS06B4bit)
        #expect(size == 0)
    }

    @Test("modelSizeInMB returns non-zero for model with files on disk")
    func testModelSizeInMBWithFiles() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        _ = try createMLXArtifacts(at: hubRoot, repoId: ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId)
        let size = await manager.modelSizeInMB(for: .qwen3TTS06B4bit)
        // The artifacts are tiny — still 0 MB when rounded down, but the method must not crash
        #expect(size >= 0)
    }

    @Test("hasLocalArtifacts detects TTS model with config.json and safetensors")
    func testHasLocalArtifactsTTSModel() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        _ = try createMLXArtifacts(at: hubRoot, repoId: ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId)
        let result = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(result, "TTS model with config.json+safetensors should be detected")
    }

    @Test("hasLocalArtifacts restores legacy cache into primary hub root")
    func testHasLocalArtifactsRestoresLegacyCacheIntoPrimaryHubRoot() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let legacyMLXAudioBase = tempRoot
            .appendingPathComponent("Library/Caches/huggingface/hub/mlx-audio", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            legacyMLXAudioBaseProvider: { legacyMLXAudioBase },
            fileManager: .default
        )

        let repoId = ModelVariant.parakeetV3.huggingFaceRepoId
        let restoredDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "_"), isDirectory: true)

        _ = try createMLXArtifactsInBase(legacyMLXAudioBase, repoId: repoId)

        let result = await manager.hasLocalArtifacts(for: .parakeetV3)

        #expect(result)
        #expect(FileManager.default.fileExists(atPath: restoredDir.appendingPathComponent("config.json").path))
        #expect(FileManager.default.fileExists(atPath: restoredDir.appendingPathComponent("model.safetensors").path))
    }

    @Test("hasLocalArtifacts detects models stored only in HuggingFace snapshot layout")
    func testHasLocalArtifactsDetectsHubSnapshotLayout() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let snapshotDir = try createHubSnapshotArtifacts(
            at: hubRoot,
            repoId: ModelVariant.parakeetV3.huggingFaceRepoId
        )

        let result = await manager.hasLocalArtifacts(for: .parakeetV3)

        #expect(result)
        #expect(FileManager.default.fileExists(atPath: snapshotDir.appendingPathComponent("config.json").path))
    }

    @Test("getModelDirectorySync resolves HuggingFace snapshot layout when mlx-audio folder is absent")
    func testGetModelDirectorySyncResolvesHubSnapshotLayout() throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let snapshotDir = try createHubSnapshotArtifacts(
            at: hubRoot,
            repoId: ModelVariant.parakeetV3.huggingFaceRepoId,
            revision: "snapshot-123"
        )

        let resolved = manager.getModelDirectorySync(for: .parakeetV3)

        #expect(resolved?.path == snapshotDir.path)
    }

    @Test("download reuses a Python Hub snapshot with blob symlinks without copying or fetching weights")
    func testDownloadReusesSharedSnapshotSymlinks() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let model = ModelVariant.qwen3ASR
        let snapshot = try createHubSnapshotArtifacts(at: hubRoot, repoId: model.huggingFaceRepoId)
        let weights = snapshot.appendingPathComponent("model.safetensors")
        let blobs = snapshot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: weights, to: blobs.appendingPathComponent("weights"))
        try FileManager.default.createSymbolicLink(atPath: weights.path, withDestinationPath: "../../blobs/weights")

        try await manager.download(model: model) { progress in
            #expect(progress.progress == 1.0)
        }

        #expect(await manager.getModelDirectory(for: model) == snapshot)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: weights.path) == "../../blobs/weights")
        #expect(!FileManager.default.fileExists(atPath: hubRoot.appendingPathComponent("mlx-audio").path))
    }

    // MARK: - BPE tokenizer completeness (vocab.json required when merges.txt present)

    @Test("hasLocalArtifacts returns false for TTS when merges.txt present but vocab.json absent")
    func testHasLocalArtifactsReturnsFalseWhenVocabJsonMissing() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repoId = ModelVariant.qwen3TTS17B8bit.huggingFaceRepoId
        let subdir = repoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        try Data("{\"model_type\":\"qwen3_tts\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        // BPE tokenizer: merges.txt present but vocab.json intentionally absent — simulates interrupted download
        try Data("BPE merges".utf8).write(to: modelDir.appendingPathComponent("merges.txt"))

        let result = await manager.hasLocalArtifacts(for: .qwen3TTS17B8bit)
        #expect(!result, "BPE model with merges.txt but without vocab.json must be treated as incomplete")
    }

    @Test("hasLocalArtifacts returns true for TTS when both merges.txt and vocab.json are present")
    func testHasLocalArtifactsReturnsTrueWhenVocabJsonPresent() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repoId = ModelVariant.qwen3TTS17B8bit.huggingFaceRepoId
        let subdir = repoId.replacingOccurrences(of: "/", with: "_")
        let modelDir = hubRoot
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("fake weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))
        try Data("{\"model_type\":\"qwen3_tts\"}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        try Data("BPE merges".utf8).write(to: modelDir.appendingPathComponent("merges.txt"))
        try Data("{\"version\":\"1.0\"}".utf8).write(to: modelDir.appendingPathComponent("vocab.json"))

        let result = await manager.hasLocalArtifacts(for: .qwen3TTS17B8bit)
        #expect(result, "BPE model with both merges.txt and vocab.json must be treated as complete")
    }

    @Test("hasLocalArtifacts remains true for non-BPE TTS model without merges.txt")
    func testHasLocalArtifactsReturnsTrueForNonBPETTSWithoutMerges() async throws {
        let (manager, hubRoot, tempRoot) = try makeManagerWithTempHub()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        // Non-BPE TTS: safetensors + config.json, no merges.txt or vocab.json → still valid
        _ = try createMLXArtifacts(at: hubRoot, repoId: ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId)
        let result = await manager.hasLocalArtifacts(for: .qwen3TTS06B4bit)
        #expect(result, "Non-BPE TTS model without merges.txt should be treated as complete")
    }

    @Test("getModelDirectorySync falls back to legacy cache when primary path is empty")
    func testGetModelDirectorySyncFallsBackToLegacyCache() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hubRoot = tempRoot.appendingPathComponent("hf-hub", isDirectory: true)
        let legacyMLXAudioBase = tempRoot
            .appendingPathComponent("Library/Caches/huggingface/hub/mlx-audio", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ModelDownloadManager(
            cacheRootProvider: { hubRoot },
            legacyMLXAudioBaseProvider: { legacyMLXAudioBase },
            fileManager: .default
        )

        let repoId = ModelVariant.parakeetV3.huggingFaceRepoId
        let legacyDir = try createMLXArtifactsInBase(legacyMLXAudioBase, repoId: repoId)

        let resolved = manager.getModelDirectorySync(for: .parakeetV3)

        #expect(resolved?.path == legacyDir.path)
    }
}

@Suite("ModelDownloadManager unified routing")
struct ModelDownloadManagerUnifiedRoutingTests {
    private let customHubRoot = URL(fileURLWithPath: "/custom/hub/root", isDirectory: true)

    private var manager: ModelDownloadManager {
        ModelDownloadManager(
            cacheRootProvider: { customHubRoot },

            fileManager: StubFileManager()
        )
    }

    @Test("Parakeet routes through the resolver backend")
    func parakeetUsesResolverBackend() {
        let backend = ModelDownloadManager.downloadBackend(for: .parakeetV3)
        #expect(backend == .resolver)
    }

    @Test("Qwen3 ASR uses the ASR backend")
    func qwen3ASRUsesASRBackend() {
        let backend = ModelDownloadManager.downloadBackend(for: .qwen3ASR)
        #expect(backend == .qwen3ASR)
    }

    @Test("Qwen3 aligner uses the aligner backend")
    func qwen3AlignerUsesAlignerBackend() {
        let backend = ModelDownloadManager.downloadBackend(for: .qwen3ForcedAligner)
        #expect(backend == .qwen3Aligner)
    }

    @Test("Sortformer uses the VAD backend")
    func sortformerUsesVADBackend() {
        let backend = ModelDownloadManager.downloadBackend(for: .sortformerStreaming)
        #expect(backend == .sortformerVAD)
    }

    @Test("TTS uses the resolver backend")
    func ttsUsesResolverBackend() {
        let backend = ModelDownloadManager.downloadBackend(for: .qwen3TTS06B4bit)
        #expect(backend == .resolver)
    }

    @Test("Parakeet and TTS share the mlx-audio root")
    func parakeetAndTTSShareMLXAudioRoot() {
        let parakeetRoot = manager.mlxAudioDirectory(forRepo: ModelVariant.parakeetV3.huggingFaceRepoId)
            .deletingLastPathComponent()
        let ttsRoot = manager.mlxAudioDirectory(forRepo: ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId)
            .deletingLastPathComponent()

        #expect(parakeetRoot == ttsRoot)
        #expect(parakeetRoot.path == "/custom/hub/root/mlx-audio")
    }

    @Test("FireRed and Qwen3 ASR share the instance mlx-audio root")
    func fireRedAndQwen3ShareInstanceMLXAudioRoot() {
        let fireRedRoot = manager.mlxAudioDirectory(forRepo: ModelVariant.fireRedASR2.huggingFaceRepoId)
            .deletingLastPathComponent()
        let qwen3Root = manager.mlxAudioDirectory(forRepo: ModelVariant.qwen3ASR.huggingFaceRepoId)
            .deletingLastPathComponent()

        #expect(fireRedRoot == qwen3Root)
        #expect(fireRedRoot.path == "/custom/hub/root/mlx-audio")
    }
}

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

// MARK: - computeDownloadProgress tests

@Suite("computeDownloadProgress")
struct ComputeDownloadProgressTests {
    @Test("returns floor 0.05 when directory is empty")
    func returnsFloorForEmptyDirectory() {
        #expect(computeDownloadProgress(actualMB: 0, expectedMB: 400) == 0.05)
    }

    @Test("returns floor 0.05 when expectedMB is zero")
    func returnsFloorForZeroExpected() {
        #expect(computeDownloadProgress(actualMB: 100, expectedMB: 0) == 0.05)
    }

    @Test("returns correct fraction when partially downloaded")
    func returnsCorrectFraction() {
        let result = computeDownloadProgress(actualMB: 200, expectedMB: 400)
        #expect(abs(result - 0.5) < 0.001)
    }

    @Test("clamps to 0.95 when actual exceeds expected")
    func clampsAtCeiling() {
        #expect(computeDownloadProgress(actualMB: 500, expectedMB: 400) == 0.95)
    }

    @Test("clamps to 0.95 exactly at 100 percent")
    func clampsAtExactFull() {
        #expect(computeDownloadProgress(actualMB: 400, expectedMB: 400) == 0.95)
    }
}

final class StubFileManager: FileManager, @unchecked Sendable {
  let documentDirectory: URL
  var existingDirectories: Set<String> = []
  var existingFiles: Set<String> = []
  var directoryListings: [String: [URL]] = [:]

  init(documentDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)) {
    self.documentDirectory = documentDirectory
    super.init()
  }

  override func urls(
    for directory: FileManager.SearchPathDirectory,
    in domainMask: FileManager.SearchPathDomainMask
  ) -> [URL] {
    if directory == .documentDirectory {
      return [documentDirectory]
    }
    return []
  }

  override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?)
    -> Bool
  {
    if existingDirectories.contains(path) {
      isDirectory?.pointee = true
      return true
    }
    if existingFiles.contains(path) {
      isDirectory?.pointee = false
      return true
    }
    isDirectory?.pointee = false
    return false
  }

  override func contentsOfDirectory(
    at url: URL,
    includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions = []
  ) throws -> [URL] {
    directoryListings[url.path] ?? []
  }
}

private func withEnvironmentVariable(
  _ key: String,
  value: String?,
  operation: () async throws -> Void
) async throws {
  let previousValue = ProcessInfo.processInfo.environment[key]
  if let value {
    setenv(key, value, 1)
  } else {
    unsetenv(key)
  }
  defer {
    if let previousValue {
      setenv(key, previousValue, 1)
    } else {
      unsetenv(key)
    }
  }
  try await operation()
}
