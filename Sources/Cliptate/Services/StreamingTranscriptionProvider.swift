import CliptateCore
import Foundation

/// Abstracts a single streaming transcription session (mic-to-text).
///
/// Implementations are created per-session by `TranscriptionPipelineFactory`
/// and wrap a `StreamingAudioCaptureModule` together with an engine.
@MainActor
protocol StreamingTranscriptionProvider: AnyObject {
  func start(language: Language, dictionaryContext: String?) async throws
  func stop() async throws -> String?
  func reset()
}

/// Unified streaming provider backed by StreamingAudioCaptureModule.
@MainActor
final class UnifiedStreamingProvider: StreamingTranscriptionProvider {
  private let module: StreamingAudioCaptureModule
  private let engine: any StreamingASREngine
  private let streamingVAD: (any StreamingVADProvider)?
  private let vadModel: ModelVariant?

  init(
    module: StreamingAudioCaptureModule,
    engine: any StreamingASREngine,
    streamingVAD: (any StreamingVADProvider)? = nil,
    vadModel: ModelVariant? = nil
  ) {
    self.module = module
    self.engine = engine
    self.streamingVAD = streamingVAD
    self.vadModel = vadModel
  }

  func start(language: Language, dictionaryContext: String?) async throws {
    try await module.start(
      engine: engine,
      language: language,
      dictionaryContext: dictionaryContext,
      streamingVAD: streamingVAD,
      vadModel: vadModel
    )
  }

  func stop() async throws -> String? {
    try await module.stop()
  }

  func reset() {
    module.reset()
  }
}

#if DEBUG
  extension UnifiedStreamingProvider {
    var testStreamingVADIdentifier: ObjectIdentifier? {
      if let silero = streamingVAD as? SileroStreamingVADModule {
        return ObjectIdentifier(silero)
      }
      if let sortformer = streamingVAD as? SortformerStreamingVADModule {
        return ObjectIdentifier(sortformer)
      }
      return nil
    }
  }
#endif
