import Foundation

/// Resolves model and precondition requirements for audio dubbing export.
/// Extracted from AICutView to enable testability and graceful fallback.
public enum DubbingModelResolver {

  /// Attempt to find a voice-clone-capable model definition.
  ///
  /// Strategy:
  /// 1. If the user's preferred model already supports voice cloning, use it directly.
  /// 2. Otherwise, find a Base model with matching parameter size and quantization.
  /// 3. If no exact match, return any available voice-clone model (prefers smaller).
  public static func resolveVoiceCloneModel(
    preferredRepo: String
  ) -> MLXTTSModelDefinition? {
    let allModels = MLXTTSModelDefinition.availableModels

    // Direct match: user's selected model supports voice cloning
    if let direct = allModels.first(where: {
      $0.huggingFaceRepo == preferredRepo && $0.supportsVoiceClone
    }) {
      return direct
    }

    // Find the user's selected model definition (even if it doesn't support clone)
    let preferred = allModels.first(where: { $0.huggingFaceRepo == preferredRepo })

    // Try to match same parameter size and quantization in a voice-clone model
    if let preferred = preferred {
      let sameSpec = allModels.first(where: {
        $0.supportsVoiceClone
          && $0.parameterSize == preferred.parameterSize
          && $0.quantization == preferred.quantization
      })
      if let sameSpec = sameSpec {
        return sameSpec
      }
    }

    // Fallback: any voice-clone model (prefer smaller for faster synthesis)
    return allModels.first(where: { $0.supportsVoiceClone })
  }

  /// Check whether dubbing can be performed with the given segments and language.
  /// Returns false if preconditions are not met (no translations, unsupported language, empty segments).
  public static func canPerformDubbing(
    segments: [Segment],
    ttsLanguage: String
  ) -> Bool {
    guard !segments.isEmpty else { return false }
    guard DubbingService.supportedTTSLanguages.contains(ttsLanguage) else { return false }
    let hasTranslations = segments.contains(where: { $0.translation != nil })
    return hasTranslations
  }
}
