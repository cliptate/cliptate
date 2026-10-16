import Combine
import Foundation

enum AnalyticsOperation: String, Sendable {
  case transcription
  case export
}

enum AnalyticsOutcome: String, Sendable {
  case succeeded
  case failed
  case cancelled
}

enum AnalyticsEvent: Equatable, Sendable {
  case appLaunched
  case featureOpened(AppSection)
  case operationFinished(AnalyticsOperation, outcome: AnalyticsOutcome, durationSeconds: TimeInterval)

  var name: String {
    switch self {
    case .appLaunched: "app_launch"
    case .featureOpened: "feature_open"
    case .operationFinished(let operation, _, _): "\(operation.rawValue)_finished"
    }
  }

  var parameters: [String: Any] {
    switch self {
    case .appLaunched:
      return [:]
    case .featureOpened(let section):
      return ["feature": section.rawValue]
    case .operationFinished(_, let outcome, let duration):
      var result: [String: Any] = [
        "outcome": outcome.rawValue,
        "duration_ms": duration.isFinite ? min(max(0, duration), 604_800) * 1000 : 0,
      ]
      if outcome != .succeeded {
        result["failure_category"] = outcome == .cancelled ? "cancelled" : "processing"
      }
      return result
    }
  }
}

@MainActor
final class AnalyticsRuntime {
  static let shared: AnalyticsRuntime = {
    let client = FirebaseAnalyticsClient()
    return AnalyticsRuntime(deliver: client.record, updateCollection: client.setCollectionEnabled)
  }()

  private let deliver: @MainActor (AnalyticsEvent) -> Void
  private let updateCollection: @MainActor (Bool) -> Void
  private var collectionEnabled = false
  private var preferenceObservation: AnyCancellable?

  init(
    deliver: @escaping @MainActor (AnalyticsEvent) -> Void,
    updateCollection: @escaping @MainActor (Bool) -> Void = { _ in }
  ) {
    self.deliver = deliver
    self.updateCollection = updateCollection
  }

  func bind(to config: AppConfiguration) {
    preferenceObservation = config.$analyticsCollectionEnabled.removeDuplicates().sink {
      [weak self] enabled in self?.start(collectionEnabled: enabled)
    }
  }

  func start(collectionEnabled: Bool) {
    setCollectionEnabled(collectionEnabled)
  }

  func setCollectionEnabled(_ enabled: Bool) {
    collectionEnabled = enabled
    updateCollection(enabled)
  }

  func record(_ event: AnalyticsEvent) {
    guard collectionEnabled else { return }
    deliver(event)
  }
}
