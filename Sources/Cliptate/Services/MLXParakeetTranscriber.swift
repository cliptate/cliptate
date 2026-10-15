import CliptateCore
import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import os.log

/// Transcriber using mlx-audio-swift's ParakeetModel.
/// File-based transcription accepts an explicit VAD model so segmentation and
/// optional diarization stay owned by the calling workflow instead of being
/// hard-wired into the ASR model itself.
public final class MLXParakeetTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber,
  StreamingASREngine
{

  private var parakeetModel: ParakeetModel?
  private let modelVariant: ModelVariant
  public var model: ModelVariant { modelVariant }
  private(set) var isModelReady: Bool = false
  private let testHooks: TestHooks?

  private let logger = Logger(
    subsystem: "com.cliptate.app", category: "MLXParakeetTranscriber")

  struct TestHooks: Sendable {
    let loadAudioSamples: (@Sendable (URL) async throws -> [Float])?
    let readAudioDuration: (@Sendable (URL) async throws -> TimeInterval)?
    let generateText: (@Sendable ([Float]) throws -> String)?
    let detectSegments: (@Sendable ([Float], TimeInterval, ModelVariant) async throws -> (
      vadRanges: [AudioTimeRange], speakerRanges: [AudioTimeRange]))?

    init(
      loadAudioSamples: (@Sendable (URL) async throws -> [Float])? = nil,
      readAudioDuration: (@Sendable (URL) async throws -> TimeInterval)? = nil,
      generateText: (@Sendable ([Float]) throws -> String)? = nil,
      detectSegments: (@Sendable ([Float], TimeInterval, ModelVariant) async throws -> (
        vadRanges: [AudioTimeRange], speakerRanges: [AudioTimeRange]))? = nil
    ) {
      self.loadAudioSamples = loadAudioSamples
      self.readAudioDuration = readAudioDuration
      self.generateText = generateText
      self.detectSegments = detectSegments
    }
  }

  private var hasInjectedGenerateHook: Bool {
    testHooks?.generateText != nil
  }

  public init(model: ModelVariant = .parakeetV3) {
    precondition(model.isParakeetModel, "MLXParakeetTranscriber requires a Parakeet model variant")
    self.modelVariant = model
    self.testHooks = nil
  }

  init(model: ModelVariant, testHooks: TestHooks) {
    precondition(model.isParakeetModel, "MLXParakeetTranscriber requires a Parakeet model variant")
    self.modelVariant = model
    self.testHooks = testHooks
  }

  // MARK: - Lifecycle

  /// Releases the loaded model from memory. Call before discarding the transcriber.
  func unload() {
    parakeetModel = nil
    isModelReady = false
  }

  // MARK: - Transcriber Protocol

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    guard !isModelReady else { return }

    if hasInjectedGenerateHook {
      isModelReady = true
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "\(modelVariant.displayName) ready",
            progress: 1.0
          ))
      }
      return
    }

    let startTime = Date()
    let modelName = modelVariant.displayName

    do {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Loading \(modelName) from HuggingFace...",
            progress: 0.1
          ))
      }

      let repoId = modelVariant.huggingFaceRepoId
      let model = try await ParakeetModel.fromPretrained(repoId)
      parakeetModel = model

      isModelReady = true
      ModelArtifactStatusNotifier.postChange(for: modelVariant)
      let totalTime = Date().timeIntervalSince(startTime)

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "\(modelName) ready (\(String(format: "%.1f", totalTime))s)",
            progress: 1.0
          ))
      }

      logger.notice(
        "MLXParakeet (\(modelName)) loaded in \(String(format: "%.1f", totalTime))s")

    } catch {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Failed to load \(modelName): \(error.localizedDescription)",
            progress: 0.0
          ))
      }
      logger.error("MLXParakeet load failed: \(error.localizedDescription)")
      throw error
    }
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try await transcribeWithProgress(
      audioPath: audioPath,
      language: language,
      vadModel: .sortformerStreaming,
      progressHandler: progressHandler
    )
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    vadModel: ModelVariant,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try Task.checkCancellation()

    guard parakeetModel != nil || hasInjectedGenerateHook else {
      throw NSError(
        domain: "VoiceFlow", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "MLX Parakeet model not initialized. Call warmUpModelWithProgress first."
        ])
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
          statusMessage: "Loading audio...",
          estimatedTimeRemaining: audioDuration
        ))
    }

    let audioSamples = try await loadAudioSamples(from: audioURL)

    guard !audioSamples.isEmpty else {
      throw NSError(
        domain: "VoiceFlow", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Audio is empty."])
    }

    try Task.checkCancellation()

    let (vadRanges, speakerRanges) = try await detectSegments(
      for: audioSamples,
      audioDuration: audioDuration,
      vadModel: vadModel
    )

    let segmentsToProcess: [AudioTimeRange] =
      vadRanges.isEmpty
      ? [AudioTimeRange(startTime: 0, endTime: audioDuration)]
      : vadRanges

    await MainActor.run {
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.1,
          statusMessage:
            vadRanges.isEmpty
            ? "No speech detected via VAD, processing full audio..."
            : "Detected \(vadRanges.count) speech segments, transcribing...",
          estimatedTimeRemaining: audioDuration
        ))
    }

    let startTime = Date()
    var aggregatedSegments: [Segment] = []

    let params = STTGenerateParameters(
      maxTokens: 448, temperature: 0.0, topP: 0.95, topK: 0, verbose: false)

    for (index, range) in segmentsToProcess.enumerated() {
      try Task.checkCancellation()

      let chunkSamples = extractSamples(
        from: audioSamples, startTime: range.startTime, endTime: range.endTime)
      guard !chunkSamples.isEmpty else { continue }

      let text = try transcribeChunkSamples(chunkSamples, params: params)
      guard !text.isEmpty else { continue }

      aggregatedSegments.append(
        Segment(
          startTime: range.startTime,
          endTime: range.endTime,
          text: text,
          words: nil,
          speakerId: nil
        ))

      aggregatedSegments.sort { $0.startTime < $1.startTime }
      let segProgress = min(range.endTime / audioDuration, 0.98)
      let snapshot = aggregatedSegments

      await MainActor.run {
        progressHandler(
          TranscriptionProgress(
            currentSegments: snapshot,
            progress: Float(segProgress),
            statusMessage:
              "Transcribing segment \(index + 1)/\(segmentsToProcess.count)...",
            estimatedTimeRemaining: calculateEstimatedTime(
              startTime: startTime,
              currentProgress: Float(segProgress),
              targetProgress: 0.98
            )
          ))
      }
    }

    guard !aggregatedSegments.isEmpty else {
      throw NSError(
        domain: "VoiceFlow", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "Transcription completed but no speech segments found."
        ])
    }

    let finalSegments =
      speakerRanges.isEmpty
      ? aggregatedSegments
      : SegmentSpeakerAnnotator.annotate(aggregatedSegments, withSpeakers: speakerRanges)

    let processingTime = Date().timeIntervalSince(startTime)

    await MainActor.run {
      progressHandler(
        TranscriptionProgress(
          currentSegments: finalSegments,
          progress: 1.0,
          statusMessage: "Completed",
          estimatedTimeRemaining: 0
        ))
    }

    return TranscriptionResult(
      segments: finalSegments,
      totalDuration: audioDuration,
      processingTime: processingTime,
      modelUsed: modelVariant.rawValue
    )
  }

  // MARK: - ChunkTranscriber

  public func transcribeChunk(samples: [Float], language: Language) async throws -> String {
    guard parakeetModel != nil || hasInjectedGenerateHook else {
      throw NSError(
        domain: "VoiceFlow", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "MLX Parakeet model not initialized. Call warmUpModelWithProgress first."
        ])
    }

    guard !samples.isEmpty else { return "" }

    let params = STTGenerateParameters(
      maxTokens: 448, temperature: 0.0, topP: 0.95, topK: 0, verbose: false)
    return try transcribeChunkSamples(samples, params: params)
  }

  // MARK: - Helpers

  private func extractSamples(from samples: [Float], startTime: Double, endTime: Double) -> [Float] {
    guard endTime > startTime else { return [] }
    let sampleRate = 16_000.0
    let start = max(0, Int(startTime * sampleRate))
    let end = min(samples.count, Int(endTime * sampleRate))
    guard end > start else { return [] }
    return Array(samples[start..<end])
  }

  private func readAudioDuration(from audioURL: URL) async throws -> TimeInterval {
    if let readAudioDuration = testHooks?.readAudioDuration {
      return try await readAudioDuration(audioURL)
    }
    let asset = AVURLAsset(url: audioURL)
    let assetDuration = try await asset.load(.duration)
    return assetDuration.seconds
  }

  private func loadAudioSamples(from audioURL: URL) async throws -> [Float] {
    if let loadAudioSamples = testHooks?.loadAudioSamples {
      return try await loadAudioSamples(audioURL)
    }
    return try await AudioProcessor.loadAndConvertAudio(url: audioURL)
  }

  private func detectSegments(
    for audioSamples: [Float],
    audioDuration: TimeInterval,
    vadModel: ModelVariant
  ) async throws -> (vadRanges: [AudioTimeRange], speakerRanges: [AudioTimeRange]) {
    if let detectSegments = testHooks?.detectSegments {
      return try await detectSegments(audioSamples, audioDuration, vadModel)
    }

    if vadModel.isSortformerVADModel {
      let segmenter = try await ModelCacheManager.shared.getVADSegmenter(model: vadModel)
      let result = try await segmenter.detectAllSpeechSegments(audioSamples: audioSamples)
      return (vadRanges: result.merged, speakerRanges: result.withSpeakers)
    }

    if vadModel.isSileroVADModel {
      let segmenter = try await ModelCacheManager.shared.getSileroVADSegmenter(model: vadModel)
      let vadRanges = try segmenter.detectSpeechSegments(audioSamples: audioSamples)
      return (vadRanges, [])
    }

    return ([AudioTimeRange(startTime: 0, endTime: audioDuration)], [])
  }

  private func transcribeChunkSamples(
    _ chunkSamples: [Float],
    params: STTGenerateParameters
  ) throws -> String {
    if let generateText = testHooks?.generateText {
      return try generateText(chunkSamples).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let parakeetModel else {
      throw NSError(
        domain: "VoiceFlow", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "MLX Parakeet model not initialized. Call warmUpModelWithProgress first."
        ])
    }

    let audioArray = MLXArray(chunkSamples)
    let output = parakeetModel.generate(audio: audioArray, generationParameters: params)
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - StreamingASREngine

  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String {
    guard parakeetModel != nil || hasInjectedGenerateHook else {
      throw NSError(
        domain: "VoiceFlow", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "MLX Parakeet model not initialized. Call warmUpModelWithProgress first."
        ])
    }
    guard !samples16k.isEmpty else { return "" }
    let params = STTGenerateParameters(
      maxTokens: 448, temperature: 0.0, topP: 0.95, topK: 0, verbose: false)
    return try transcribeChunkSamples(samples16k, params: params)
  }

  private func calculateEstimatedTime(
    startTime: Date, currentProgress: Float, targetProgress: Float
  ) -> TimeInterval? {
    guard currentProgress > 0.01 else { return nil }
    let elapsed = Date().timeIntervalSince(startTime)
    let rate = Double(currentProgress) / elapsed
    guard rate > 0 else { return nil }
    return Double(targetProgress - currentProgress) / rate
  }
}
