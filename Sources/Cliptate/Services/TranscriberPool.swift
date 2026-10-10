import Foundation

/// 键：区分不同转写器实例（类型 + 模型）
private struct TranscriberKey: Hashable {
  let type: TranscriberType
  let model: ModelVariant
}

/// 缓存条目，记录最近访问时间与正在进行的预热任务
private struct TranscriberEntry {
  var transcriber: Transcriber?
  var lastAccess: Date
  var warmingTask: Task<TranscriberBox, Error>?  // 避免并发重复预热
}

/// Lightweight box to bridge non-Sendable transcriber references across async boundaries.
private final class TranscriberBox: @unchecked Sendable {
  let value: Transcriber

  init(_ value: Transcriber) {
    self.value = value
  }
}

/// 线程安全（actor）转写器池：按配置预加载，闲置超时（默认10分钟）自动释放。
@available(*, deprecated, message: "Use ModelCacheManager.shared instead.")
actor TranscriberPool {
  nonisolated static let shared: TranscriberPool = {
    let pool = TranscriberPool()
    Task { await pool.startCleanupLoop() }
    return pool
  }()

  private var entries: [TranscriberKey: TranscriberEntry] = [:]
  private let expiry: TimeInterval = 3600  // 1 hour
  private var cleanupTask: Task<Void, Never>?

  private init() {}

  /// 获取（或预热）对应配置的 transcriber。
  /// 多个并发请求会复用同一个 warmingTask。
  func getTranscriber(
    type: TranscriberType, model: ModelVariant,
    progress: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Transcriber {
    let key = TranscriberKey(type: type, model: model)
    // 已存在并预热
    if var entry = entries[key], let ready = entry.transcriber {
      entry.lastAccess = Date()
      entries[key] = entry
      return ready
    }
    // 已存在预热中的任务
    if var entry = entries[key], let task = entry.warmingTask {
      entry.lastAccess = Date()
      entries[key] = entry
      return try await task.value.value
    }

    try await validateModelReadiness(for: model)

    // 创建新 transcriber & 预热任务
    let transcriber = type.createTranscriber(model: model)
    let warming = Task<TranscriberBox, Error> {
      try await transcriber.warmUpModelWithProgress { p in
        progress(p)
      }
      return TranscriberBox(transcriber)
    }
    entries[key] = TranscriberEntry(transcriber: nil, lastAccess: Date(), warmingTask: warming)
    do {
      let readyBox = try await warming.value
      let ready = readyBox.value
      // 预热完成，存入实例
      if var finished = entries[key] {
        finished.transcriber = ready
        finished.warmingTask = nil
        finished.lastAccess = Date()
        entries[key] = finished
      }
      return ready
    } catch {
      // 失败清理条目
      entries.removeValue(forKey: key)
      throw error
    }
  }

  /// 使用时更新访问时间，防止过早过期。
  func noteAccess(type: TranscriberType, model: ModelVariant) {
    let key = TranscriberKey(type: type, model: model)
    if var entry = entries[key] {
      entry.lastAccess = Date()
      entries[key] = entry
    }
  }

  /// 判断指定模型是否已经完成预热并可复用。
  func hasReadyTranscriber(type: TranscriberType, model: ModelVariant) -> Bool {
    let key = TranscriberKey(type: type, model: model)
    if let entry = entries[key], entry.transcriber != nil {
      return true
    }
    return false
  }

  /// 检查指定配置的模型是否正在预热中。
  func isModelWarming(type: TranscriberType, model: ModelVariant) -> Bool {
    let key = TranscriberKey(type: type, model: model)
    return entries[key]?.warmingTask != nil
  }

  /// 主循环：每 60s 清理一次过期实例。
  private func startCleanupLoop() {
    cleanupTask = Task { [weak self] in
      while !(Task.isCancelled) {
        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        await self?.purgeExpired()
      }
    }
  }

  private func purgeExpired() {
    let now = Date()
    var removed: [TranscriberKey] = []
    for (k, v) in entries {
      // 仍在预热的不清理
      if v.warmingTask != nil { continue }
      if now.timeIntervalSince(v.lastAccess) > expiry {
        removed.append(k)
      }
    }
    removed.forEach { entries.removeValue(forKey: $0) }
    if !removed.isEmpty {
      print("[TranscriberPool] purged \(removed.count) expired model(s)")
    }
  }

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
}
