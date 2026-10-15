import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("ModelCacheManager lifecycle and concurrency", .serialized)
struct ModelCacheManagerLifecycleTests {
  private func uniqueKey(kind: ModelLifecycleKind = .tts, prefix: String) -> ModelLifecycleKey {
    ModelLifecycleKey(kind: kind, identifier: "\(prefix)-\(UUID().uuidString)")
  }

  @Test("lazy loading reuses cached model instance")
  func lazyLoadingReusesCache() async throws {
    let key = uniqueKey(prefix: "lazy-load")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Lazy Load Test",
      estimatedMemoryMB: 24
    )
    try await ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Lazy Load Test",
      estimatedMemoryMB: 24
    )

    let state = await ModelCacheManager.shared.modelState(for: key)
    let sampleCount = await ModelCacheManager.shared.testPerformanceSampleCount(for: key)
    #expect(state == .loaded)
    #expect(sampleCount == 1)
    await ModelCacheManager.shared.testRemoveEntry(for: key)
  }

  @Test("idle cleanup removes stale non-ASR entries")
  func cleanupPurgesIdleTTSModels() async throws {
    let key = uniqueKey(prefix: "cleanup")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Cleanup Test",
      estimatedMemoryMB: 64
    )
    await ModelCacheManager.shared.testSetLastAccess(
      Date().addingTimeInterval(-720),
      for: key
    )
    await ModelCacheManager.shared.testPurgeExpiredEntries()

    let exists = await ModelCacheManager.shared.testContainsEntry(for: key)
    #expect(exists == false)
    await ModelCacheManager.shared.testRemoveEntry(for: key)
  }

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
    await ModelCacheManager.shared.testSetASRCleanupTimeout(seconds: 600)
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

  @Test("idle cleanup keeps ASR entries while actively in use")
  func cleanupKeepsLeasedASRModelsAfterASRTimeout() async throws {
    let key = ModelLifecycleKey(kind: .asr, identifier: "parakeet:leased-test")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Leased ASR Test",
      estimatedMemoryMB: 80,
      asASRResource: true
    )
    await ModelCacheManager.shared.testSetASRCleanupTimeout(seconds: 1)
    let lease = try #require(await ModelCacheManager.shared.testAcquireASRLease(for: key))
    await ModelCacheManager.shared.testSetLastAccess(Date().addingTimeInterval(-5), for: key)
    await ModelCacheManager.shared.testPurgeExpiredEntries()

    let existsWhileLeased = await ModelCacheManager.shared.testContainsEntry(for: key)
    #expect(existsWhileLeased == true)

    await ModelCacheManager.shared.testReleaseASRLease(lease)
    await ModelCacheManager.shared.testPurgeExpiredEntries()

    let existsImmediatelyAfterRelease = await ModelCacheManager.shared.testContainsEntry(for: key)
    #expect(existsImmediatelyAfterRelease == true)

    await ModelCacheManager.shared.testSetLastAccess(Date().addingTimeInterval(-5), for: key)
    await ModelCacheManager.shared.testPurgeExpiredEntries()

    let existsAfterIdleAgain = await ModelCacheManager.shared.testContainsEntry(for: key)
    #expect(existsAfterIdleAgain == false)
    await ModelCacheManager.shared.testSetASRCleanupTimeout(seconds: 600)
  }

  @Test("failed model load transitions to error and recovers on retry")
  func modelLoadErrorRecoveryFlow() async throws {
    let key = uniqueKey(prefix: "error-recovery")

    await #expect(throws: Error.self) {
      try await ModelCacheManager.shared.testLoadMockResource(
        key: key,
        displayName: "Recovery Test",
        estimatedMemoryMB: 48,
        failMessage: "intentional failure"
      )
    }

    let failedState = await ModelCacheManager.shared.modelState(for: key)
    let failedMessage = await ModelCacheManager.shared.testErrorMessage(for: key)
    #expect(failedState == .error("intentional failure"))
    #expect(failedMessage == "intentional failure")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Recovery Test",
      estimatedMemoryMB: 48
    )

    let recoveredState = await ModelCacheManager.shared.modelState(for: key)
    let sampleCount = await ModelCacheManager.shared.testPerformanceSampleCount(for: key)
    #expect(recoveredState == .loaded)
    #expect(sampleCount == 1)
    await ModelCacheManager.shared.testRemoveEntry(for: key)
  }

  @Test("concurrent requests for same model only load once")
  func concurrentRequestsShareSingleLoad() async throws {
    let key = uniqueKey(prefix: "concurrent")

    async let first: Void = ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Concurrent Test",
      estimatedMemoryMB: 32,
      delayNanoseconds: 150_000_000
    )
    async let second: Void = ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Concurrent Test",
      estimatedMemoryMB: 32,
      delayNanoseconds: 150_000_000
    )
    _ = try await (first, second)

    let sampleCount = await ModelCacheManager.shared.testPerformanceSampleCount(for: key)
    let state = await ModelCacheManager.shared.modelState(for: key)
    #expect(sampleCount == 1)
    #expect(state == .loaded)
    await ModelCacheManager.shared.testRemoveEntry(for: key)
  }

  @Test("cleanup reduces tracked cache memory for expired entries")
  func memoryCleanupEffectiveness() async throws {
    let keyA = uniqueKey(prefix: "memory-a")
    let keyB = uniqueKey(prefix: "memory-b")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: keyA,
      displayName: "Memory A",
      estimatedMemoryMB: 70
    )
    try await ModelCacheManager.shared.testLoadMockResource(
      key: keyB,
      displayName: "Memory B",
      estimatedMemoryMB: 90
    )

    let before = await ModelCacheManager.shared.snapshot()
    let trackedBefore = before.statuses
      .filter { $0.key == keyA || $0.key == keyB }
      .reduce(0) { $0 + $1.memoryUsageMB }
    #expect(trackedBefore == 160)

    let staleDate = Date().addingTimeInterval(-720)
    await ModelCacheManager.shared.testSetLastAccess(staleDate, for: keyA)
    await ModelCacheManager.shared.testSetLastAccess(staleDate, for: keyB)
    await ModelCacheManager.shared.testPurgeExpiredEntries()

    let after = await ModelCacheManager.shared.snapshot()
    let trackedAfter = after.statuses
      .filter { $0.key == keyA || $0.key == keyB }
      .reduce(0) { $0 + $1.memoryUsageMB }
    #expect(trackedAfter == 0)
    await ModelCacheManager.shared.testRemoveEntry(for: keyA)
    await ModelCacheManager.shared.testRemoveEntry(for: keyB)
  }

  @Test("releasing a TTS model removes its cached entry immediately")
  func releaseTTSModelRemovesEntry() async throws {
    let modelID = "release-\(UUID().uuidString)"
    let key = ModelLifecycleKey(kind: .tts, identifier: "\(TTSEngine.qwen3TTS.rawValue):\(modelID)")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: key,
      displayName: "Release TTS Test",
      estimatedMemoryMB: 48
    )

    await ModelCacheManager.shared.releaseTTSModel(engine: .qwen3TTS, modelID: modelID)

    let exists = await ModelCacheManager.shared.testContainsEntry(for: key)
    #expect(exists == false)
  }

  @Test("evictAll removes all cached entries regardless of type or lease")
  func evictAllClearsEverything() async throws {
    let asrKey = uniqueKey(kind: .asr, prefix: "evict-asr")
    let ttsKey = uniqueKey(kind: .tts, prefix: "evict-tts")
    let alignKey = uniqueKey(kind: .align, prefix: "evict-align")

    try await ModelCacheManager.shared.testLoadMockResource(
      key: asrKey, displayName: "Evict ASR", estimatedMemoryMB: 100, asASRResource: true
    )
    try await ModelCacheManager.shared.testLoadMockResource(
      key: ttsKey, displayName: "Evict TTS", estimatedMemoryMB: 50
    )
    try await ModelCacheManager.shared.testLoadMockResource(
      key: alignKey, displayName: "Evict Align", estimatedMemoryMB: 60
    )

    let beforeSnapshot = await ModelCacheManager.shared.snapshot()
    #expect(beforeSnapshot.statuses.contains { $0.key == asrKey })
    #expect(beforeSnapshot.statuses.contains { $0.key == ttsKey })
    #expect(beforeSnapshot.statuses.contains { $0.key == alignKey })

    await ModelCacheManager.shared.evictAll()

    let afterSnapshot = await ModelCacheManager.shared.snapshot()
    let testKeys: Set<ModelLifecycleKey> = [asrKey, ttsKey, alignKey]
    let remainingTestEntries = afterSnapshot.statuses.filter { testKeys.contains($0.key) }
    #expect(remainingTestEntries.isEmpty)
  }
}
