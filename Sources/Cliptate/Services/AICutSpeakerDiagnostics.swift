import Foundation

/// Result of speaker capability diagnostics for the AI Cut workflow.
public struct AICutSpeakerDiagnosticResult: Equatable, Sendable {
  /// Whether speaker labels are available based on current configuration.
  public let isSpeakerCapable: Bool
  
  /// The aligner model variant that will be used (nil if none available).
  public let alignVariant: ModelVariant?
  
  /// Human-readable message explaining why speaker labels are unavailable (nil if capable).
  public let missingRequirementMessage: String?
  
  public init(
    isSpeakerCapable: Bool,
    alignVariant: ModelVariant?,
    missingRequirementMessage: String?
  ) {
    self.isSpeakerCapable = isSpeakerCapable
    self.alignVariant = alignVariant
    self.missingRequirementMessage = missingRequirementMessage
  }
}

/// Pure helper that decides whether the active AI Cut path is speaker-capable.
public enum AICutSpeakerDiagnostics {
  public static let missingAlignModelMessage =
    "Speaker labels are unavailable because no downloaded align model is ready."

  public static var localizedMissingAlignModelMessage: String {
    String(
      localized: "Speaker labels are unavailable because no downloaded align model is ready.",
      comment: "AI Cut status message"
    )
  }

  /// Resolves speaker capability based on configured/downloaded/auto-discovered aligner availability.
  ///
  /// - Parameters:
  ///   - configuredAligner: The user-configured aligner model variant (may be nil).
  ///   - isAlignerDownloaded: Whether the configured aligner is actually downloaded.
  ///   - autoDiscoveredAligner: Fallback aligner automatically discovered from downloaded models.
  /// - Returns: Diagnostic result indicating capability status and which model will be used.
  public static func resolve(
    configuredAligner: ModelVariant?,
    isAlignerDownloaded: Bool,
    autoDiscoveredAligner: ModelVariant?
  ) -> AICutSpeakerDiagnosticResult {
    if let configuredAligner {
      if isAlignerDownloaded {
        return .init(
          isSpeakerCapable: true,
          alignVariant: configuredAligner,
          missingRequirementMessage: nil
        )
      }

      return .init(
        isSpeakerCapable: false,
        alignVariant: nil,
        missingRequirementMessage: missingAlignModelMessage
      )
    }

    if let autoDiscoveredAligner {
      return .init(
        isSpeakerCapable: true,
        alignVariant: autoDiscoveredAligner,
        missingRequirementMessage: nil
      )
    }

    return .init(
      isSpeakerCapable: false,
      alignVariant: nil,
      missingRequirementMessage: missingAlignModelMessage
    )
  }
}
