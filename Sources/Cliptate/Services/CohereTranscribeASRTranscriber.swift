import CliptateCore
import AVFoundation
import Foundation
import MLX
import MLXAudioSTT

public final class CohereTranscribeASRTranscriber: @unchecked Sendable, Transcriber,
  ChunkTranscriber, StreamingASREngine
{
  private var cohereModel: CohereTranscribeModel?
  private let modelVariant: ModelVariant
  public var model: ModelVariant { modelVariant }
  private(set) var isModelReady: Bool = false

  public init(model: ModelVariant = .cohereTranscribe03FP16) {
    precondition(
      model.isCohereTranscribeModel,
      "CohereTranscribeASRTranscriber requires a Cohere model variant"
    )
    self.modelVariant = model
  }

  func unload() {
    cohereModel = nil
    isModelReady = false
  }

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    guard !isModelReady else { return }

    await MainActor.run {
      progressHandler(
        ModelDownloadProgress(
          currentStep: "Loading \(modelVariant.displayName)...",
          progress: 0.1
        )
      )
    }

    let model = try await CohereTranscribeModel.fromPretrained(modelVariant.huggingFaceRepoId)
    cohereModel = model
    isModelReady = true
    ModelArtifactStatusNotifier.postChange(for: modelVariant)

    await MainActor.run {
      progressHandler(
        ModelDownloadProgress(
          currentStep: "\(modelVariant.displayName) ready",
          progress: 1.0
        )
      )
    }
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try Task.checkCancellation()
    try validate(language: language)

    if !isModelReady {
      try await warmUpModelWithProgress { _ in }
    }

    guard cohereModel != nil else {
      throw NSError(
        domain: "CohereTranscribeASR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Model not initialized. Please warm up the model first."]
      )
    }

    let audioURL = URL(fileURLWithPath: audioPath)
    let needsStop = audioURL.startAccessingSecurityScopedResource()
    defer { if needsStop { audioURL.stopAccessingSecurityScopedResource() } }

    let audioDuration = max(try await readAudioDuration(from: audioURL), 0.001)
    await MainActor.run {
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.0,
          statusMessage: "Preparing audio...",
          estimatedTimeRemaining: audioDuration
        )
      )
    }

    let audioSamples = try await loadAudioSamples(from: audioURL)
    guard !audioSamples.isEmpty else {
      throw NSError(
        domain: "CohereTranscribeASR",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid audio data - empty audio"]
      )
    }

    try Task.checkCancellation()

    await MainActor.run {
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.35,
          statusMessage: "Running Cohere transcription...",
          estimatedTimeRemaining: nil
        )
      )
    }

    let startTime = Date()
    let result = try generate(samples: audioSamples, language: language, chunkDuration: 30.0)
    let segments = segments(from: result, audioDuration: audioDuration)
    let processingTime = Date().timeIntervalSince(startTime)

    await MainActor.run {
      progressHandler(
        TranscriptionProgress(
          currentSegments: segments,
          progress: 1.0,
          statusMessage: "Completed",
          estimatedTimeRemaining: 0
        )
      )
    }

    return TranscriptionResult(
      segments: segments,
      totalDuration: audioDuration,
      processingTime: processingTime,
      modelUsed: modelVariant.rawValue
    )
  }

  public func transcribeChunk(samples: [Float], language: Language) async throws -> String {
    try transcribeStreamingChunk(samples16k: samples, language: language, dictionaryContext: nil)
  }

  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String {
    _ = dictionaryContext
    try validate(language: language)

    guard isModelReady, cohereModel != nil else {
      throw NSError(
        domain: "CohereTranscribeASR",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Model not initialized. Warm up the model first."]
      )
    }

    guard !samples16k.isEmpty else { return "" }
    let output = try generate(
      samples: samples16k,
      language: language,
      chunkDuration: max(0.5, Float(samples16k.count) / 16_000.0)
    )
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func validate(language: Language) throws {
    guard modelVariant.supportedLanguages.contains(language) else {
      let supported = modelVariant.supportedLanguages
        .filter { $0 != .auto }
        .map(\.displayName)
        .joined(separator: ", ")
      throw NSError(
        domain: "CohereTranscribeASR",
        code: 4,
        userInfo: [
          NSLocalizedDescriptionKey:
            "\(modelVariant.displayName) does not support \(language.displayName). Supported languages: \(supported)."
        ]
      )
    }
  }

  private func readAudioDuration(from audioURL: URL) async throws -> TimeInterval {
    let asset = AVURLAsset(url: audioURL)
    let assetDuration = try await asset.load(.duration)
    return assetDuration.seconds
  }

  private func loadAudioSamples(from audioURL: URL) async throws -> [Float] {
    try await AudioProcessor.loadAndConvertAudio(url: audioURL)
  }

  private func generate(
    samples: [Float],
    language: Language,
    chunkDuration: Float
  ) throws -> STTOutput {
    guard let cohereModel else {
      throw NSError(
        domain: "CohereTranscribeASR",
        code: 5,
        userInfo: [NSLocalizedDescriptionKey: "ASR model not initialized."]
      )
    }

    let params = STTGenerateParameters(
      maxTokens: 448,
      temperature: 0.0,
      topP: 0.95,
      topK: 0,
      verbose: false,
      language: language.cohereLanguageName,
      chunkDuration: chunkDuration,
      minChunkDuration: 1.0
    )

    return cohereModel.generate(
      audio: MLXArray(samples),
      generationParameters: params
    )
  }

  private func segments(from result: STTOutput, audioDuration: TimeInterval) -> [Segment] {
    if let rawSegments = result.segments {
      let mappedSegments = rawSegments.compactMap { segmentDict -> Segment? in
        let text = (segmentDict["text"] as? String ?? "").trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return nil }

        let start = segmentDict["start"] as? Double ?? 0
        let end = segmentDict["end"] as? Double ?? audioDuration
        let confidence =
          segmentDict["confidence"] as? Float
          ?? (segmentDict["confidence"] as? Double).map(Float.init)

        return Segment(
          startTime: start,
          endTime: max(end, start),
          text: text,
          words: nil,
          confidence: confidence
        )
      }

      if !mappedSegments.isEmpty {
        return mappedSegments
      }
    }

    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    return [
      Segment(
        startTime: 0,
        endTime: audioDuration,
        text: text,
        words: nil,
        confidence: nil
      )
    ]
  }
}

private extension Language {
  var cohereLanguageName: String? {
    switch self {
    case .auto:
      return nil
    case .english:
      return "English"
    case .french:
      return "French"
    case .german:
      return "German"
    case .italian:
      return "Italian"
    case .spanish:
      return "Spanish"
    case .portuguese:
      return "Portuguese"
    case .greek:
      return "Greek"
    case .dutch:
      return "Dutch"
    case .polish:
      return "Polish"
    case .chinese:
      return "Chinese"
    case .japanese:
      return "Japanese"
    case .korean:
      return "Korean"
    case .vietnamese:
      return "Vietnamese"
    case .arabic:
      return "Arabic"
    default:
      return displayName
    }
  }
}
