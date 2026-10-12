import Foundation

struct BatchTranscriptionPlan: Sendable {
  let vad: any VADProvider
  let asr: any ASRChunkProvider
  let align: (any AlignChunkProvider)?
}

/// Creates the correct VAD, ASR, Align, and Streaming providers
/// based on the current model selection and transcriber type.
///
/// This is the single point of extension: to add a new engine, add
/// a new branch here and a new conforming type for each stage protocol.
enum TranscriptionPipelineFactory {
  @MainActor
  private static var cachedStreamingVADProviders: [ModelVariant: any StreamingVADProvider] = [:]

  // MARK: - Batch Pipeline

  /// Creates a VAD provider appropriate for the given model.
  /// Silero VAD models use the lightweight SileroVADProvider (no diarization).
  /// Sortformer models use the existing SortformerVADProvider.
  static func makeVADProvider(
    vadModel: ModelVariant? = nil,
    segmenter: SpeechSegmenter? = nil
  ) -> any VADProvider {
    if let model = vadModel, model.isSileroVADModel {
      return SileroVADProvider(model: model)
    }
    if let model = vadModel, model.isSortformerVADModel {
      return SortformerVADProvider(segmenter: segmenter ?? SpeechSegmenter(model: model))
    }
    return SortformerVADProvider(segmenter: segmenter ?? SpeechSegmenter())
  }

  /// Creates an ASR chunk provider appropriate for the given transcriber.
  ///
  /// - `Qwen3ASRTranscriber` → `Qwen3ASRChunkProvider` (with optional dictionary context)
  /// - `MLXParakeetTranscriber` → `ParakeetASRChunkProvider`
  /// - anything else → `FallbackASRChunkProvider` (uses `ChunkTranscriber` or file-based)
  static func makeASRChunkProvider(
    transcriber: any Transcriber,
    dictionaryContext: String? = nil
  ) -> any ASRChunkProvider {
    if let qwen3 = transcriber as? Qwen3ASRTranscriber {
      return Qwen3ASRChunkProvider(transcriber: qwen3, dictionaryContext: dictionaryContext)
    }
    if let parakeet = transcriber as? MLXParakeetTranscriber {
      return ParakeetASRChunkProvider(transcriber: parakeet)
    }
    return FallbackASRChunkProvider(transcriber: transcriber)
  }

  /// Creates an align chunk provider backed by the given Qwen3 forced-aligner.
  static func makeAlignChunkProvider(
    aligner: Qwen3ForcedAlignerTranscriber
  ) -> any AlignChunkProvider {
    Qwen3AlignChunkProvider(aligner: aligner)
  }

  /// Creates a batch transcription plan from explicit stage inputs.
  static func makeBatchPlan(
    transcriber: any Transcriber,
    aligner: Qwen3ForcedAlignerTranscriber? = nil,
    dictionaryContext: String? = nil,
    vadModel: ModelVariant? = nil
  ) -> BatchTranscriptionPlan {
    BatchTranscriptionPlan(
      vad: makeVADProvider(vadModel: vadModel),
      asr: makeASRChunkProvider(transcriber: transcriber, dictionaryContext: dictionaryContext),
      align: aligner.map(makeAlignChunkProvider)
    )
  }

  /// Creates a complete batch transcription pipeline (VAD + ASR + Align).
  static func makeBatchPipeline(
    transcriber: any Transcriber,
    aligner: Qwen3ForcedAlignerTranscriber,
    dictionaryContext: String? = nil,
    vadModel: ModelVariant? = nil
  ) -> BatchTranscriptionPipeline {
    let plan = makeBatchPlan(
      transcriber: transcriber,
      aligner: aligner,
      dictionaryContext: dictionaryContext,
      vadModel: vadModel
    )
    guard let align = plan.align else {
      preconditionFailure("Aligned batch pipeline requires an align provider")
    }
    return BatchTranscriptionPipeline(vad: plan.vad, asr: plan.asr, align: align)
  }

  // MARK: - Streaming Pipeline

  /// Creates a streaming transcription provider for any supported engine type.
  ///
  /// A fresh streaming VAD module (Sortformer or Silero) is created based on the
  /// active `vadModelVariant` and injected into the provider so the capture module
  /// remains decoupled from the concrete VAD type.
  @MainActor
  static func makeStreamingProvider(
    type: TranscriberType,
    transcriber: any Transcriber,
    streamingModule: StreamingAudioCaptureModule,
    vadModel: ModelVariant
  ) throws -> any StreamingTranscriptionProvider {
    let vad = makeStreamingVADProvider(vadModel: vadModel)

    let engine: any StreamingASREngine
    switch type {
    case .whisper:
      guard let whisper = transcriber as? MLXWhisperTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "MLXWhisperTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = whisper
    case .parakeet:
      guard let parakeet = transcriber as? MLXParakeetTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "MLXParakeetTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = parakeet
    case .qwen3:
      guard let qwen3 = transcriber as? Qwen3ASRTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "Qwen3ASRTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = qwen3
    case .fireRed:
      guard let fireRed = transcriber as? FireRedASRTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "FireRedASRTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = fireRed
    case .cohere:
      guard let cohere = transcriber as? CohereTranscribeASRTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "CohereTranscribeASRTranscriber",
          actual: String(describing: Swift.type(of: transcriber))
        )
      }
      engine = cohere
    }

    return UnifiedStreamingProvider(
      module: streamingModule,
      engine: engine,
      streamingVAD: vad,
      vadModel: vadModel
    )
  }

  @MainActor
  private static func makeStreamingVADProvider(vadModel: ModelVariant) -> any StreamingVADProvider {
    if let cached = cachedStreamingVADProviders[vadModel] {
      return cached
    }

    let provider: any StreamingVADProvider
    if vadModel.isSileroVADModel {
      provider = SileroStreamingVADModule(
        logger: .init(subsystem: "com.cliptate.app", category: "StreamingVAD"),
        configuration: .init(sampleRate: 16_000, threshold: 0.5)
      )
    } else {
      provider = SortformerStreamingVADModule(
        logger: .init(subsystem: "com.cliptate.app", category: "StreamingVAD"),
        configuration: .init(sampleRate: 16_000, threshold: 0.5)
      )
    }

    cachedStreamingVADProviders[vadModel] = provider
    return provider
  }
}

// MARK: - Errors

enum TranscriptionPipelineError: LocalizedError, Equatable {
  case transcirberTypeMismatch(expected: String, actual: String)
  case streamingNotSupported(type: TranscriberType)

  var errorDescription: String? {
    switch self {
    case .transcirberTypeMismatch(let expected, let actual):
      return "Transcriber type mismatch: expected \(expected), got \(actual)."
    case .streamingNotSupported(let type):
      return "\(type.displayName) does not support streaming transcription."
    }
  }
}
