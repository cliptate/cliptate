import Foundation
import HuggingFace
import MLXAudioSTT
import MLXAudioVAD
@preconcurrency import MLXAudioCore
import os.log

private func defaultLegacyMLXAudioBase() -> URL? {
  ModelDownloadManager.legacyMLXAudioBase(cachesDirectory: URL.cachesDirectory)
}

enum ModelDownloadError: LocalizedError, Equatable {
  case permissionDenied(reason: ModelDownloadPermission.PermissionDenialReason)

  var errorDescription: String? {
    switch self {
    case .permissionDenied(let reason):
      return reason.message
    }
  }
}

/// Manages Parakeet and MLX Audio model downloads, status, and deletion.
actor ModelDownloadManager {
  static let shared = ModelDownloadManager()

  /// Returns the HuggingFace hub cache root used by the underlying mlx-audio library.
  /// Injected for testability; defaults to the same singleton used by `ModelUtils.resolveOrDownloadModel`.
  nonisolated let cacheRootProvider: @Sendable () -> URL
  nonisolated let legacyMLXAudioBaseProvider: @Sendable () -> URL?

  private let accessController: any ModelAccessControlling
  private let fileManager: FileManager
  private let logger = Logger(subsystem: "com.cliptate.app", category: "ModelDownloadManager")
  private var activeDownloads: [ModelVariant: Task<Void, Error>] = [:]

  init(
    cacheRootProvider: @escaping @Sendable () -> URL = {
      ModelDownloadManager.hubCacheRoot(environment: ProcessInfo.processInfo.environment)
    },
    legacyMLXAudioBaseProvider: @escaping @Sendable () -> URL? = { defaultLegacyMLXAudioBase() },
    accessController: any ModelAccessControlling = ModelAccessController.shared,
    fileManager: FileManager = .default
  ) {
    self.cacheRootProvider = cacheRootProvider
    self.legacyMLXAudioBaseProvider = legacyMLXAudioBaseProvider
    self.accessController = accessController
    self.fileManager = fileManager
  }

  /// Base directory for all mlx-audio model caches (`<hub_root>/mlx-audio`).
  nonisolated func mlxAudioBase() -> URL {
    ModelStorageLayoutResolver.mlxAudioBase(hubRoot: cacheRootProvider())
  }

  /// Canonical cache directory for a specific model repo (`<hub_root>/mlx-audio/<org>_<name>`).
  nonisolated func mlxAudioDirectory(forRepo repoId: String) -> URL {
    ModelStorageLayoutResolver.mlxAudioDirectories(
      forRepo: repoId,
      hubRoot: cacheRootProvider(),
      legacyMLXAudioBase: legacyMLXAudioBaseProvider()
    ).first!
  }

  nonisolated func mlxAudioDirectories(forRepo repoId: String) -> [URL] {
    ModelStorageLayoutResolver.mlxAudioDirectories(
      forRepo: repoId,
      hubRoot: cacheRootProvider(),
      legacyMLXAudioBase: legacyMLXAudioBaseProvider()
    )
  }

  nonisolated func huggingFaceRepositoryDirectories(forRepo repoId: String) -> [URL] {
    ModelStorageLayoutResolver.huggingFaceRepositoryDirectories(
      forRepo: repoId,
      hubRoot: cacheRootProvider(),
      legacyMLXAudioBase: legacyMLXAudioBaseProvider()
    )
  }

  // MARK: - Public API

  func isModelDownloaded(_ model: ModelVariant) async -> Bool {
    if model.requiresProSubscription {
      do {
        let permission: ModelDownloadPermission = try await accessController.checkPermission(for: model)
        guard permission.isAllowed else { return false }
      } catch {
        return false
      }
    }
    return hasLocalModel(for: model)
  }

  func getStatuses(for models: [ModelVariant]) async -> [ModelVariant: Bool] {
    var statuses: [ModelVariant: Bool] = [:]
    for model in models {
      statuses[model] = await isModelDownloaded(model)
    }
    return statuses
  }

  func hasLocalArtifacts(for model: ModelVariant) -> Bool {
    hasLocalModel(for: model)
  }

  func getModelDirectory(for model: ModelVariant) -> URL? {
    if let dir = accessibleModelDirectory(for: model) {
      return dir
    }
    return storageDirectory(for: model)
  }

  /// Synchronous model-directory lookup; safe to call from non-async contexts.
  nonisolated func getModelDirectorySync(for model: ModelVariant) -> URL? {
    let candidates = artifactDirectories(for: model)
    if let valid = candidates.first(where: { Self.hasValidArtifacts(at: $0, fileManager: .default) }) {
      return valid
    }
    let storageCandidates = storageDirectories(for: model)
    return storageCandidates.first(where: { FileManager.default.directoryExists(at: $0) })
  }

  func download(
    model: ModelVariant,
    progressHandler: @escaping @Sendable (ModelDownloadProgress) async -> Void
  ) async throws {
    if let existing = activeDownloads[model] {
      try await existing.value
      return
    }

    try await ensureDownloadPermitted(for: model)

    let task = Task {
      switch Self.downloadBackend(for: model) {
      case .resolver, .qwen3ASR, .qwen3Aligner, .fireRedASR, .cohereASR, .sortformerVAD, .sileroVAD:
        try await self.downloadMLXAudioModel(model, progressHandler: progressHandler)
      case .unsupported:
        await progressHandler(ModelDownloadProgress(currentStep: "Unsupported model type", progress: 0.0))
        return
      }
    }

    activeDownloads[model] = task
    defer { activeDownloads[model] = nil }

    try await task.value
  }

  func cancelDownload(for model: ModelVariant) {
    guard let task = activeDownloads[model] else { return }
    task.cancel()
  }

  func delete(model: ModelVariant) throws {
    for dir in storageDirectories(for: model) {
      if fileManager.directoryExists(at: dir) {
        try fileManager.removeItem(at: dir)
      }
    }
    ModelArtifactStatusNotifier.postChange(for: model)
  }

  nonisolated static func downloadBackend(for model: ModelVariant) -> ModelDownloadBackend {
    model.downloadBackend
  }

  // MARK: - MLX Audio (ASR / Aligner / VAD)

  private func downloadMLXAudioModel(
    _ model: ModelVariant,
    progressHandler: @escaping @Sendable (ModelDownloadProgress) async -> Void
  ) async throws {
    try Task.checkCancellation()
    guard !hasLocalModel(for: model) else {
      await progressHandler(ModelDownloadProgress(currentStep: "Model already downloaded", progress: 1.0))
      return
    }

    let maxRetries = 3
    var lastError: Error?

    for attempt in 1...maxRetries {
      try Task.checkCancellation()
      var downloadTask: Task<Void, Error>?
      var progressTask: Task<Void, Never>?

      do {
        await progressHandler(
          ModelDownloadProgress(
            currentStep: "Downloading \(model.displayName)...",
            progress: 0.05,
            attemptNumber: attempt,
            maxAttempts: maxRetries
          )
        )

        let paths = storagePaths(for: model)
        let modelDir = paths.primaryHuggingFaceRepositoryDirectory
          ?? paths.primaryMLXAudioDirectory
          ?? mlxAudioDirectory(forRepo: model.huggingFaceRepoId)
        let expectedMB = model.fileSize

        let activeDownloadTask: Task<Void, Error> = Task {
          try Task.checkCancellation()
          switch Self.downloadBackend(for: model) {
          case .qwen3Aligner:
            _ = try await Qwen3ForcedAlignerModel.fromPretrained(model.huggingFaceRepoId)
          case .fireRedASR:
            _ = try await FireRedASR2Model.fromPretrained(model.huggingFaceRepoId)
          case .cohereASR:
            _ = try await CohereTranscribeModel.fromPretrained(model.huggingFaceRepoId)
          case .sortformerVAD:
            _ = try await SortformerModel.fromPretrained(model.huggingFaceRepoId)
          case .sileroVAD:
            _ = try await SileroVAD.fromPretrained(model.huggingFaceRepoId)
          case .resolver:
            guard model.isParakeetModel || model.isTTSModel else {
              throw Self.unsupportedModelError()
            }
            // Clear any incomplete flat mlx-audio cache left by prior interrupted downloads.
            // (The flat cache was used by the old ModelUtils.resolveOrDownloadModel path; new
            // downloads go to the standard HuggingFace snapshot layout instead.)
            self.clearIncompleteTTSCacheIfNeeded(for: model)
            // Download every file in the repository without extension filtering.
            // Passing an empty `matching` array causes HubClient to fetch all files,
            // including tokenizer artefacts such as vocab.json that a filtered download
            // may miss when a previous attempt was interrupted.
            let repoID = Repo.ID(rawValue: model.huggingFaceRepoId)!
            _ = try await HubClient().downloadSnapshot(
              of: repoID,
              kind: .model,
              revision: "main",
              matching: []
            )
          case .qwen3ASR:
            _ = try await Qwen3ASRModel.fromPretrained(model.huggingFaceRepoId)
          case .unsupported:
            throw Self.unsupportedModelError()
          }
        }
        downloadTask = activeDownloadTask

        progressTask = makeFileSizeProgressTask(
          at: modelDir,
          expectedMB: expectedMB,
          displayName: model.displayName,
          attempt: attempt,
          maxAttempts: maxRetries,
          downloadTask: activeDownloadTask,
          progressHandler: progressHandler
        )

        try await withTaskCancellationHandler {
          try await activeDownloadTask.value
        } onCancel: {
          activeDownloadTask.cancel()
        }
        progressTask?.cancel()
        downloadTask = nil

        await progressHandler(
          ModelDownloadProgress(
            currentStep: "MLX Audio model ready",
            progress: 1.0,
            attemptNumber: attempt,
            maxAttempts: maxRetries
          )
        )
        ModelArtifactStatusNotifier.postChange(for: model)
        return

      } catch is CancellationError {
        progressTask?.cancel()
        downloadTask?.cancel()
        throw CancellationError()
      } catch {
        progressTask?.cancel()
        downloadTask?.cancel()
        lastError = error
        await progressHandler(
          ModelDownloadProgress(
            currentStep: "Download failed: \(error.localizedDescription)",
            progress: 0.0,
            attemptNumber: attempt,
            maxAttempts: maxRetries
          )
        )
        if attempt < maxRetries {
          let delay = TimeInterval(attempt * 4)
          await progressHandler(
            ModelDownloadProgress(
              currentStep: "Retrying in \(Int(delay))s...",
              progress: 0.0,
              estimatedTimeRemaining: delay,
              attemptNumber: attempt,
              maxAttempts: maxRetries
            )
          )
          do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          } catch is CancellationError {
            throw CancellationError()
          }
        }
      }
    }

    throw NSError(
      domain: "ModelDownloadManager",
      code: -10,
      userInfo: [
        NSLocalizedDescriptionKey: "Failed to download \(model.displayName)",
        NSLocalizedFailureReasonErrorKey: lastError?.localizedDescription ?? "Unknown error",
      ]
    )
  }

  // MARK: - Helpers

  /// Returns the on-disk size of a downloaded model directory in MB (rounded down).
  /// Returns 0 if the model is not downloaded or the directory cannot be read.
  func modelSizeInMB(for model: ModelVariant) -> Int {
    guard let dir = storageDirectory(for: model) ?? accessibleModelDirectory(for: model) else { return 0 }
    let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
      at: dir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]
    ) else { return 0 }
    var totalBytes: Int64 = 0
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
            values.isRegularFile == true,
            let size = values.fileSize else { continue }
      totalBytes += Int64(size)
    }
    return Int(totalBytes / (1024 * 1024))
  }

  private func hasLocalModel(for model: ModelVariant) -> Bool {
    accessibleModelDirectory(for: model) != nil
  }

  private func storageDirectory(for model: ModelVariant) -> URL? {
    storageDirectories(for: model).first(where: {
      fileManager.directoryExists(at: $0)
    })
  }

  private func accessibleModelDirectory(for model: ModelVariant) -> URL? {
    let paths = storagePaths(for: model)
    let snapshotCandidates = huggingFaceSnapshotDirectories(for: model)
    if let snapshot = snapshotCandidates.first(where: { Self.hasValidArtifacts(at: $0, fileManager: fileManager) }) {
      return snapshot
    }

    let cacheCandidates = paths.mlxAudioDirectories
    guard let primary = cacheCandidates.first else { return nil }
    if Self.hasValidArtifacts(at: primary, fileManager: fileManager) {
      return primary
    }

    guard let legacy = cacheCandidates.dropFirst().first(where: { Self.hasValidArtifacts(at: $0, fileManager: fileManager) }) else {
      return nil
    }

    restoreLegacyArtifactsIfNeeded(from: legacy, to: primary)
    if Self.hasValidArtifacts(at: primary, fileManager: fileManager) {
      return primary
    }
    return legacy
  }

  nonisolated private func storagePaths(for model: ModelVariant) -> ModelStoragePaths {
    model.storagePaths(
      hubRoot: cacheRootProvider(),
      legacyMLXAudioBase: legacyMLXAudioBaseProvider()
    )
  }

  nonisolated private func artifactDirectories(for model: ModelVariant) -> [URL] {
    let snapshotDirs = huggingFaceSnapshotDirectories(for: model)
    let cacheDirs = storagePaths(for: model).mlxAudioDirectories
    return ModelStorageLayoutResolver.deduplicatedURLs(snapshotDirs + cacheDirs)
  }

  nonisolated private func storageDirectories(for model: ModelVariant) -> [URL] {
    storagePaths(for: model).storageDirectories
  }

  nonisolated private func huggingFaceSnapshotDirectories(for model: ModelVariant) -> [URL] {
    let fileManager = FileManager.default
    var result: [URL] = []

    for repoDir in storagePaths(for: model).huggingFaceRepositoryDirectories {
      let snapshotsRoot = repoDir.appendingPathComponent("snapshots", isDirectory: true)
      guard let snapshotEntries = try? fileManager.contentsOfDirectory(
        at: snapshotsRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else { continue }

      let refsMain = repoDir.appendingPathComponent("refs/main")
      if let revision = try? String(contentsOf: refsMain, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
        !revision.isEmpty
      {
        let preferred = snapshotsRoot.appendingPathComponent(revision, isDirectory: true)
        if fileManager.directoryExists(at: preferred) {
          result.append(preferred)
        }
      }

      let remaining = snapshotEntries.filter { entry in
        guard fileManager.directoryExists(at: entry) else { return false }
        return !result.contains { $0.standardizedFileURL == entry.standardizedFileURL }
      }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      result.append(contentsOf: remaining)
    }

    return ModelStorageLayoutResolver.deduplicatedURLs(result)
  }

  private func restoreLegacyArtifactsIfNeeded(from legacy: URL, to primary: URL) {
    guard legacy.standardizedFileURL != primary.standardizedFileURL else { return }

    if fileManager.directoryExists(at: primary) && !Self.hasValidArtifacts(at: primary, fileManager: fileManager) {
      do {
        try fileManager.removeItem(at: primary)
      } catch {
        logger.error("Failed to remove invalid primary model cache at \(primary.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return
      }
    }

    guard !fileManager.directoryExists(at: primary) else { return }

    do {
      try fileManager.createDirectory(
        at: primary.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try fileManager.copyItem(at: legacy, to: primary)
    } catch {
      logger.error("Failed to restore legacy model cache from \(legacy.path, privacy: .public) to \(primary.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  private func ensureDownloadPermitted(for model: ModelVariant) async throws {
    guard model.requiresProSubscription else { return }
    let permission = try await accessController.checkPermission(for: model)
    guard permission.isAllowed else {
      let reason = permission.reason ?? .requiresProSubscription
      throw ModelDownloadError.permissionDenied(reason: reason)
    }
  }

  /// Removes an incomplete flat mlx-audio cache directory when it contains a BPE
  /// tokenizer file (`merges.txt`) but is missing the accompanying `vocab.json`.
  /// This situation arises when a previous filtered download was interrupted after
  /// `merges.txt` was written but before `vocab.json` arrived.  The flat cache
  /// directory (used by the old `ModelUtils.resolveOrDownloadModel` path) is also
  /// deleted so the new `HubClient.downloadSnapshot` call performs a fresh fetch.
  private func clearIncompleteTTSCacheIfNeeded(for model: ModelVariant) {
    let paths = storagePaths(for: model)
    guard let flatDir = paths.primaryMLXAudioDirectory else { return }
    let mergesPath = flatDir.appendingPathComponent("merges.txt")
    let vocabPath = flatDir.appendingPathComponent("vocab.json")
    guard fileManager.fileExists(atPath: mergesPath.path),
          !fileManager.fileExists(atPath: vocabPath.path) else { return }

    logger.warning(
      "Incomplete model flat cache detected for \(model.huggingFaceRepoId, privacy: .public): merges.txt present but vocab.json missing. Clearing for full re-download."
    )
    try? fileManager.removeItem(at: flatDir)
    for hfDir in paths.huggingFaceRepositoryDirectories {
      if fileManager.fileExists(atPath: hfDir.path) {
        try? fileManager.removeItem(at: hfDir)
      }
    }
  }

  nonisolated private static func unsupportedModelError() -> NSError {
    NSError(
      domain: "ModelDownloadManager",
      code: -11,
      userInfo: [NSLocalizedDescriptionKey: "Unsupported model type"]
    )
  }

  /// Polls the download directory size every 0.5 s and reports file-size-based progress.
  /// Progress is clamped to [0.05, 0.95] until the download task completes.
  private func makeFileSizeProgressTask(
    at dir: URL,
    expectedMB: Int,
    displayName: String,
    attempt: Int,
    maxAttempts: Int,
    downloadTask: Task<Void, Error>,
    progressHandler: @escaping @Sendable (ModelDownloadProgress) async -> Void
  ) -> Task<Void, Never> {
    Task<Void, Never> {
      while !downloadTask.isCancelled && !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: 500_000_000) } catch { break }
        guard !Task.isCancelled, !downloadTask.isCancelled else { break }
        let actualMB = directoryTotalMB(at: dir)
        let progress = computeDownloadProgress(actualMB: actualMB, expectedMB: expectedMB)
        await progressHandler(
          ModelDownloadProgress(
            currentStep: "Downloading \(displayName)... (\(Int(progress * 100))%)",
            progress: progress,
            attemptNumber: attempt,
            maxAttempts: maxAttempts
          )
        )
      }
    }
  }

  private func directoryTotalMB(at url: URL) -> Int {
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
    ) else { return 0 }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true,
            let size = values.fileSize else { continue }
      total += Int64(size)
    }
    return Int(total / (1024 * 1024))
  }

  private static func hasValidArtifacts(at dir: URL, fileManager: FileManager) -> Bool {
    guard fileManager.directoryExists(at: dir) else { return false }
    let configPath = dir.appendingPathComponent("config.json")
    guard fileManager.fileExists(atPath: configPath.path),
          let configData = try? Data(contentsOf: configPath),
          !configData.isEmpty,
          (try? JSONSerialization.jsonObject(with: configData)) != nil else { return false }
    let files = try? fileManager.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.fileSizeKey]
    )
    let hasSafetensors = files?.contains { file in
      guard file.pathExtension == "safetensors" else { return false }
      let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      return size > 0
    } ?? false
    guard hasSafetensors else { return false }

    // BPE tokenizer models ship both merges.txt and vocab.json.  If only merges.txt
    // is present the download was interrupted before vocab.json arrived, which causes
    // tokenizer construction to fail at load time.
    let mergesPath = dir.appendingPathComponent("merges.txt")
    if fileManager.fileExists(atPath: mergesPath.path) {
      let vocabPath = dir.appendingPathComponent("vocab.json")
      guard fileManager.fileExists(atPath: vocabPath.path) else { return false }
    }

    return true
  }

}

// MARK: - Progress computation (internal for testability)

/// Computes download progress from actual vs expected size, clamped to [0.05, 0.95].
/// A floor of 0.05 indicates the download has started; 1.0 is only reported on completion.
func computeDownloadProgress(actualMB: Int, expectedMB: Int) -> Float {
  guard expectedMB > 0 else { return 0.05 }
  let raw = Float(actualMB) / Float(expectedMB)
  return max(0.05, min(raw, 0.95))
}

// MARK: - Path resolution (mlx-audio cache layout)

extension ModelDownloadManager {

  /// Resolves the HuggingFace hub cache root, respecting env-var overrides.
  ///
  /// Priority: `HF_HUB_CACHE` → `HF_HOME/hub` → `~/.cache/huggingface/hub`
  static func hubCacheRoot(environment env: [String: String]) -> URL {
    ModelStorageLayoutResolver.hubCacheRoot(environment: env)
  }

  static func hubCacheRoot(
    environment env: [String: String],
    homeDirectory: URL,
    cachesDirectory: URL
  ) -> URL {
    ModelStorageLayoutResolver.hubCacheRoot(
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    )
  }

  @discardableResult
  static func configureSharedHubCacheEnvironment(
    environment env: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
    cachesDirectory: URL = URL.cachesDirectory
  ) -> URL {
    let hubRoot = hubCacheRoot(
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    )
    setenv("HF_HUB_CACHE", hubRoot.path, 1)
    return hubRoot
  }

  /// Root directory for all mlx-audio model downloads.
  static func mlxAudioBase(environment env: [String: String]) -> URL {
    ModelStorageLayoutResolver.mlxAudioBase(environment: env)
  }

  static func mlxAudioBase(
    environment env: [String: String],
    homeDirectory: URL,
    cachesDirectory: URL
  ) -> URL {
    ModelStorageLayoutResolver.mlxAudioBase(
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    )
  }

  /// Returns the primary cache directory for a specific mlx-audio model repo.
  static func mlxAudioDirectory(forRepo repoId: String) -> URL {
    mlxAudioDirectory(forRepo: repoId, environment: ProcessInfo.processInfo.environment)
  }

  static func mlxAudioDirectory(
    forRepo repoId: String,
    environment env: [String: String],
    homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
    cachesDirectory: URL = URL.cachesDirectory
  ) -> URL {
    mlxAudioDirectories(
      forRepo: repoId,
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    ).first!
  }

  /// Returns candidate cache directories (primary + optional legacy fallback).
  static func mlxAudioDirectories(
    forRepo repoId: String,
    environment env: [String: String],
    homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
    cachesDirectory: URL = URL.cachesDirectory
  ) -> [URL] {
    let hubRoot = ModelStorageLayoutResolver.hubCacheRoot(
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    )
    let legacy = ModelStorageLayoutResolver.legacyMLXAudioBase(cachesDirectory: cachesDirectory)
    return ModelStorageLayoutResolver.mlxAudioDirectories(
      forRepo: repoId,
      hubRoot: hubRoot,
      legacyMLXAudioBase: legacy
    )
  }

  fileprivate static func legacyHubCacheRoot(cachesDirectory: URL) -> URL {
    ModelStorageLayoutResolver.legacyHubCacheRoot(cachesDirectory: cachesDirectory)
  }

  fileprivate static func legacyMLXAudioBase(cachesDirectory: URL) -> URL {
    ModelStorageLayoutResolver.legacyMLXAudioBase(cachesDirectory: cachesDirectory)
  }
}

extension FileManager {
  fileprivate func directoryExists(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
  }
}
