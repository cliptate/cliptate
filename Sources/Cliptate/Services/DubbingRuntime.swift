import CliptateCore
import Foundation

@MainActor
final class DubbingRuntime {
  static let shared = DubbingRuntime()

  private let ttsService: MLXTTSService
  private let dubbingServiceFactory: @MainActor (MLXTTSService) -> DubbingService

  init(
    ttsService: MLXTTSService = .shared,
    dubbingServiceFactory: @escaping @MainActor (MLXTTSService) -> DubbingService = {
      DubbingService(ttsService: $0)
    }
  ) {
    self.ttsService = ttsService
    self.dubbingServiceFactory = dubbingServiceFactory
  }

  func resolveVoiceCloneModel(preferredRepo: String) -> MLXTTSModelDefinition? {
    DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: preferredRepo)
  }

  func canPerformDubbing(segments: [Segment], ttsLanguage: String) -> Bool {
    DubbingModelResolver.canPerformDubbing(segments: segments, ttsLanguage: ttsLanguage)
  }

  func generateDubbedAudio(
    sourceMediaURL: URL,
    segments: [Segment],
    totalDuration: TimeInterval,
    ttsModelDefinition: MLXTTSModelDefinition,
    ttsLanguage: String,
    outputURL: URL,
    outputFormat: AudioExportFormat,
    presetSpeaker: String?,
    customReferenceAudioURL: URL? = nil,
    customReferenceText: String? = nil,
    progress: @escaping @Sendable (DubbingService.DubbingProgress) -> Void
  ) async throws -> DubbingService.DubbingResult {
    try await dubbingServiceFactory(ttsService).generateDubbedAudio(
      sourceMediaURL: sourceMediaURL,
      segments: segments,
      totalDuration: totalDuration,
      ttsModelDefinition: ttsModelDefinition,
      ttsLanguage: ttsLanguage,
      outputURL: outputURL,
      outputFormat: outputFormat,
      presetSpeaker: presetSpeaker,
      customReferenceAudioURL: customReferenceAudioURL,
      customReferenceText: customReferenceText,
      progress: progress
    )
  }
}
