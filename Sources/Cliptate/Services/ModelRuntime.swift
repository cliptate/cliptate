import Foundation

@MainActor
protocol ModelWarmupRuntimeControlling: AnyObject {
  func bootstrap(using config: AppConfiguration)
}

extension TranscriberWarmupCoordinator: ModelWarmupRuntimeControlling {}

protocol ModelCacheRuntimeControlling: Sendable {
  func updateCleanupTimeout(seconds: TimeInterval) async
  func updateASRIdleTimeout(seconds: TimeInterval) async
  func preloadASRModel(type: TranscriberType, model: ModelVariant) async throws
}

extension ModelCacheManager: ModelCacheRuntimeControlling {}

@MainActor
protocol ModelRuntimeControlling: AnyObject {
  func prepare(using config: AppConfiguration)
}

@MainActor
final class ModelRuntime: ObservableObject, ModelRuntimeControlling {
  enum Status: Equatable {
    case idle
    case preparing
    case ready
    case failed(String)
  }

  static let shared = ModelRuntime()

  @Published private(set) var status: Status = .idle

  private let warmupCoordinator: any ModelWarmupRuntimeControlling
  private let cacheController: any ModelCacheRuntimeControlling
  private var hasBootstrappedWarmup = false

  init(
    warmupCoordinator: (any ModelWarmupRuntimeControlling)? = nil,
    cacheController: (any ModelCacheRuntimeControlling)? = nil
  ) {
    self.warmupCoordinator = warmupCoordinator ?? TranscriberWarmupCoordinator.shared
    self.cacheController = cacheController ?? ModelCacheManager.shared
  }

  func prepare(using config: AppConfiguration) {
    if !hasBootstrappedWarmup {
      warmupCoordinator.bootstrap(using: config)
      hasBootstrappedWarmup = true
    }

    status = .preparing

    let cacheController = self.cacheController

    Task { [weak self, weak config] in
      guard let self, let config else { return }

      let selection = await MainActor.run {
        (
          config.transcriberType,
          config.modelVariant,
          config.modelCleanupTimeoutSeconds,
          config.asrIdleTimeoutSeconds
        )
      }

      do {
        await cacheController.updateCleanupTimeout(seconds: selection.2)
        await cacheController.updateASRIdleTimeout(seconds: selection.3)
        try await cacheController.preloadASRModel(type: selection.0, model: selection.1)
        await config.refreshModelLifecycleState()
        await MainActor.run {
          self.status = .ready
        }
      } catch {
        await MainActor.run {
          self.status = .failed(error.localizedDescription)
        }
      }
    }
  }
}
