import Combine
import Foundation
import os.log

/// Coordinates background model warm-ups so cached ASR models stay hot across the app lifecycle.
@MainActor
final class TranscriberWarmupCoordinator: ObservableObject {
  static let shared = TranscriberWarmupCoordinator()

  struct Signature: Hashable, Sendable {
    let type: TranscriberType
    let model: ModelVariant

    var displayName: String {
      "\(type.displayName) – \(model.displayName)"
    }
  }

  enum Status {
    case idle
    case warming(progress: ModelDownloadProgress?)
    case ready(Date)
    case blocked(String)
    case failed(String)
  }

  enum StreamingStatus: Equatable {
    case idle
    case warming
    case ready(Date)
    case failed(String)
  }

  enum WarmupReason: String, Sendable {
    case appLaunch
    case configurationChanged
    case voiceToTextSelection
    case downloadStatusUpdated
    case viewAppeared
    case userInitiated
  }

  @Published private(set) var statusBySignature: [Signature: Status] = [:]
  @Published private(set) var streamingStatus: StreamingStatus = .idle

  private var activeTasks: [Signature: Task<Void, Never>] = [:]
  private var streamingTasks: [ModelVariant: Task<Void, Never>] = [:]
  private var streamingStatuses: [ModelVariant: StreamingStatus] = [:]
  private var currentStreamingVariant: ModelVariant?
  private var cancellables: Set<AnyCancellable> = []
  private var didAttachConfiguration = false
  private weak var attachedConfig: AppConfiguration?
  private let logger = Logger(subsystem: "com.Cliptate", category: "ModelWarmup")

  private init() {}

  func bootstrap(using config: AppConfiguration) {
    guard !didAttachConfiguration else { return }
    didAttachConfiguration = true
    attachedConfig = config

    observeConfigurationChanges(in: config)

    let initialSignatures: Set<Signature> = [
      Signature(type: config.transcriberType, model: config.modelVariant),
    ]

    for signature in initialSignatures {
      scheduleWarmup(
        for: signature.type,
        model: signature.model,
        reason: .appLaunch,
        force: true
      )
    }

    ensureStreamingWarmup(
      for: config.transcriberType,
      model: config.modelVariant,
      force: true
    )

    scheduleVADWarmup(for: config.vadModelVariant, force: true)
  }

  func status(for signature: Signature) -> Status {
    statusBySignature[signature] ?? .idle
  }

  func status(for type: TranscriberType, model: ModelVariant) -> Status {
    status(for: Signature(type: type, model: model))
  }

  func scheduleWarmup(
    for type: TranscriberType,
    model: ModelVariant,
    reason: WarmupReason,
    force: Bool = false
  ) {
    Task { @MainActor [weak self] in
      await self?.handleWarmupRequest(
        for: type,
        model: model,
        reason: reason,
        force: force
      )
    }
  }

  /// Re-warm the configured ASR model using the last attached configuration.
  func triggerWarmup() {
    guard let config = attachedConfig else { return }
    scheduleWarmup(
      for: config.transcriberType,
      model: config.modelVariant,
      reason: .userInitiated,
      force: true
    )
  }

  @MainActor
  private func handleWarmupRequest(
    for type: TranscriberType,
    model: ModelVariant,
    reason: WarmupReason,
    force: Bool
  ) async {
    let signature = Signature(type: type, model: model)

    guard type.supportedModels.contains(model) else {
      logger.debug("Skipping warmup for unsupported combination")
      return
    }

    if force {
      if let task = activeTasks[signature] {
        task.cancel()
        activeTasks[signature] = nil
      }
    } else if await shouldSkipWarmup(for: signature) {
      return
    }

    startWarmupTask(for: signature, reason: reason)
  }

  @MainActor
  private func shouldSkipWarmup(for signature: Signature) async -> Bool {
    if case .warming = statusBySignature[signature] {
      return true
    }

    if case .ready = statusBySignature[signature] {
      return true
    }

    if let task = activeTasks[signature], !task.isCancelled {
      return true
    }

    if await ModelCacheManager.shared.hasReadyTranscriber(
      type: signature.type,
      model: signature.model
    ) {
      publishReady(for: signature)
      return true
    }

    if await ModelCacheManager.shared.isModelLoading(
      type: signature.type,
      model: signature.model
    ) {
      statusBySignature[signature] = .warming(progress: nil)
      bridgeExistingWarmup(for: signature)
      return true
    }

    return false
  }

  private func bridgeExistingWarmup(for signature: Signature) {
    if let task = activeTasks[signature], !task.isCancelled {
      return
    }

    let task = Task.detached(priority: .background) { [signature, weak coordinator = self] in
      guard let coordinator else { return }
      do {
        _ = try await ModelCacheManager.shared.getASRTranscriber(
          type: signature.type,
          model: signature.model
        ) { _ in }
        await coordinator.publishReady(for: signature)
      } catch is CancellationError {
        await coordinator.publishIdle(for: signature)
      } catch let error as ModelPreparationError {
        await coordinator.publishBlocked(error.localizedDescription, for: signature)
      } catch let error as ModelDownloadError {
        await coordinator.publishFailed(error.localizedDescription, for: signature)
      } catch {
        await coordinator.publishFailed(error.localizedDescription, for: signature)
      }
    }

    activeTasks[signature] = task
  }

  func ensureStreamingWarmup(
    for type: TranscriberType,
    model: ModelVariant,
    force: Bool = false
  ) {
    guard type == .parakeet else {
      resetStreamingWarmupState()
      return
    }
    warmStreamingEngines(for: model, force: force)
  }

  private func observeConfigurationChanges(in config: AppConfiguration) {
    config.$transcriberType.combineLatest(config.$modelVariant)
      .sink { [weak self] pair in
        let (type, model) = pair
        self?.scheduleWarmup(for: type, model: model, reason: .voiceToTextSelection)
        self?.ensureStreamingWarmup(for: type, model: model)
      }
      .store(in: &cancellables)

    config.$vadModelVariant
      .dropFirst()
      .removeDuplicates()
      .sink { [weak self] vadModel in
        self?.scheduleVADWarmup(for: vadModel)
      }
      .store(in: &cancellables)
  }

  private func scheduleVADWarmup(for model: ModelVariant, force: Bool = false) {
    Task.detached(priority: .background) { [logger] in
      do {
        try await ModelCacheManager.shared.preloadVADModel(model: model)
      } catch is CancellationError {
        return
      } catch {
        if !force {
          logger.error("Failed to preload VAD model \(model.rawValue): \(error.localizedDescription)")
        }
      }
    }
  }

  private func warmStreamingEngines(for model: ModelVariant?, force: Bool = false) {
    guard let model, model.isParakeetModel else {
      resetStreamingWarmupState()
      return
    }

    currentStreamingVariant = model
    streamingStatus = streamingStatuses[model] ?? .idle

    if !force {
      if case .ready = streamingStatuses[model] {
        if currentStreamingVariant == model {
          streamingStatus = streamingStatuses[model] ?? .idle
        }
        return
      }

      if case .warming = streamingStatuses[model],
        let task = streamingTasks[model],
        !task.isCancelled
      {
        if currentStreamingVariant == model {
          streamingStatus = .warming
        }
        return
      }
    } else if let task = streamingTasks[model] {
      task.cancel()
      streamingTasks[model] = nil
    }

    streamingStatuses[model] = .warming
    if currentStreamingVariant == model {
      streamingStatus = .warming
    }

    let task = Task.detached(priority: .background) { [weak self] in
      guard let self else { return }
      do {
        _ = try await ModelCacheManager.shared.getASRTranscriber(
          type: .parakeet,
          model: model,
          progress: { _ in }
        )
        await self.publishStreamingReady(for: model)
      } catch is CancellationError {
        await self.publishStreamingIdle(for: model)
      } catch {
        await self.publishStreamingFailed(error.localizedDescription, for: model)
      }
    }

    streamingTasks[model] = task
  }

  private func startWarmupTask(for signature: Signature, reason: WarmupReason) {
    logger.notice("Warming up model \(signature.displayName) due to \(reason.rawValue)")
    statusBySignature[signature] = .warming(progress: nil)

    let task = Task.detached(priority: .background) { [signature, weak coordinator = self] in
      guard let coordinator else { return }

      let hasArtifacts = await ModelDownloadManager.shared.hasLocalArtifacts(for: signature.model)
      guard hasArtifacts else {
        let message = "\(signature.model.displayName) is not downloaded yet."
        await coordinator.publishBlocked(message, for: signature)
        return
      }

      do {
        _ = try await ModelCacheManager.shared.getASRTranscriber(
          type: signature.type,
          model: signature.model,
          progress: { progress in
            Task { @MainActor [weak coordinator] in
              guard let coordinator else { return }
              coordinator.publishProgress(progress, for: signature)
            }
          }
        )
        await coordinator.publishReady(for: signature)
      } catch is CancellationError {
        await coordinator.publishIdle(for: signature)
      } catch let error as ModelPreparationError {
        await coordinator.publishBlocked(error.localizedDescription, for: signature)
      } catch let error as ModelDownloadError {
        await coordinator.publishFailed(error.localizedDescription, for: signature)
      } catch {
        await coordinator.publishFailed(error.localizedDescription, for: signature)
      }
    }

    activeTasks[signature] = task
  }

  @MainActor
  private func publishProgress(_ progress: ModelDownloadProgress, for signature: Signature) {
    statusBySignature[signature] = .warming(progress: progress)
  }

  @MainActor
  private func publishReady(for signature: Signature) {
    statusBySignature[signature] = .ready(Date())
    activeTasks[signature] = nil
  }

  @MainActor
  private func publishBlocked(_ message: String, for signature: Signature) {
    statusBySignature[signature] = .blocked(message)
    activeTasks[signature] = nil
  }

  @MainActor
  private func publishFailed(_ message: String, for signature: Signature) {
    statusBySignature[signature] = .failed(message)
    activeTasks[signature] = nil
  }

  @MainActor
  private func publishIdle(for signature: Signature) {
    if case .ready = statusBySignature[signature] {
      return
    }
    statusBySignature[signature] = .idle
    activeTasks[signature] = nil
  }

  @MainActor
  private func publishStreamingReady(for model: ModelVariant) {
    streamingTasks[model] = nil
    let ready = StreamingStatus.ready(Date())
    streamingStatuses[model] = ready
    if currentStreamingVariant == model {
      streamingStatus = ready
    }
  }

  @MainActor
  private func publishStreamingFailed(_ message: String, for model: ModelVariant) {
    streamingTasks[model] = nil
    let failed = StreamingStatus.failed(message)
    streamingStatuses[model] = failed
    if currentStreamingVariant == model {
      streamingStatus = failed
    }
  }

  @MainActor
  private func publishStreamingIdle(for model: ModelVariant) {
    streamingTasks[model] = nil
    streamingStatuses[model] = .idle
    if currentStreamingVariant == model {
      streamingStatus = .idle
    }
  }

  private func resetStreamingWarmupState() {
    currentStreamingVariant = nil
    streamingStatus = .idle
  }
}

extension TranscriberWarmupCoordinator.Status {
  var isWarming: Bool {
    if case .warming = self { return true }
    return false
  }

  var errorMessage: String? {
    switch self {
    case .blocked(let message), .failed(let message):
      return message
    default:
      return nil
    }
  }

  var progressDescription: String? {
    switch self {
    case .warming(let progress):
      return progress?.currentStep
    default:
      return nil
    }
  }
}
