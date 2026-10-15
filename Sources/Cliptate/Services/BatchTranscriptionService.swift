import CliptateCore
import AVFoundation
import Foundation

enum BatchTranscriptionWorkflow: Sendable {
  case fileTranscription
  case dictationFinalization
  case dictationHistoryReprocessing

  var usesAlignment: Bool {
    switch self {
    case .fileTranscription:
      return true
    case .dictationFinalization, .dictationHistoryReprocessing:
      return false
    }
  }
}

struct BatchTranscriptionRequest: Sendable {
  let sourceURL: URL
  let workflow: BatchTranscriptionWorkflow
  let transcriberType: TranscriberType
  let asrModel: ModelVariant
  let vadModel: ModelVariant
  let alignModel: ModelVariant?
  let language: Language
  let dictionaryEntries: [String]
}

struct BatchTranscriptionSamplesRequest: Sendable {
  let audioSamples: [Float]
  let totalDuration: TimeInterval
  let workflow: BatchTranscriptionWorkflow
  let transcriberType: TranscriberType
  let asrModel: ModelVariant
  let vadModel: ModelVariant
  let alignModel: ModelVariant?
  let language: Language
  let dictionaryEntries: [String]
}

struct BatchTranscriptionOutput: Sendable {
  let result: TranscriptionResult
  let speakerAnnotationApplied: Bool
  let sourceURLBookmark: Data?
}

struct BatchTranscriptionService {
  typealias ASRAcquireClosure = @Sendable (
    TranscriberType, ModelVariant, @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> (Transcriber, ASRModelLease)
  typealias ASRReleaseClosure = @Sendable (ASRModelLease) async -> Void
  typealias AlignAcquireClosure = @Sendable (
    ModelVariant, @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Qwen3ForcedAlignerTranscriber
  typealias BookmarkCreateClosure = @Sendable (URL) -> Data?
  typealias BatchPlanFactory = @Sendable (
    any Transcriber,
    Qwen3ForcedAlignerTranscriber?,
    String?,
    ModelVariant?
  ) -> BatchTranscriptionPlan

  let loadAudioSamples: @Sendable (URL) async throws -> [Float]
  let loadDuration: @Sendable (URL) async throws -> TimeInterval
  let acquireASRTranscriber: ASRAcquireClosure
  let releaseASRLease: ASRReleaseClosure
  let acquireAlignTranscriber: AlignAcquireClosure
  let makePostProcessor: @Sendable (ModelVariant) -> TranscriptionPostProcessor
  let makeSourceBookmark: BookmarkCreateClosure
  let makeBatchPlan: BatchPlanFactory

  init(
    loadAudioSamples: @escaping @Sendable (URL) async throws -> [Float] = { url in
      try await AudioProcessor.loadAndConvertAudio(url: url)
    },
    loadDuration: @escaping @Sendable (URL) async throws -> TimeInterval = { url in
      let asset = AVURLAsset(url: url)
      let duration = try await asset.load(.duration)
      return max(duration.seconds, 0.001)
    },
    acquireASRTranscriber: @escaping ASRAcquireClosure = { type, model, progress in
      try await ModelCacheManager.shared.acquireASRTranscriber(type: type, model: model, progress: progress)
    },
    releaseASRLease: @escaping ASRReleaseClosure = { lease in
      ModelCacheManager.shared.releaseASRLease(lease)
    },
    acquireAlignTranscriber: @escaping AlignAcquireClosure = { model, progress in
      try await ModelCacheManager.shared.getAlignTranscriber(model: model, progress: progress)
    },
    makePostProcessor: @escaping @Sendable (ModelVariant) -> TranscriptionPostProcessor = { vadModel in
      TranscriptionPostProcessor(speakerPropagation: PlainASRSpeakerPropagation(vadModel: vadModel))
    },
    makeSourceBookmark: @escaping BookmarkCreateClosure = { url in
      try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    },
    makeBatchPlan: @escaping BatchPlanFactory = { transcriber, aligner, dictionaryContext, vadModel in
      TranscriptionPipelineFactory.makeBatchPlan(
        transcriber: transcriber,
        aligner: aligner,
        dictionaryContext: dictionaryContext,
        vadModel: vadModel
      )
    }
  ) {
    self.loadAudioSamples = loadAudioSamples
    self.loadDuration = loadDuration
    self.acquireASRTranscriber = acquireASRTranscriber
    self.releaseASRLease = releaseASRLease
    self.acquireAlignTranscriber = acquireAlignTranscriber
    self.makePostProcessor = makePostProcessor
    self.makeSourceBookmark = makeSourceBookmark
    self.makeBatchPlan = makeBatchPlan
  }

  func transcribe(
    request: BatchTranscriptionRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in },
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput {
    let needsStop = request.sourceURL.startAccessingSecurityScopedResource()
    defer {
      if needsStop {
        request.sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let audioSamples = try await loadAudioSamples(request.sourceURL)
    let totalDuration = try await loadDuration(request.sourceURL)
    let dictionaryContext = ASRDictionaryBiasService.dictionaryContext(from: request.dictionaryEntries)

    let (transcriber, lease) = try await acquireASRTranscriber(
      request.transcriberType,
      request.asrModel,
      modelProgressHandler
    )
    do {
      let aligner = try await resolveAligner(for: request, modelProgressHandler: modelProgressHandler)
      let plan = makeBatchPlan(transcriber, aligner, dictionaryContext, request.vadModel)
      let modelUsed = if let alignModel = request.workflow.usesAlignment ? request.alignModel : nil {
        "\(request.asrModel.rawValue) + \(alignModel.rawValue)"
      } else {
        request.asrModel.rawValue
      }
      let rawResult = try await run(
        plan: plan,
        samples: audioSamples,
        totalDuration: totalDuration,
        language: request.language,
        modelUsed: modelUsed,
        progressHandler: progressHandler
      )
      let postResult = await makePostProcessor(request.vadModel).postProcess(
        asrResult: rawResult,
        sourceURL: request.sourceURL,
        dictionaryEntries: request.dictionaryEntries
      )
      let sourceURLBookmark = makeSourceBookmark(request.sourceURL)
      await releaseASRLease(lease)
      return BatchTranscriptionOutput(
        result: TranscriptionResult(
          segments: postResult.segments,
          totalDuration: rawResult.totalDuration,
          processingTime: rawResult.processingTime,
          modelUsed: rawResult.modelUsed,
          createdAt: rawResult.createdAt
        ),
        speakerAnnotationApplied: postResult.speakerAnnotationApplied,
        sourceURLBookmark: sourceURLBookmark
      )
    } catch {
      await releaseASRLease(lease)
      throw error
    }
  }

  func transcribe(
    request: BatchTranscriptionSamplesRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in },
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput {
    let dictionaryContext = ASRDictionaryBiasService.dictionaryContext(from: request.dictionaryEntries)

    let (transcriber, lease) = try await acquireASRTranscriber(
      request.transcriberType,
      request.asrModel,
      modelProgressHandler
    )
    do {
      let aligner = try await resolveAligner(for: request, modelProgressHandler: modelProgressHandler)
      let plan = makeBatchPlan(transcriber, aligner, dictionaryContext, request.vadModel)
      let modelUsed = if let alignModel = request.workflow.usesAlignment ? request.alignModel : nil {
        "\(request.asrModel.rawValue) + \(alignModel.rawValue)"
      } else {
        request.asrModel.rawValue
      }
      let rawResult = try await run(
        plan: plan,
        samples: request.audioSamples,
        totalDuration: request.totalDuration,
        language: request.language,
        modelUsed: modelUsed,
        progressHandler: progressHandler
      )
      let postResult = await makePostProcessor(request.vadModel).postProcess(
        asrResult: rawResult,
        audioSamples: request.audioSamples,
        dictionaryEntries: request.dictionaryEntries
      )
      await releaseASRLease(lease)
      return BatchTranscriptionOutput(
        result: TranscriptionResult(
          segments: postResult.segments,
          totalDuration: rawResult.totalDuration,
          processingTime: rawResult.processingTime,
          modelUsed: rawResult.modelUsed,
          createdAt: rawResult.createdAt
        ),
        speakerAnnotationApplied: postResult.speakerAnnotationApplied,
        sourceURLBookmark: nil
      )
    } catch {
      await releaseASRLease(lease)
      throw error
    }
  }

  private func resolveAligner(
    for request: BatchTranscriptionRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Qwen3ForcedAlignerTranscriber? {
    guard request.workflow.usesAlignment, let alignModel = request.alignModel else { return nil }
    return try await acquireAlignTranscriber(alignModel, modelProgressHandler)
  }

  private func resolveAligner(
    for request: BatchTranscriptionSamplesRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws -> Qwen3ForcedAlignerTranscriber? {
    guard request.workflow.usesAlignment, let alignModel = request.alignModel else { return nil }
    return try await acquireAlignTranscriber(alignModel, modelProgressHandler)
  }

  private func run(
    plan: BatchTranscriptionPlan,
    samples: [Float],
    totalDuration: Double,
    language: Language,
    modelUsed: String,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    if let align = plan.align {
      return try await BatchTranscriptionPipeline(vad: plan.vad, asr: plan.asr, align: align).run(
        samples: samples,
        totalDuration: totalDuration,
        language: language,
        modelUsed: modelUsed,
        progressHandler: progressHandler
      )
    }

    return try await BatchASRTranscriptionPipeline(vad: plan.vad, asr: plan.asr).run(
      samples: samples,
      totalDuration: totalDuration,
      language: language,
      modelUsed: modelUsed,
      progressHandler: progressHandler
    )
  }
}
