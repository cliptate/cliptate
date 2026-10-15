import CliptateCore
import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import os.log

/// Transcriber implementation for Qwen3 ASR models using MLX.
public final class Qwen3ASRTranscriber: @unchecked Sendable, Transcriber, ChunkTranscriber, StreamingASREngine {
  private static let alignmentChunkDuration: Float = 3.0
  private var asrModel: Qwen3ASRModel?
  private let modelVariant: ModelVariant
  private var isModelReady: Bool = false
  private let testHooks: TestHooks?

  /// The model variant this transcriber was initialized with
  public var model: ModelVariant { modelVariant }

  private let logger = Logger(subsystem: "com.cliptate.app", category: "Qwen3ASRTranscriber")

  struct GenerationRequest: @unchecked Sendable {
    let audio: [Float]
    let language: String?
    let chunkDuration: Float
    let minChunkDuration: Float
    let context: String

    init(
      audio: [Float],
      language: String?,
      chunkDuration: Float,
      minChunkDuration: Float,
      context: String
    ) {
      self.audio = audio
      self.language = language
      self.chunkDuration = chunkDuration
      self.minChunkDuration = minChunkDuration
      self.context = context
    }
  }

  struct TestHooks: Sendable {
    let loadAudioSamples: (@Sendable (URL) async throws -> [Float])?
    let readAudioDuration: (@Sendable (URL) async throws -> TimeInterval)?
    let generate: (@Sendable (GenerationRequest) throws -> STTOutput)?

    init(
      loadAudioSamples: (@Sendable (URL) async throws -> [Float])? = nil,
      readAudioDuration: (@Sendable (URL) async throws -> TimeInterval)? = nil,
      generate: (@Sendable (GenerationRequest) throws -> STTOutput)? = nil
    ) {
      self.loadAudioSamples = loadAudioSamples
      self.readAudioDuration = readAudioDuration
      self.generate = generate
    }

    final class GenerateCapture: @unchecked Sendable {
      struct RecordedRequest: Sendable {
        let language: String?
        let chunkDuration: Float
        let minChunkDuration: Float
        let context: String

        init(_ request: GenerationRequest) {
          self.language = request.language
          self.chunkDuration = request.chunkDuration
          self.minChunkDuration = request.minChunkDuration
          self.context = request.context
        }
      }

      private let lock = NSLock()
      private var lastRequest: RecordedRequest?
      var output: STTOutput

      init(
        output: STTOutput = STTOutput(
          text: "sysulq whispercut",
          segments: [["text": "sysulq whispercut", "start": 0.0, "end": 1.0]]
        )
      ) {
        self.output = output
      }

      var last: RecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequest
      }

      func record(_ request: GenerationRequest) -> STTOutput {
        lock.lock()
        lastRequest = RecordedRequest(request)
        let output = self.output
        lock.unlock()
        return output
      }
    }
  }

  private var hasInjectedGenerateHook: Bool {
    testHooks?.generate != nil
  }

  /// Initialize the transcriber with a specific Qwen3 model variant
  /// - Parameter model: The model variant to use (.qwen3ASR or .qwen3ForcedAligner)
  public init(model: ModelVariant = .qwen3ASR) {
    self.modelVariant = model
    self.testHooks = nil
    logger.notice("🤖 Qwen3ASRTranscriber initialized with model: \(model.rawValue)")
  }

  init(model: ModelVariant, testHooks: TestHooks) {
    self.modelVariant = model
    self.testHooks = testHooks
    logger.notice("🤖 Qwen3ASRTranscriber initialized with model: \(model.rawValue)")
  }

  /// Transcribes a streaming chunk that has already been normalized to 16kHz mono samples.
  /// Reuses the warmed ASR model instance managed by this transcriber.
  public func transcribeStreamingChunk(samples16k: [Float], language: Language) throws -> String {
    try transcribeStreamingChunk(
      samples16k: samples16k,
      language: language,
      dictionaryContext: nil
    )
  }

  public func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String? = nil
  ) throws -> String {
    guard modelVariant.isQwen3ASRModel else {
      throw NSError(
        domain: "Qwen3ASR", code: 6,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Streaming chunk transcription requires a Qwen3 ASR model. Current model: \(modelVariant.displayName)."
        ])
    }

    guard isModelReady || hasInjectedGenerateHook else {
      throw NSError(
        domain: "Qwen3ASR", code: 7,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Model not initialized for streaming. Warm up the model before transcription."
        ])
    }

    guard !samples16k.isEmpty else { return "" }

    let chunkDuration = max(0.5, Float(samples16k.count) / 16_000.0)
    let request = GenerationRequest(
      audio: samples16k,
      language: language.qwen3LanguageName,
      chunkDuration: chunkDuration,
      minChunkDuration: 1.0,
      context: dictionaryContext ?? ""
    )
    let result = try generate(request: request)
    return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Lifecycle

  /// Releases loaded model weights from memory. Call before discarding the transcriber.
  func unload() {
    asrModel = nil
    isModelReady = false
  }

  // MARK: ChunkTranscriber

  public func transcribeChunk(samples: [Float], language: Language) async throws -> String {
    try await transcribeChunk(
      samples: samples,
      language: language,
      dictionaryContext: nil
    )
  }

  public func transcribeChunk(
    samples: [Float],
    language: Language,
    dictionaryContext: String? = nil
  ) async throws -> String {
    try transcribeStreamingChunk(
      samples16k: samples,
      language: language,
      dictionaryContext: dictionaryContext
    )
  }

  // MARK: - Transcriber Protocol

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    if isModelReady {
      return
    }

    let startTime = Date()
    let modelName = modelVariant.displayName

    do {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Checking \(modelName) availability...",
            progress: 0.05
          ))
      }

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Loading \(modelName) from HuggingFace...",
            progress: 0.2
          ))
      }

      // Ensure merges.txt exists (mlx-audio only downloads *.safetensors and *.json)
      try await ensureMergesFile(for: modelVariant)

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Initializing Qwen3 ASR model...",
            progress: 0.4
          ))
      }

      let model = try await Qwen3ASRModel.fromPretrained(
        modelVariant.huggingFaceRepoId
      )
      asrModel = model

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Model weights loaded, preparing for inference...",
            progress: 0.7
          ))
      }

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

      logger.notice("🤖 Qwen3 model loaded successfully in \(String(format: "%.1f", totalTime))s")

    } catch {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Failed to load \(modelName): \(error.localizedDescription)",
            progress: 0.0
          ))
      }
      logger.error("🤖 Failed to load Qwen3 model: \(error.localizedDescription)")
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
      dictionaryContext: nil,
      progressHandler: progressHandler
    )
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    dictionaryContext: String? = nil,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try await transcribeWithProgressInternal(
      audioPath: audioPath,
      language: language,
      chunkDuration: nil,
      dictionaryContext: dictionaryContext,
      progressHandler: progressHandler
    )
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    chunkDuration: Float,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try await transcribeWithProgress(
      audioPath: audioPath,
      language: language,
      chunkDuration: chunkDuration,
      dictionaryContext: nil,
      progressHandler: progressHandler
    )
  }

  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    chunkDuration: Float,
    dictionaryContext: String? = nil,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try await transcribeWithProgressInternal(
      audioPath: audioPath,
      language: language,
      chunkDuration: chunkDuration,
      dictionaryContext: dictionaryContext,
      progressHandler: progressHandler
    )
  }

  private func transcribeWithProgressInternal(
    audioPath: String,
    language: Language,
    chunkDuration: Float?,
    dictionaryContext: String?,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try Task.checkCancellation()

    // Validate language is supported
    guard modelVariant.supportedLanguages.contains(language) || language == .auto else {
      let supportedLangs = modelVariant.supportedLanguages.map { $0.displayName }.joined(
        separator: ", ")
      throw NSError(
        domain: "Qwen3ASR", code: 4,
        userInfo: [
          NSLocalizedDescriptionKey:
            "\(modelVariant.displayName) does not support \(language.displayName). Supported languages: \(supportedLangs)."
        ])
    }

    // Ensure model is loaded
    if !isModelReady {
      if hasInjectedGenerateHook {
        isModelReady = true
      } else {
        try await warmUpModelWithProgress { _ in }
      }
    }

    guard asrModel != nil || hasInjectedGenerateHook else {
      throw NSError(
        domain: "Qwen3ASR", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Model not initialized. Please warm up the model first."
        ])
    }

    let startTime = Date()
    let audioURL = URL(fileURLWithPath: audioPath)

    // Access security scoped resource
    let needsStop = audioURL.startAccessingSecurityScopedResource()
    defer { if needsStop { audioURL.stopAccessingSecurityScopedResource() } }

    let audioDuration = max(try await readAudioDuration(from: audioURL), 0.001)

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [], progress: 0.0, statusMessage: "Preparing audio...",
          estimatedTimeRemaining: audioDuration))
    }

    try Task.checkCancellation()

    // Load and convert audio to float samples at 16kHz
    let audioSamples = try await loadAudioSamples(from: audioURL)
    try Task.checkCancellation()

    guard !audioSamples.isEmpty else {
      logger.notice("🤖 Audio is empty, skipping transcription.")
      throw NSError(
        domain: "Qwen3ASR", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid audio data - empty audio"])
    }

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.2,
          statusMessage: "Starting transcription...",
          estimatedTimeRemaining: nil
        ))
    }

    // Convert to MLXArray for Qwen3 model
    let languageName = language.qwen3LanguageName

    logger.notice("🤖 Starting Qwen3 transcription with language: \(languageName)")

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.3,
          statusMessage: "Running transcription model...",
          estimatedTimeRemaining: nil
        ))
    }

    var segments: [Segment] = []

    if asrModel != nil || hasInjectedGenerateHook {
      // Normal ASR transcription
      let effectiveChunkDuration = max(0.5, chunkDuration ?? 1200.0)
      let request = GenerationRequest(
        audio: audioSamples,
        language: languageName,
        chunkDuration: effectiveChunkDuration,
        minChunkDuration: 1.0,
        context: dictionaryContext ?? ""
      )
      let result = try generate(request: request)

      Task { @MainActor in
        progressHandler(
          TranscriptionProgress(
            currentSegments: [],
            progress: 0.7,
            statusMessage: "Processing transcription results...",
            estimatedTimeRemaining: nil
          ))
      }

      // Convert Qwen3 segments to our Segment type
      // STTOutput.segments is [[String: Any]]? with keys: "text", "start", "end"
      if let qwenSegments = result.segments {
        segments = qwenSegments.compactMap { segmentDict -> Segment? in
          guard let text = segmentDict["text"] as? String,
                let start = segmentDict["start"] as? Double,
                let end = segmentDict["end"] as? Double else {
            return nil
          }
          let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
          guard !trimmedText.isEmpty else { return nil }
          return Segment(
            startTime: start,
            endTime: end,
            text: trimmedText,
            words: nil,
            confidence: nil
          )
        }
      }

      logger.notice("🤖 Transcription complete: \(segments.count) segments")

    }

    let processingTime = Date().timeIntervalSince(startTime)

    let finalProgress = TranscriptionProgress(
      currentSegments: segments, progress: 1.0, statusMessage: "Completed",
      estimatedTimeRemaining: 0)
    Task { @MainActor in progressHandler(finalProgress) }

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

  private func generate(request: GenerationRequest) throws -> STTOutput {
    if let generate = testHooks?.generate {
      return try generate(request)
    }

    guard let asrModel else {
      throw NSError(
        domain: "Qwen3ASR", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "ASR model not initialized."]
      )
    }

    return asrModel.generate(
      audio: MLXArray(request.audio),
      context: request.context,
      language: request.language,
      chunkDuration: request.chunkDuration,
      minChunkDuration: request.minChunkDuration
    )
  }

  // MARK: - Model File Fixup

  /// Ensure merges.txt exists in the mlx-audio cache directory.
  ///
  /// mlx-audio's ModelUtils.resolveOrDownloadModel only downloads files matching
  /// `["*.safetensors", "*.json"]`, so `merges.txt` is never downloaded.
  /// Without it, `generateTokenizerJSONIfMissing()` silently skips tokenizer.json
  /// generation, causing AutoTokenizer.from() to fail with:
  /// "Required configuration file missing: tokenizer.json"
  private func ensureMergesFile(for model: ModelVariant) async throws {
    let repoId = model.huggingFaceRepoId
    let modelDir = await ModelDownloadManager.shared.getModelDirectory(for: model)
      ?? model.storagePaths().primaryMLXAudioDirectory
      ?? ModelDownloadManager.shared.mlxAudioDirectory(forRepo: repoId)

    let mergesPath = modelDir.appendingPathComponent("merges.txt")
    if FileManager.default.fileExists(atPath: mergesPath.path) {
      logger.debug("🤖 merges.txt already exists at \(mergesPath.path)")
      return
    }

    // Create the cache directory if it doesn't exist yet
    // (fromPretrained will later find no safetensors and trigger the full model download)
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

    logger.notice("🤖 Downloading missing merges.txt for \(model.displayName) from HuggingFace")

    let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/merges.txt")!
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw NSError(
        domain: "Qwen3ASR", code: 11,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Failed to download merges.txt for tokenizer generation (HTTP \(statusCode)). "
            + "This file is required but not included in the mlx-audio model download."
        ])
    }

    try data.write(to: mergesPath)
    logger.notice(
      "🤖 Downloaded merges.txt (\(data.count) bytes) to \(mergesPath.path)")
  }
}

// MARK: - Language Extension for Qwen3

extension Language {
  /// Get the Qwen3-compatible language name.
  /// Returns a hardcoded English name (never localized) so the ASR model
  /// receives the correct token regardless of the app's UI locale.
  public var qwen3LanguageName: String {
    switch self {
    case .auto: return "auto"
    case .english: return "English"
    case .chinese: return "Chinese"
    case .german: return "German"
    case .spanish: return "Spanish"
    case .russian: return "Russian"
    case .korean: return "Korean"
    case .french: return "French"
    case .japanese: return "Japanese"
    case .portuguese: return "Portuguese"
    case .turkish: return "Turkish"
    case .polish: return "Polish"
    case .catalan: return "Catalan"
    case .dutch: return "Dutch"
    case .arabic: return "Arabic"
    case .swedish: return "Swedish"
    case .italian: return "Italian"
    case .indonesian: return "Indonesian"
    case .hindi: return "Hindi"
    case .finnish: return "Finnish"
    case .vietnamese: return "Vietnamese"
    case .hebrew: return "Hebrew"
    case .ukrainian: return "Ukrainian"
    case .greek: return "Greek"
    case .malay: return "Malay"
    case .czech: return "Czech"
    case .romanian: return "Romanian"
    case .danish: return "Danish"
    case .hungarian: return "Hungarian"
    case .tamil: return "Tamil"
    case .norwegian: return "Norwegian"
    case .thai: return "Thai"
    case .urdu: return "Urdu"
    case .croatian: return "Croatian"
    case .bulgarian: return "Bulgarian"
    case .lithuanian: return "Lithuanian"
    case .latin: return "Latin"
    case .maori: return "Maori"
    case .maltese: return "Maltese"
    case .welsh: return "Welsh"
    case .slovak: return "Slovak"
    case .slovenian: return "Slovenian"
    case .swahili: return "Swahili"
    case .galician: return "Galician"
    case .amharic: return "Amharic"
    case .assamese: return "Assamese"
    case .azerbaijani: return "Azerbaijani"
    case .bashkir: return "Bashkir"
    case .belarusian: return "Belarusian"
    case .bengali: return "Bengali"
    case .bosnian: return "Bosnian"
    case .breton: return "Breton"
    case .burmese: return "Burmese"
    case .esperanto: return "Esperanto"
    case .estonian: return "Estonian"
    case .faroese: return "Faroese"
    case .georgian: return "Georgian"
    case .gujarati: return "Gujarati"
    case .haitian: return "Haitian"
    case .hausa: return "Hausa"
    case .hawaiian: return "Hawaiian"
    case .icelandic: return "Icelandic"
    case .javanese: return "Javanese"
    case .kannada: return "Kannada"
    case .kazakh: return "Kazakh"
    case .khmer: return "Khmer"
    case .lao: return "Lao"
    case .latvian: return "Latvian"
    case .lingala: return "Lingala"
    case .luxembourgish: return "Luxembourgish"
    case .macedonian: return "Macedonian"
    case .malagasy: return "Malagasy"
    case .malayalam: return "Malayalam"
    case .marathi: return "Marathi"
    case .mongolian: return "Mongolian"
    case .nepali: return "Nepali"
    case .nynorsk: return "Nynorsk"
    case .occitan: return "Occitan"
    case .pashto: return "Pashto"
    case .persian: return "Persian"
    case .punjabi: return "Punjabi"
    case .serbian: return "Serbian"
    case .shona: return "Shona"
    case .sindhi: return "Sindhi"
    case .sinhala: return "Sinhala"
    case .somali: return "Somali"
    case .sundanese: return "Sundanese"
    case .tagalog: return "Tagalog"
    case .tajik: return "Tajik"
    case .tatar: return "Tatar"
    case .telugu: return "Telugu"
    case .tibetan: return "Tibetan"
    case .turkmen: return "Turkmen"
    case .uyghur: return "Uyghur"
    case .uzbek: return "Uzbek"
    case .yiddish: return "Yiddish"
    case .yoruba: return "Yoruba"
    }
  }
}
