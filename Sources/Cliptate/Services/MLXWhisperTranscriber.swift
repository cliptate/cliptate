import Foundation
import MLX
import MLXAudioSTT

/// Whisper inference over 16 kHz mono samples. Timing describes whole windows;
/// the batch runtime supplies VAD and optional forced alignment for precise edits.
public final class MLXWhisperTranscriber: @unchecked Sendable, Transcriber,
  ChunkTranscriber, StreamingASREngine
{
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var model: WhisperModel?
    private var ready = false
    private var loading: Task<Void, Error>?

    func prepare(loader: @escaping @Sendable () async throws -> WhisperModel?) -> Task<Void, Error>? {
      lock.withLock {
        if ready { return nil }
        if let loading { return loading }
        let task = Task {
          do {
            let model = try await loader()
            self.lock.withLock {
              self.model = model
              self.ready = true
              self.loading = nil
            }
          } catch {
            self.lock.withLock { self.loading = nil }
            throw error
          }
        }
        loading = task
        return task
      }
    }

    func current() -> (model: WhisperModel?, ready: Bool) {
      lock.withLock { (model, ready) }
    }

    func unload() {
      lock.withLock {
        model = nil
        ready = false
      }
    }
  }

  struct TestHooks: Sendable {
    var loadModel: @Sendable (String) async throws -> Void
    var loadAudio: @Sendable (URL) async throws -> [Float] = { _ in [] }
    var generate: @Sendable ([Float], String) throws -> String = { _, _ in "" }
  }

  public let model: ModelVariant
  private let state = State()
  // MLX decoding mutates attention caches; serialize callers sharing this resource.
  private let inferenceLock = NSLock()
  private let testHooks: TestHooks?
  private static let sampleRate = 16_000
  private static let windowSamples = 30 * sampleRate

  public init(model: ModelVariant = .whisperLargeV3Turbo) {
    precondition(model.isWhisperModel)
    self.model = model
    testHooks = nil
  }

  init(model: ModelVariant = .whisperLargeV3Turbo, testHooks: TestHooks) {
    precondition(model.isWhisperModel)
    self.model = model
    self.testHooks = testHooks
  }

  func unload() {
    inferenceLock.withLock { state.unload() }
  }

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    try Task.checkCancellation()
    let task = state.prepare { [model, testHooks] in
      if let testHooks {
        try await testHooks.loadModel(model.huggingFaceRepoId)
        return nil
      }
      let downloads = ModelDownloadManager.shared
      try await downloads.download(model: model) { _ in }
      try Task.checkCancellation()
      guard let directory = await downloads.getModelDirectory(for: model) else {
        throw ModelPreparationError.modelNotDownloaded(model)
      }
      return try await WhisperModel.fromDirectory(directory)
    }
    guard let task else { return }
    await MainActor.run {
      progressHandler(ModelDownloadProgress(currentStep: String(localized: "Loading Whisper..."), progress: 0.1))
    }
    try await task.value
    try Task.checkCancellation()
    ModelArtifactStatusNotifier.postChange(for: model)
    await MainActor.run {
      progressHandler(ModelDownloadProgress(currentStep: String(localized: "Whisper ready"), progress: 1))
    }
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try validate(language)
    try Task.checkCancellation()
    let started = Date()
    let url = URL(fileURLWithPath: audioPath)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let samples: [Float]
    if let testHooks {
      samples = try await testHooks.loadAudio(url)
    } else {
      samples = try await AudioProcessor.loadAndConvertAudio(url: url)
    }
    try await warmUpModelWithProgress { _ in }
    var segments: [Segment] = []
    for start in stride(from: 0, to: samples.count, by: Self.windowSamples) {
      try Task.checkCancellation()
      let end = min(start + Self.windowSamples, samples.count)
      let text = try generate(samples: Array(samples[start..<end]), language: language)
      if !text.isEmpty {
        segments.append(Segment(
          startTime: Double(start) / Double(Self.sampleRate),
          endTime: Double(end) / Double(Self.sampleRate), text: text
        ))
      }
      let update = TranscriptionProgress(
        currentSegments: segments, progress: Float(end) / Float(samples.count),
        statusMessage: String(localized: "Running Whisper transcription..."),
        estimatedTimeRemaining: nil
      )
      await MainActor.run { progressHandler(update) }
    }
    try Task.checkCancellation()
    let completed = TranscriptionProgress(
      currentSegments: segments, progress: 1, statusMessage: String(localized: "Completed"),
      estimatedTimeRemaining: 0
    )
    await MainActor.run { progressHandler(completed) }
    return TranscriptionResult(
      segments: segments, totalDuration: Double(samples.count) / Double(Self.sampleRate),
      processingTime: Date().timeIntervalSince(started), modelUsed: model.rawValue
    )
  }

  public func transcribeChunk(samples: [Float], language: Language) async throws -> String {
    try transcribeStreamingChunk(samples16k: samples, language: language, dictionaryContext: nil)
  }

  func transcribeStreamingChunk(
    samples16k: [Float], language: Language, dictionaryContext: String?
  ) throws -> String {
    // Upstream Whisper has no vocabulary-prompt support. Post-processing still
    // applies the configured dictionary in the shared transcription runtime.
    try validate(language)
    var texts: [String] = []
    for start in stride(from: 0, to: samples16k.count, by: Self.windowSamples) {
      let end = min(start + Self.windowSamples, samples16k.count)
      let text = try generate(samples: Array(samples16k[start..<end]), language: language)
      if !text.isEmpty { texts.append(text) }
    }
    try Task.checkCancellation()
    return texts.joined(separator: " ")
  }

  private func validate(_ language: Language) throws {
    guard model.supportedLanguages.contains(language) else {
      throw NSError(domain: "MLXWhisper", code: 1, userInfo: [
        NSLocalizedDescriptionKey: String(localized: "Whisper requires a supported, explicitly selected language.")
      ])
    }
  }

  private func generate(samples: [Float], language: Language) throws -> String {
    try Task.checkCancellation()
    let text: String = try inferenceLock.withLock {
      let current = state.current()
      guard current.ready else {
        throw NSError(domain: "MLXWhisper", code: 2, userInfo: [
          NSLocalizedDescriptionKey: String(localized: "Model not initialized. Warm up the model first.")
        ])
      }
      if let testHooks { return try testHooks.generate(samples, language.rawValue) }
      guard let model = current.model else {
        throw NSError(domain: "MLXWhisper", code: 2)
      }
      return model.generate(
        audio: MLXArray(samples),
        generationParameters: STTGenerateParameters(maxTokens: 448, temperature: 0, language: language.rawValue)
      ).text
    }
    try Task.checkCancellation()
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
