import CliptateCore
import Foundation

@MainActor
final class DubbingRuntime {
  static let shared = DubbingRuntime()

  private let ttsService: MLXTTSService
  private let dubbingServiceFactory: @MainActor (MLXTTSService) -> DubbingService
  typealias Synthesizer =
    @MainActor (String, DubbingSynthesisRequest, URL?, String?) async throws -> DubbingAudio
  let synthesize: Synthesizer
  private let usesModelCache: Bool
  private var isPreparing = false

  init(
    ttsService: MLXTTSService = .shared,
    synthesize: Synthesizer? = nil,
    dubbingServiceFactory: @escaping @MainActor (MLXTTSService) -> DubbingService = {
      DubbingService(ttsService: $0)
    }
  ) {
    self.ttsService = ttsService
    self.dubbingServiceFactory = dubbingServiceFactory
    self.usesModelCache = synthesize == nil
    self.synthesize =
      synthesize ?? { text, request, referenceURL, referenceText in
        let audio = try await ttsService.synthesizeDubbingAudio(
          text: text, modelDefinition: request.model, voiceDescription: nil,
          referenceAudioURL: referenceURL, referenceText: referenceText, language: request.language)
        await ttsService.clearMLXCache()
        return audio
      }
  }

  func prepare(
    request: VideoDubbingRequest, cachedClips: [DubbedClip] = [],
    generating: Set<SegmentIdentifier>? = nil,
    onClip: (DubbedClip) -> Void = { _ in }
  ) async throws -> DubbingPreparation {
    let needsAdmission = usesModelCache && generating?.isEmpty != true
    if needsAdmission && isPreparing { throw VideoDubbingError.busy }
    if needsAdmission { isPreparing = true }
    defer { if needsAdmission { isPreparing = false } }
    var acquired = false
    do {
      let result = try await prepareClips(
        request: request, cachedClips: cachedClips, generating: generating,
        beforeSynthesis: {
          if self.usesModelCache && !acquired {
            _ = try await ModelCacheManager.shared.ensureTTSModel(
              engine: .qwen3TTS, modelID: request.model.huggingFaceRepo)
            acquired = true
          }
        },
        onClip: onClip)
      if acquired {
        await ModelCacheManager.shared.releaseTTSModel(
          engine: .qwen3TTS, modelID: request.model.huggingFaceRepo)
      }
      return result
    } catch {
      if acquired {
        await ModelCacheManager.shared.releaseTTSModel(
          engine: .qwen3TTS, modelID: request.model.huggingFaceRepo)
      }
      throw error
    }
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
