import CliptateCore

/// Distribution and billing policy belongs to the application.
extension ModelVariant {
  /// Access level classification for this model variant
  public var accessLevel: ModelAccessLevel {
    guard SubscriptionPolicy.isBillingEnabled else { return .free }
    switch self {
    case .parakeetV3,
      .qwen3ASR17B4bit, .qwen3ASR17B5bit, .qwen3ASR17B6bit, .qwen3ASR17B8bit,
      .qwen3ASR17Bbf16,
      .fireRedASR2,
      .cohereTranscribe03FP16, .cohereTranscribe038bit, .cohereTranscribe034bit,
      .sortformerStreaming, .sortformerOffline:
      return .pro
    default:
      return .free
    }
  }
  /// Indicates whether the model requires a Pro subscription
  public var requiresProSubscription: Bool {
    accessLevel.requiresSubscription
  }

  /// Convenience list of all free models
  public static var freeModels: [ModelVariant] {
    allCases.filter { !$0.requiresProSubscription }
  }

  /// Convenience list of all Pro models
  public static var proModels: [ModelVariant] {
    allCases.filter(\.requiresProSubscription)
  }

}
