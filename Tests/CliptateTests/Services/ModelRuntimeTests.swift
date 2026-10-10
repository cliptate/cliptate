import Foundation
import Testing

@testable import Cliptate

@Suite("ModelRuntime")
@MainActor
struct ModelRuntimeTests {
  @Test("prepare bootstraps warmup once and preloads the selected model")
  func prepareBootstrapsWarmupOnce() async throws {
    let config = AppConfiguration.shared
    let original = config.makeSnapshot()
    defer { config.applySnapshot(original) }

    config.transcriberType = .qwen3
    config.modelVariant = .qwen3ASR
    config.modelCleanupTimeoutSeconds = 321
    config.asrIdleTimeoutSeconds = 654

    let warmup = FakeWarmupCoordinator()
    let cache = FakeModelCacheController()
    let runtime = ModelRuntime(warmupCoordinator: warmup, cacheController: cache)

    runtime.prepare(using: config)
    await waitUntilReady(runtime)

    runtime.prepare(using: config)
    await waitUntilPreloadCount(cache, expected: 2)

    #expect(warmup.bootstrapCallCount == 1)
    #expect(await cache.cleanupTimeouts.elementsEqual([321, 321]))
    #expect(await cache.asrIdleTimeouts.elementsEqual([654, 654]))
    let preloadRequests = await cache.preloadRequests
    #expect(preloadRequests.count == 2)
    #expect(preloadRequests.allSatisfy { $0.0 == .qwen3 && $0.1 == .qwen3ASR })
    #expect(runtime.status == .ready)
  }

  private func waitUntilReady(_ runtime: ModelRuntime) async {
    for _ in 0..<100 {
      if runtime.status == .ready {
        return
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  private func waitUntilPreloadCount(_ cache: FakeModelCacheController, expected: Int) async {
    for _ in 0..<100 {
      if await cache.preloadRequests.count == expected {
        return
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}

@MainActor
private final class FakeWarmupCoordinator: ModelWarmupRuntimeControlling {
  private(set) var bootstrapCallCount = 0

  func bootstrap(using config: AppConfiguration) {
    bootstrapCallCount += 1
  }
}

private actor FakeModelCacheController: ModelCacheRuntimeControlling {
  private(set) var cleanupTimeouts: [TimeInterval] = []
  private(set) var asrIdleTimeouts: [TimeInterval] = []
  private(set) var preloadRequests: [(TranscriberType, ModelVariant)] = []

  func updateCleanupTimeout(seconds: TimeInterval) async {
    cleanupTimeouts.append(seconds)
  }

  func updateASRIdleTimeout(seconds: TimeInterval) async {
    asrIdleTimeouts.append(seconds)
  }

  func preloadASRModel(type: TranscriberType, model: ModelVariant) async throws {
    preloadRequests.append((type, model))
  }
}
