import Foundation
import MLX
import MLXAudioSTT

/// Nemotron inference over 16 kHz mono samples with native sentence timing.
/// Batch alignment supplies word timing; live dictation uses shared VAD chunks.
public final class NemotronASRTranscriber: @unchecked Sendable, Transcriber,
  ChunkTranscriber, StreamingASREngine
{
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var model: NemotronASRModel?
    private var ready = false
    private var loading: Task<Void, Error>?

    func prepare(loader: @escaping @Sendable () async throws -> NemotronASRModel?) -> Task<Void, Error>? {
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

    func current() -> (model: NemotronASRModel?, ready: Bool) {
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
    var generate: @Sendable ([Float], String) throws -> STTOutput = { _, _ in STTOutput(text: "") }
  }

  public let model: ModelVariant
  private let state = State()
  // MLX decoding mutates attention caches; serialize callers sharing this resource.
  private let inferenceLock = NSLock()
  private let testHooks: TestHooks?
  private static let sampleRate = 16_000
  private static let windowSamples = 30 * sampleRate

  public init(model: ModelVariant = .nemotronASR358bit) {
    precondition(model.isNemotronASRModel)
    self.model = model
    testHooks = nil
  }

  init(model: ModelVariant = .nemotronASR358bit, testHooks: TestHooks) {
    precondition(model.isNemotronASRModel)
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
      return try NemotronASRModel.fromDirectory(directory)
    }
    guard let task else { return }
    await MainActor.run {
      progressHandler(ModelDownloadProgress(currentStep: String(localized: "Loading Nemotron ASR..."), progress: 0.1))
    }
    try await task.value
    try Task.checkCancellation()
    ModelArtifactStatusNotifier.postChange(for: model)
    await MainActor.run {
      progressHandler(ModelDownloadProgress(currentStep: String(localized: "Nemotron ASR ready"), progress: 1))
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
      let output = try generate(samples: Array(samples[start..<end]), language: language)
      segments.append(contentsOf: Self.segments(
        from: output, offset: Double(start) / Double(Self.sampleRate),
        duration: Double(end - start) / Double(Self.sampleRate)
      ))
      let update = TranscriptionProgress(
        currentSegments: segments, progress: Float(end) / Float(samples.count),
        statusMessage: String(localized: "Running Nemotron transcription..."),
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
    // Nemotron has language prompts, but no vocabulary biasing. Post-processing still
    // applies the configured dictionary in the shared transcription runtime.
    try validate(language)
    var texts: [String] = []
    for start in stride(from: 0, to: samples16k.count, by: Self.windowSamples) {
      let end = min(start + Self.windowSamples, samples16k.count)
      let text = try generate(samples: Array(samples16k[start..<end]), language: language)
        .text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { texts.append(text) }
    }
    try Task.checkCancellation()
    return texts.joined(separator: " ")
  }

  private func validate(_ language: Language) throws {
    guard model.supportedLanguages.contains(language) else {
      throw NSError(domain: "NemotronASR", code: 1, userInfo: [
        NSLocalizedDescriptionKey: String(localized: "Nemotron ASR requires a language supported by the selected checkpoint.")
      ])
    }
  }

  private func generate(samples: [Float], language: Language) throws -> STTOutput {
    try Task.checkCancellation()
    let output: STTOutput = try inferenceLock.withLock {
      let current = state.current()
      guard current.ready else {
        throw NSError(domain: "NemotronASR", code: 2, userInfo: [
          NSLocalizedDescriptionKey: String(localized: "Model not initialized. Warm up the model first.")
        ])
      }
      if let testHooks { return try testHooks.generate(samples, language.nemotronLanguageCode) }
      guard let model = current.model else {
        throw NSError(domain: "NemotronASR", code: 2)
      }
      return model.generate(
        audio: MLXArray(samples),
        generationParameters: STTGenerateParameters(temperature: 0, language: language.nemotronLanguageCode, chunkDuration: 30)
      )
    }
    try Task.checkCancellation()
    return output
  }

  private static func segments(from output: STTOutput, offset: Double, duration: Double) -> [Segment] {
    let segments = (output.segments ?? []).compactMap { raw -> Segment? in
      let text = (raw["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, let start = raw["start"] as? Double,
        let end = raw["end"] as? Double, start.isFinite, end.isFinite, end >= start
      else { return nil }
      let clippedStart = min(duration, max(0, start))
      let clippedEnd = min(duration, max(clippedStart, end))
      return Segment(startTime: offset + clippedStart, endTime: offset + clippedEnd, text: text)
    }
    if !segments.isEmpty { return segments }
    let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? [] : [Segment(startTime: offset, endTime: offset + duration, text: text)]
  }
}

extension Language {
  /// Use advertised, out-of-box language locales. Unknown prompt keys silently
  /// fall back to auto upstream, so callers validate model.supportedLanguages first.
  var nemotronLanguageCode: String {
    switch self {
    case .auto: return "auto"
    case .english: return "en-US"
    case .spanish: return "es-ES"
    case .french: return "fr-FR"
    case .italian: return "it-IT"
    case .portuguese: return "pt-PT"
    case .dutch: return "nl-NL"
    case .german: return "de-DE"
    case .turkish: return "tr-TR"
    case .russian: return "ru-RU"
    case .arabic: return "ar-AR"
    case .hindi: return "hi-IN"
    case .japanese: return "ja-JP"
    case .korean: return "ko-KR"
    case .vietnamese: return "vi-VN"
    case .ukrainian: return "uk-UA"
    case .polish: return "pl-PL"
    case .swedish: return "sv-SE"
    case .czech: return "cs-CZ"
    case .norwegian: return "nb-NO"
    case .danish: return "da-DK"
    case .bulgarian: return "bg-BG"
    case .finnish: return "fi-FI"
    case .croatian: return "hr-HR"
    case .slovak: return "sk-SK"
    case .chinese: return "zh-CN"
    case .hungarian: return "hu-HU"
    case .romanian: return "ro-RO"
    case .estonian: return "et-EE"
    default: return rawValue
    }
  }
}
