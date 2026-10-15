import CliptateCore
import Foundation
import MLX
import os.log

enum ModelLifecycleState: Equatable, Sendable {
  case notLoaded
  case loading
  case loaded
  case error(String)
}

enum ModelLifecycleKind: String, Sendable {
  case asr
  case align
  case tts
  case vad
}

struct ModelLifecycleKey: Hashable, Sendable {
  let kind: ModelLifecycleKind
  let identifier: String

  var id: String { "\(kind.rawValue):\(identifier)" }
}

struct ModelLifecycleStatus: Identifiable, Sendable {
  let key: ModelLifecycleKey
  let displayName: String
  let state: ModelLifecycleState
  let memoryUsageMB: Int
  let lastAccess: Date?
  let errorMessage: String?

  var id: String { key.id }
}

struct ModelCacheSnapshot: Sendable {
  let statuses: [ModelLifecycleStatus]
  let totalMemoryUsageMB: Int
  let generatedAt: Date

  static let empty = ModelCacheSnapshot(statuses: [], totalMemoryUsageMB: 0, generatedAt: .distantPast)
}

struct ModelCachePerformanceSnapshot: Sendable {
  let averageLoadDurationByModelID: [String: TimeInterval]
  let sampleCountByModelID: [String: Int]
}

struct ASRModelLease: Sendable {
  fileprivate let key: ModelLifecycleKey
  fileprivate let id: UUID
}

enum ModelLanguageContext: Sendable {
  case asr(type: TranscriberType, model: ModelVariant)
  case align(model: ModelVariant)
  case tts(engine: TTSEngine, modelID: String?)
}

protocol ModelLanguageSupportQuerying: Sendable {
  func supportedLanguages(forASR type: TranscriberType, model: ModelVariant) async -> [Language]
  func supportedLanguages(forAlign model: ModelVariant) async -> [Language]
  func supportedLanguages(forTTS engine: TTSEngine, modelID: String?) async -> [Language]
  func filteredLanguages(for context: ModelLanguageContext) async -> [Language]
  func invalidateLanguageSupportCache() async
}

enum ModelCacheError: LocalizedError, Equatable {
  case invalidAlignModel(ModelVariant)
  case ttsAssetsMissing(String)
  case unsupportedTTSModel(String)
  case typeMismatch(expected: String)

  var errorDescription: String? {
    switch self {
    case .invalidAlignModel(let model):
      return "\(model.displayName) is not a valid align model."
    case .ttsAssetsMissing(let details):
      return details
    case .unsupportedTTSModel(let modelID):
      return "Unsupported TTS model: \(modelID)"
    case .typeMismatch(let expected):
      return "Cached model type mismatch. Expected \(expected)."
    }
  }
}

actor ModelCacheManager: ModelLanguageSupportQuerying {
  nonisolated static let shared: ModelCacheManager = {
    let manager = ModelCacheManager()
    Task { await manager.startCleanupLoopIfNeeded() }
    return manager
  }()

  private enum CachedResource {
    case asr(Transcriber)
    case align(Qwen3ForcedAlignerTranscriber)
    case tts(TTSResource)
    case vad(SortformerVADSegmenter)
    case sileroVAD(SileroVADSegmenter)
  }

  private struct TTSResource: Sendable, Equatable {
    let engine: TTSEngine
    let modelID: String
    let usesMLXRuntime: Bool
  }

  private struct ModelCacheEntry {
    var state: ModelLifecycleState
    var lastAccess: Date
    var memoryUsageMB: Int
    var displayName: String
    var activeASRLeaseIDs: Set<UUID>
    var resource: CachedResource?
    var loadingTask: Task<CachedResourceBox, Error>?
    var errorMessage: String?
  }

  private final class CachedResourceBox: @unchecked Sendable {
    let value: CachedResource

    init(_ value: CachedResource) {
      self.value = value
    }
  }

  private var entries: [ModelLifecycleKey: ModelCacheEntry] = [:]
  private var loadDurationHistory: [ModelLifecycleKey: [TimeInterval]] = [:]
  private var cleanupTask: Task<Void, Never>?
  private var cleanupTimeout: TimeInterval = 600  // 10 minutes
  private var asrCleanupTimeout: TimeInterval = 600
  private var languageSupportCache: [String: [Language]] = [:]
  private let logger = Logger(subsystem: "com.Cliptate", category: "ModelCacheManager")

  private init() {}

  // MARK: - Public model loading

  /// Updates the idle-eviction timeout used for non-ASR cached models.
  func updateCleanupTimeout(seconds: TimeInterval) {
    cleanupTimeout = max(60, seconds)
  }

  func updateASRIdleTimeout(seconds: TimeInterval) {
    asrCleanupTimeout = max(60, seconds)
  }

  func getCleanupTimeout() -> TimeInterval {
    cleanupTimeout
  }

  func acquireASRTranscriber(
    type: TranscriberType,
    model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> (Transcriber, ASRModelLease) {
    let key = asrKey(type: type, model: model)
    let transcriber = try await getASRTranscriber(type: type, model: model, progress: progress)
    let lease = registerASRLease(for: key)
    return (transcriber, lease)
  }

  func releaseASRLease(_ lease: ASRModelLease) {
    guard var entry = entries[lease.key] else { return }
    guard entry.activeASRLeaseIDs.remove(lease.id) != nil else { return }
    entry.lastAccess = Date()
    entries[lease.key] = entry
  }

  /// Preloads the requested ASR model and stores it in the shared cache.
  func preloadASRModel(type: TranscriberType, model: ModelVariant) async throws {
    _ = try await getASRTranscriber(type: type, model: model, progress: { _ in })
  }

  /// Returns a ready ASR transcriber for the requested engine/model pair.
  /// Concurrent requests reuse a single in-flight warm-up task.
  /// Any previously loaded ASR model with a different key is evicted first.
  func getASRTranscriber(
    type: TranscriberType,
    model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Transcriber {
    let key = asrKey(type: type, model: model)
    await evictStaleEntries(ofKind: .asr, keepingKey: key)
    let resource = try await loadResource(
      key: key,
      displayName: "\(type.displayName) • \(model.displayName)",
      estimatedMemoryMB: model.fileSize
    ) { [weak self] in
      guard let self else { throw CancellationError() }
      try await self.validateModelReadiness(for: model)
      let transcriber = type.createTranscriber(model: model)
      try await transcriber.warmUpModelWithProgress { step in
        progress(step)
      }
      return .asr(transcriber)
    }

    guard case .asr(let transcriber) = resource else {
      throw ModelCacheError.typeMismatch(expected: "ASR transcriber")
    }
    return transcriber
  }

  /// Preloads a forced-aligner model so alignment operations can reuse it.
  func preloadAlignModel(
    model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
  ) async throws {
    _ = try await getAlignTranscriber(model: model, progress: progress)
  }

  /// Returns a ready forced-aligner transcriber from cache or warm-up.
  func getAlignTranscriber(
    model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Qwen3ForcedAlignerTranscriber {
    guard model.isQwen3AlignerModel else {
      throw ModelCacheError.invalidAlignModel(model)
    }

    let key = alignKey(model: model)
    await evictStaleEntries(ofKind: .align, keepingKey: key)
    let resource = try await loadResource(
      key: key,
      displayName: "Align • \(model.displayName)",
      estimatedMemoryMB: model.fileSize
    ) { [weak self] in
      guard let self else { throw CancellationError() }
      try await self.validateModelReadiness(for: model)
      let aligner = Qwen3ForcedAlignerTranscriber(model: model)
      try await aligner.warmUpModelWithProgress { step in
        progress(step)
      }
      return .align(aligner)
    }

    guard case .align(let aligner) = resource else {
      throw ModelCacheError.typeMismatch(expected: "Align transcriber")
    }
    return aligner
  }

  /// Preloads the MLX TTS runtime for faster first synthesis.
  func preloadTTSModel(
    engine: TTSEngine,
    modelID: String
  ) async throws {
    let _ = try await ensureTTSModel(
      engine: engine,
      modelID: modelID
    )
  }

  @discardableResult
  /// Ensures a TTS runtime is loaded and returns the active model identifier.
  func ensureTTSModel(
    engine: TTSEngine,
    modelID: String
  ) async throws -> String {
    let key = ttsKey(engine: engine, modelID: modelID)
    let initialMemory = await estimateTTSMemory(engine: engine, modelID: modelID)
    let resource = try await loadResource(
      key: key,
      displayName: "TTS • \(modelID)",
      estimatedMemoryMB: initialMemory
    ) {
      switch engine {
      case .qwen3TTS:
        guard
          let definition = MLXTTSModelDefinition.availableModels.first(where: {
            $0.huggingFaceRepo == modelID
          })
        else {
          throw ModelCacheError.unsupportedTTSModel(modelID)
        }
        let isCached = await ModelDownloadManager.shared.hasLocalArtifacts(for: definition.modelVariant)
        guard isCached else {
          throw ModelCacheError.ttsAssetsMissing(
            "\(definition.displayName) is not downloaded. Download it from the Models page."
          )
        }
        try await MLXTTSService.shared.loadModel(definition: definition)
        return .tts(TTSResource(engine: engine, modelID: modelID, usesMLXRuntime: true))
      }
    }

    guard case .tts(let ttsResource) = resource else {
      throw ModelCacheError.typeMismatch(expected: "TTS model")
    }

    if let memoryUsage = await refreshedTTSMemoryIfNeeded(resource: ttsResource),
      var updated = entries[key]
    {
      updated.memoryUsageMB = max(0, memoryUsage)
      updated.lastAccess = Date()
      entries[key] = updated
    }

    return ttsResource.modelID
  }

  func releaseTTSModel(engine: TTSEngine, modelID: String) async {
    let key = ttsKey(engine: engine, modelID: modelID)
    guard let entry = entries[key] else { return }
    entry.loadingTask?.cancel()
    if let resource = entry.resource {
      await teardown(resource: resource)
    }
    entries.removeValue(forKey: key)
  }

  // MARK: - VAD model loading

  /// Returns a ready VAD segmenter from cache or loads one.
  /// Uses the same caching pattern as ASR: one active VAD model at a time.
  func getVADSegmenter(
    model: ModelVariant = .sortformerOffline
  ) async throws -> SortformerVADSegmenter {
    let key = vadKey(model: model)
    await evictStaleEntries(ofKind: .vad, keepingKey: key)
    let resource = try await loadResource(
      key: key,
      displayName: "VAD • \(model.displayName)",
      estimatedMemoryMB: model.fileSize
    ) {
      let segmenter = try await SortformerVADSegmenter.makeWithModel(variant: model)
      return .vad(segmenter)
    }

    guard case .vad(let segmenter) = resource else {
      throw ModelCacheError.typeMismatch(expected: "VAD segmenter")
    }
    return segmenter
  }

  /// Returns a ready Silero VAD segmenter from cache or loads one.
  func getSileroVADSegmenter(
    model: ModelVariant = .sileroVAD
  ) async throws -> SileroVADSegmenter {
    let key = vadKey(model: model)
    await evictStaleEntries(ofKind: .vad, keepingKey: key)
    let resource = try await loadResource(
      key: key,
      displayName: "VAD • \(model.displayName)",
      estimatedMemoryMB: model.fileSize
    ) {
      let segmenter = try await SileroVADSegmenter.makeWithModel(variant: model)
      return .sileroVAD(segmenter)
    }

    guard case .sileroVAD(let segmenter) = resource else {
      throw ModelCacheError.typeMismatch(expected: "Silero VAD segmenter")
    }
    return segmenter
  }

  /// Preloads the VAD model so subsequent calls are cache hits.
  func preloadVADModel(model: ModelVariant = .sortformerOffline) async throws {
    if model.isSileroVADModel {
      _ = try await getSileroVADSegmenter(model: model)
    } else {
      _ = try await getVADSegmenter(model: model)
    }
  }

  /// Returns `true` when a VAD model is fully loaded and cache-ready.
  func hasReadyVADModel(model: ModelVariant = .sortformerOffline) -> Bool {
    let key = vadKey(model: model)
    guard let entry = entries[key] else { return false }
    guard case .loaded = entry.state else { return false }
    switch entry.resource {
    case .vad, .sileroVAD:
      return true
    default:
      return false
    }
  }

  // MARK: - Model state and cache statistics

  /// Returns `true` when an ASR transcriber is fully loaded and cache-ready.
  func hasReadyTranscriber(type: TranscriberType, model: ModelVariant) -> Bool {
    let key = asrKey(type: type, model: model)
    guard let entry = entries[key] else { return false }
    guard case .loaded = entry.state else { return false }
    if case .asr = entry.resource {
      return true
    }
    return false
  }

  func hasReadyAlignTranscriber(model: ModelVariant) -> Bool {
    let key = alignKey(model: model)
    guard let entry = entries[key] else { return false }
    guard case .loaded = entry.state else { return false }
    if case .align = entry.resource {
      return true
    }
    return false
  }

  /// Returns `true` when an ASR model is currently warming/loading.
  func isModelLoading(type: TranscriberType, model: ModelVariant) -> Bool {
    let key = asrKey(type: type, model: model)
    if let entry = entries[key], case .loading = entry.state {
      return true
    }
    return false
  }

  func modelState(for key: ModelLifecycleKey) -> ModelLifecycleState {
    entries[key]?.state ?? .notLoaded
  }

  func noteAccess(type: TranscriberType, model: ModelVariant) {
    let key = asrKey(type: type, model: model)
    updateLastAccess(for: key)
  }

  func noteAccess(alignModel model: ModelVariant) {
    let key = alignKey(model: model)
    updateLastAccess(for: key)
  }

  func noteAccess(ttsEngine engine: TTSEngine, modelID: String) {
    let key = ttsKey(engine: engine, modelID: modelID)
    updateLastAccess(for: key)
  }

  /// Returns a point-in-time snapshot for UI/state observation.
  func snapshot() -> ModelCacheSnapshot {
    let statuses = entries.map { key, entry in
      ModelLifecycleStatus(
        key: key,
        displayName: entry.displayName,
        state: entry.state,
        memoryUsageMB: entry.memoryUsageMB,
        lastAccess: {
          switch entry.state {
          case .loaded, .loading:
            return entry.lastAccess
          case .notLoaded, .error:
            return nil
          }
        }(),
        errorMessage: entry.errorMessage
      )
    }
    .sorted { $0.id < $1.id }

    let totalMemoryUsageMB = statuses.reduce(0) { partialResult, status in
      switch status.state {
      case .loaded:
        return partialResult + status.memoryUsageMB
      case .notLoaded, .loading, .error:
        return partialResult
      }
    }

    return ModelCacheSnapshot(
      statuses: statuses,
      totalMemoryUsageMB: totalMemoryUsageMB,
      generatedAt: Date()
    )
  }

  /// Returns aggregated load-duration metrics collected for cached model warm-ups.
  func performanceSnapshot() -> ModelCachePerformanceSnapshot {
    var averages: [String: TimeInterval] = [:]
    var sampleCounts: [String: Int] = [:]

    for (key, durations) in loadDurationHistory where !durations.isEmpty {
      let total = durations.reduce(0, +)
      averages[key.id] = total / Double(durations.count)
      sampleCounts[key.id] = durations.count
    }

    return ModelCachePerformanceSnapshot(
      averageLoadDurationByModelID: averages,
      sampleCountByModelID: sampleCounts
    )
  }

  /// Evicts all cache entries of the given kind whose key differs from `keepingKey`.
  /// The entry for `keepingKey` (if already loaded) is preserved so a hot-cache hit
  /// on the same model skips both eviction and re-loading.
  private func evictStaleEntries(ofKind kind: ModelLifecycleKind, keepingKey key: ModelLifecycleKey) async {
    for entryKey in entries.keys where entryKey.kind == kind && entryKey != key {
      guard let entry = entries[entryKey] else { continue }
      if kind == .asr && !entry.activeASRLeaseIDs.isEmpty {
        continue
      }
      entry.loadingTask?.cancel()
      if let resource = entry.resource {
        await teardown(resource: resource)
      }
      entries.removeValue(forKey: entryKey)
      logger.debug("Evicted stale \(kind.rawValue, privacy: .public) model: \(entryKey.identifier, privacy: .public)")
    }
  }

  /// Clears cached models while optionally preserving the currently active ASR model.
  func clearCache(keepASR type: TranscriberType?, model: ModelVariant?) async {
    let keepKey: ModelLifecycleKey? = {
      guard let type, let model else { return nil }
      return asrKey(type: type, model: model)
    }()

    let keys = entries.keys
    for key in keys {
      if key.kind == .asr, key == keepKey {
        continue
      }
      guard let entry = entries[key] else { continue }
      if key.kind == .asr, !entry.activeASRLeaseIDs.isEmpty {
        continue
      }
      if let loadingTask = entry.loadingTask {
        loadingTask.cancel()
      }
      if let resource = entry.resource {
        await teardown(resource: resource)
      }
      entries.removeValue(forKey: key)
    }
  }

  /// Evicts ALL cached models unconditionally, including those with active leases.
  /// Intended for lightweight mode entry where maximum memory savings is required.
  func evictAll() async {
    let keys = Array(entries.keys)
    for key in keys {
      guard let entry = entries[key] else { continue }
      entry.loadingTask?.cancel()
      if let resource = entry.resource {
        await teardown(resource: resource)
      }
      entries.removeValue(forKey: key)
    }
    logger.info("Evicted all \(keys.count, privacy: .public) cached model(s) for lightweight mode")
  }

  // MARK: - Language support

  func supportedLanguages(forASR type: TranscriberType, model: ModelVariant) async -> [Language] {
    await cachedLanguages(for: "asr:\(type.rawValue):\(model.rawValue)") {
      model.supportedLanguages
    }
  }

  func supportedLanguages(forAlign model: ModelVariant) async -> [Language] {
    await cachedLanguages(for: "align:\(model.rawValue)") {
      model.supportedLanguages
    }
  }

  func supportedLanguages(forTTS engine: TTSEngine, modelID: String?) async -> [Language] {
    let key = "tts:\(engine.rawValue):\(modelID ?? "default")"
    return await cachedLanguages(for: key) {
      switch engine {
      case .qwen3TTS:
        return [.chinese, .english, .japanese, .korean]
      }
    }
  }

  func filteredLanguages(for context: ModelLanguageContext) async -> [Language] {
    let languages: [Language]
    switch context {
    case .asr(let type, let model):
      languages = await supportedLanguages(forASR: type, model: model)
    case .align(let model):
      languages = await supportedLanguages(forAlign: model)
    case .tts(let engine, let modelID):
      languages = await supportedLanguages(forTTS: engine, modelID: modelID)
    }

    if languages.isEmpty {
      logger.warning("Missing language metadata; falling back to all languages.")
      return Language.allCases
    }
    return languages
  }

  func invalidateLanguageSupportCache() async {
    languageSupportCache.removeAll()
  }

  // MARK: - Internal generic loading

  private func loadResource(
    key: ModelLifecycleKey,
    displayName: String,
    estimatedMemoryMB: Int,
    operation: @escaping @Sendable () async throws -> CachedResource
  ) async throws -> CachedResource {
    let startTime = Date()

    if var existing = entries[key], let ready = existing.resource {
      existing.lastAccess = Date()
      existing.state = .loaded
      existing.errorMessage = nil
      entries[key] = existing
      return ready
    }

    if var existing = entries[key], let loadingTask = existing.loadingTask {
      existing.lastAccess = Date()
      existing.state = .loading
      entries[key] = existing
      do {
        let loadingValue = try await loadingTask.value.value
        return loadingValue
      } catch {
        existing.state = .error(error.localizedDescription)
        existing.errorMessage = error.localizedDescription
        existing.loadingTask = nil
        entries[key] = existing
        throw error
      }
    }

    let loadingTask = Task<CachedResourceBox, Error> {
      let resource = try await operation()
      return CachedResourceBox(resource)
    }

    entries[key] = ModelCacheEntry(
      state: .loading,
      lastAccess: Date(),
      memoryUsageMB: max(estimatedMemoryMB, 0),
      displayName: displayName,
      activeASRLeaseIDs: [],
      resource: nil,
      loadingTask: loadingTask,
      errorMessage: nil
    )

    do {
      let loaded = try await loadingTask.value.value
      if var finished = entries[key] {
        finished.resource = loaded
        finished.loadingTask = nil
        finished.state = .loaded
        finished.lastAccess = Date()
        finished.errorMessage = nil
        entries[key] = finished
      }
      let elapsed = Date().timeIntervalSince(startTime)
      recordLoadDuration(elapsed, for: key)
      logger.debug("Loaded \(displayName, privacy: .public) in \(elapsed, privacy: .public)s")
      return loaded
    } catch {
      if var failed = entries[key] {
        failed.loadingTask = nil
        failed.resource = nil
        failed.state = .error(error.localizedDescription)
        failed.errorMessage = error.localizedDescription
        entries[key] = failed
      } else {
        entries[key] = ModelCacheEntry(
          state: .error(error.localizedDescription),
          lastAccess: Date(),
          memoryUsageMB: 0,
          displayName: displayName,
          activeASRLeaseIDs: [],
          resource: nil,
          loadingTask: nil,
          errorMessage: error.localizedDescription
        )
      }
      let elapsed = Date().timeIntervalSince(startTime)
      logger.error(
        "Failed loading \(displayName, privacy: .public) after \(elapsed, privacy: .public)s: \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  // MARK: - Cleanup loop

  private func startCleanupLoopIfNeeded() {
    guard cleanupTask == nil else { return }
    cleanupTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        await self.purgeExpiredEntries()
      }
    }
  }

  private func purgeExpiredEntries() async {
    let now = Date()
    let keys = entries.keys
    var removed: [ModelLifecycleKey] = []

    for key in keys {
      guard var entry = entries[key] else { continue }
      if entry.loadingTask != nil {
        continue
      }
      if key.kind == .asr && !entry.activeASRLeaseIDs.isEmpty {
        continue
      }
      let timeout: TimeInterval = switch key.kind {
      case .asr, .vad:
        asrCleanupTimeout
      case .align, .tts:
        cleanupTimeout
      }
      let idle = now.timeIntervalSince(entry.lastAccess)
      if idle > timeout {
        if let resource = entry.resource {
          await teardown(resource: resource)
        }
        entry.resource = nil
        entries[key] = nil
        removed.append(key)
      }
    }

    if !removed.isEmpty {
      logger.debug("Purged \(removed.count) idle model(s) from cache")
    }
  }

  private func teardown(resource: CachedResource) async {
    let shouldClearMLXCache: Bool
    switch resource {
    case .asr(let transcriber):
      if let transcriber = transcriber as? MLXWhisperTranscriber {
        transcriber.unload()
        shouldClearMLXCache = true
      } else if let transcriber = transcriber as? MLXParakeetTranscriber {
        transcriber.unload()
        shouldClearMLXCache = true
      } else if let transcriber = transcriber as? Qwen3ASRTranscriber {
        transcriber.unload()
        shouldClearMLXCache = true
      } else if let transcriber = transcriber as? NemotronASRTranscriber {
        transcriber.unload()
        shouldClearMLXCache = true
      } else if let transcriber = transcriber as? CohereTranscribeASRTranscriber {
        transcriber.unload()
        shouldClearMLXCache = true
      } else {
        shouldClearMLXCache = false
      }
    case .align(let aligner):
      aligner.unload()
      shouldClearMLXCache = true
    case .tts(let handle):
      switch handle.engine {
      case .qwen3TTS:
        if handle.usesMLXRuntime {
          await MLXTTSService.shared.reset()
        }
      }
      shouldClearMLXCache = handle.usesMLXRuntime
    case .vad:
      // VAD model (Sortformer) uses MLX runtime
      shouldClearMLXCache = true
    case .sileroVAD:
      // Silero VAD also uses MLX runtime
      shouldClearMLXCache = true
    }
    if shouldClearMLXCache {
      // Flush MLX GPU buffer pool so memory is returned to the system.
      MLX.Memory.clearCache()
    }
  }

  // MARK: - Readiness checks and helpers

  private func validateModelReadiness(for model: ModelVariant) async throws {
    if model.requiresProSubscription {
      let permission = try await ModelAccessController.shared.checkPermission(for: model)
      guard permission.isAllowed else {
        let reason = permission.reason ?? .requiresProSubscription
        throw ModelDownloadError.permissionDenied(reason: reason)
      }
    }

    let hasArtifacts = await ModelDownloadManager.shared.hasLocalArtifacts(for: model)
    guard hasArtifacts else {
      throw ModelPreparationError.modelNotDownloaded(model)
    }
  }

  private func updateLastAccess(for key: ModelLifecycleKey) {
    guard var entry = entries[key] else { return }
    entry.lastAccess = Date()
    entries[key] = entry
  }

  private func registerASRLease(for key: ModelLifecycleKey) -> ASRModelLease {
    let lease = ASRModelLease(key: key, id: UUID())
    guard var entry = entries[key] else {
      preconditionFailure("Attempted to lease missing ASR cache entry: \(key.id)")
    }
    entry.activeASRLeaseIDs.insert(lease.id)
    entry.lastAccess = Date()
    entries[key] = entry
    return lease
  }

  private func recordLoadDuration(_ duration: TimeInterval, for key: ModelLifecycleKey) {
    var samples = loadDurationHistory[key] ?? []
    samples.append(duration)
    if samples.count > 30 {
      samples.removeFirst(samples.count - 30)
    }
    loadDurationHistory[key] = samples
  }

  private func estimateTTSMemory(engine: TTSEngine, modelID: String) async -> Int {
    switch engine {
    case .qwen3TTS:
      guard let def = MLXTTSModelDefinition.availableModels.first(where: { $0.huggingFaceRepo == modelID }) else { return 0 }
      return await ModelDownloadManager.shared.modelSizeInMB(for: def.modelVariant)
    }
  }

  private func refreshedTTSMemoryIfNeeded(resource: TTSResource) async -> Int? {
    switch resource.engine {
    case .qwen3TTS:
      guard let def = MLXTTSModelDefinition.availableModels.first(where: { $0.huggingFaceRepo == resource.modelID }) else { return nil }
      return await ModelDownloadManager.shared.modelSizeInMB(for: def.modelVariant)
    }
  }

  private func cachedLanguages(
    for key: String,
    loader: () -> [Language]
  ) async -> [Language] {
    if let cached = languageSupportCache[key] {
      return cached
    }
    let loaded = loader()
    languageSupportCache[key] = loaded
    return loaded
  }

  private func asrKey(type: TranscriberType, model: ModelVariant) -> ModelLifecycleKey {
    ModelLifecycleKey(kind: .asr, identifier: "\(type.rawValue):\(model.rawValue)")
  }

  private func alignKey(model: ModelVariant) -> ModelLifecycleKey {
    ModelLifecycleKey(kind: .align, identifier: model.rawValue)
  }

  private func ttsKey(engine: TTSEngine, modelID: String) -> ModelLifecycleKey {
    ModelLifecycleKey(kind: .tts, identifier: "\(engine.rawValue):\(modelID)")
  }

  private func vadKey(model: ModelVariant) -> ModelLifecycleKey {
    ModelLifecycleKey(kind: .vad, identifier: model.rawValue)
  }

  /// Evicts non-essential models (TTS, align) while preserving ASR and VAD caches.
  /// Used by lightweight mode to save memory while keeping the core transcription
  /// pipeline warm.
  func evictNonEssentialModels() async {
    let keys = Array(entries.keys)
    var evictedCount = 0
    for key in keys {
      guard key.kind == .tts || key.kind == .align else { continue }
      guard let entry = entries[key] else { continue }
      entry.loadingTask?.cancel()
      if let resource = entry.resource {
        await teardown(resource: resource)
      }
      entries.removeValue(forKey: key)
      evictedCount += 1
    }
    if evictedCount > 0 {
      logger.info("Evicted \(evictedCount, privacy: .public) non-essential model(s) for lightweight mode")
    }
  }
}

#if DEBUG
extension ModelCacheManager {
  private final class MockTranscriber: @unchecked Sendable, Transcriber {
    func warmUpModelWithProgress(progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void)
      async throws
    {
    }

    func transcribeWithProgress(
      audioPath: String,
      language: Language,
      progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResult {
      TranscriptionResult(
        segments: [],
        totalDuration: 0,
        processingTime: 0,
        modelUsed: "mock"
      )
    }
  }

  func testResetState() async {
    cleanupTask?.cancel()
    cleanupTask = nil
    entries.removeAll()
    loadDurationHistory.removeAll()
    languageSupportCache.removeAll()
    cleanupTimeout = 600
    asrCleanupTimeout = 600
  }

  func testSetCleanupTimeout(seconds: TimeInterval) {
    cleanupTimeout = max(1, seconds)
  }

  func testSetASRCleanupTimeout(seconds: TimeInterval) {
    asrCleanupTimeout = max(1, seconds)
  }

  func testAcquireASRLease(for key: ModelLifecycleKey) -> ASRModelLease? {
    guard key.kind == .asr else { return nil }
    guard entries[key] != nil else { return nil }
    return registerASRLease(for: key)
  }

  func testReleaseASRLease(_ lease: ASRModelLease) {
    releaseASRLease(lease)
  }

  func testLoadMockResource(
    key: ModelLifecycleKey,
    displayName: String = "Mock",
    estimatedMemoryMB: Int = 32,
    delayNanoseconds: UInt64 = 0,
    failMessage: String? = nil,
    asASRResource: Bool = false
  ) async throws {
    _ = try await loadResource(
      key: key,
      displayName: displayName,
      estimatedMemoryMB: estimatedMemoryMB
    ) {
      if delayNanoseconds > 0 {
        try await Task.sleep(nanoseconds: delayNanoseconds)
      }
      if let failMessage {
        throw NSError(
          domain: "ModelCacheManagerTests",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: failMessage]
        )
      }
      if asASRResource {
        return .asr(MockTranscriber())
      }
      return .tts(
        TTSResource(engine: .qwen3TTS, modelID: "mock:\(key.identifier)", usesMLXRuntime: false))
    }
  }

  func testSetLastAccess(_ date: Date, for key: ModelLifecycleKey) {
    guard var entry = entries[key] else { return }
    entry.lastAccess = date
    entries[key] = entry
  }

  func testPurgeExpiredEntries() async {
    await purgeExpiredEntries()
  }

  func testContainsEntry(for key: ModelLifecycleKey) -> Bool {
    entries[key] != nil
  }

  func testRemoveEntry(for key: ModelLifecycleKey) {
    entries.removeValue(forKey: key)
    loadDurationHistory.removeValue(forKey: key)
  }

  func testErrorMessage(for key: ModelLifecycleKey) -> String? {
    entries[key]?.errorMessage
  }

  func testPerformanceSampleCount(for key: ModelLifecycleKey) -> Int {
    loadDurationHistory[key]?.count ?? 0
  }
}
#endif
