import CliptateCore
import AVFoundation
import Foundation
import MLX
import MLXAudioSTT

public final class FireRedASRTranscriber: @unchecked Sendable, Transcriber, StreamingASREngine {
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var fireRedModel: FireRedASR2Model?
    private var isModelReady = false
    private var activeWarmUpTask: Task<Void, Error>?

    func prepareWarmUpTask(
      loader: @escaping @Sendable () async throws -> FireRedASR2Model?
    ) -> (task: Task<Void, Error>?, shouldReportProgress: Bool) {
      lock.lock()
      defer { lock.unlock() }

      if isModelReady {
        return (nil, false)
      }

      if let activeWarmUpTask {
        return (activeWarmUpTask, false)
      }

      let task = Task {
        do {
          let model = try await loader()
          self.finishWarmUp(model: model)
        } catch {
          self.failWarmUp()
          throw error
        }
      }

      activeWarmUpTask = task
      return (task, true)
    }

    func finishWarmUp(model: FireRedASR2Model?) {
      lock.lock()
      fireRedModel = model
      isModelReady = true
      activeWarmUpTask = nil
      lock.unlock()
    }

    func failWarmUp() {
      lock.lock()
      activeWarmUpTask = nil
      lock.unlock()
    }

    func isReady() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return isModelReady
    }

    func currentModel() -> FireRedASR2Model? {
      lock.lock()
      defer { lock.unlock() }
      return fireRedModel
    }
  }

  struct GenerationRequest: @unchecked Sendable {
    let audio: [Float]
    let language: String?
  }

  struct TestHooks: Sendable {
    let loadAudioSamples: (@Sendable (URL) async throws -> [Float])?
    let readAudioDuration: (@Sendable (URL) async throws -> TimeInterval)?
    let loadModel: (@Sendable (String) async throws -> Void)?
    let generate: (@Sendable (GenerationRequest) throws -> STTOutput)?

    init(
      loadAudioSamples: (@Sendable (URL) async throws -> [Float])? = nil,
      readAudioDuration: (@Sendable (URL) async throws -> TimeInterval)? = nil,
      loadModel: (@Sendable (String) async throws -> Void)? = nil,
      generate: (@Sendable (GenerationRequest) throws -> STTOutput)? = nil
    ) {
      self.loadAudioSamples = loadAudioSamples
      self.readAudioDuration = readAudioDuration
      self.loadModel = loadModel
      self.generate = generate
    }

    actor LoadCapture {
      private var requestedRepoIDs: [String] = []

      func recordLoad(repoID: String) async throws {
        requestedRepoIDs.append(repoID)
      }

      func snapshot() -> [String] {
        requestedRepoIDs
      }
    }
  }

  private let modelVariant: ModelVariant
  private let state = State()
  private let testHooks: TestHooks?

  public var model: ModelVariant { modelVariant }

  public init(model: ModelVariant = .fireRedASR2) {
    precondition(model.isFireRedASRModel, "FireRedASRTranscriber requires a FireRed ASR model variant")
    self.modelVariant = model
    self.testHooks = nil
  }

  init(model: ModelVariant, testHooks: TestHooks) {
    precondition(model.isFireRedASRModel, "FireRedASRTranscriber requires a FireRed ASR model variant")
    self.modelVariant = model
    self.testHooks = testHooks
  }

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    let loadTask = state.prepareWarmUpTask { [modelVariant, testHooks] in
      if let loadModel = testHooks?.loadModel {
        try await loadModel(modelVariant.huggingFaceRepoId)
        return nil
      }

      return try await FireRedASR2Model.fromPretrained(modelVariant.huggingFaceRepoId)
    }

    guard let task = loadTask.task else {
      return
    }

    if loadTask.shouldReportProgress {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Loading \(modelVariant.displayName)...",
            progress: 0.1
          )
        )
      }
    }

    try await task.value

    if loadTask.shouldReportProgress {
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
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    guard modelVariant.supportedLanguages.contains(language) || language == .auto else {
      let supportedLangs = modelVariant.supportedLanguages.map(\.displayName).joined(separator: ", ")
      throw NSError(
        domain: "FireRedASR",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "\(modelVariant.displayName) does not support \(language.displayName). Supported languages: \(supportedLangs)."
        ]
      )
    }

    if !state.isReady() {
      try await warmUpModelWithProgress { _ in }
    }

    guard state.currentModel() != nil || testHooks?.generate != nil else {
      throw NSError(
        domain: "FireRedASR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Model not initialized. Please warm up the model first."]
      )
    }

    let startTime = Date()
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
        domain: "FireRedASR",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Invalid audio data - empty audio"]
      )
    }

    await MainActor.run {
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.3,
          statusMessage: "Running FireRed transcription...",
          estimatedTimeRemaining: nil
        )
      )
    }

    let result = try await generate(
      request: GenerationRequest(
        audio: audioSamples,
        language: language.fireRedLanguageName
      )
    )

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

  private func generate(request: GenerationRequest) async throws -> STTOutput {
    if let generate = testHooks?.generate {
      return try generate(request)
    }

    guard let fireRedModel = state.currentModel() else {
      throw NSError(
        domain: "FireRedASR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "ASR model not initialized."]
      )
    }

    return fireRedModel.generate(
      audio: MLXArray(request.audio),
      language: request.language
    )
  }

  // MARK: - StreamingASREngine

  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String {
    guard !samples16k.isEmpty else { return "" }

    if let generate = testHooks?.generate {
      let request = GenerationRequest(audio: samples16k, language: language.fireRedLanguageName)
      let output = try generate(request)
      return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let fireRedModel = state.currentModel() else {
      throw NSError(
        domain: "FireRedASR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Model not initialized. Warm up the model first."]
      )
    }

    let output = fireRedModel.generate(
      audio: MLXArray(samples16k),
      language: language.fireRedLanguageName
    )
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let confidence = segmentDict["confidence"] as? Float ?? (segmentDict["confidence"] as? Double).map(Float.init)

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
  var fireRedLanguageName: String? {
    switch self {
    case .auto:
      return nil
    case .chinese:
      return "Chinese"
    case .english:
      return "English"
    default:
      return displayName
    }
  }
}
