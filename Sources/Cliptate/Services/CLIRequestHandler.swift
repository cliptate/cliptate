import Foundation

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

struct CLISpeechRequest: Sendable {
  let text: String
  let model: MLXTTSModelDefinition
  let voice: String?
  let language: String
  let referenceAudioURL: URL?
  let referenceText: String?
  let variantPreference: TTSVariantPreference
}

@MainActor
final class CLIRequestHandler {
  private let config: AppConfiguration
  private let history: HistoryRuntime?
  private let persist: @MainActor (AppConfiguration) throws -> Void
  private let transcribe:
    @Sendable (BatchTranscriptionRequest, @escaping @Sendable (String) -> Void) async throws ->
      BatchTranscriptionOutput
  private let synthesize: @Sendable (CLISpeechRequest) async throws -> Data
  private let ensureModel:
    @Sendable (ModelVariant, Bool, @escaping @Sendable (String) -> Void) async throws -> Void

  init(
    config: AppConfiguration,
    history: HistoryRuntime? = nil,
    persist: @escaping @MainActor (AppConfiguration) throws -> Void = {
      try ConfigurationRuntime.shared.flush(using: $0)
    },
    transcribe:
      @escaping @Sendable (BatchTranscriptionRequest, @escaping @Sendable (String) -> Void)
      async throws -> BatchTranscriptionOutput = { request, progress in
        try await BatchTranscriptionRuntime.shared.transcribe(
          request: request,
          modelProgressHandler: { progress($0.currentStep) },
          progressHandler: { progress($0.statusMessage) })
      },
    synthesize: @escaping @Sendable (CLISpeechRequest) async throws -> Data = { request in
      let cache = ModelCacheManager.shared
      _ = try await cache.ensureTTSModel(engine: .qwen3TTS, modelID: request.model.huggingFaceRepo)
      do {
        let audio = try await TTSSessionRuntime.shared.synthesize(
          text: request.text, modelDefinition: request.model, voiceDescription: request.voice,
          referenceAudioURL: request.referenceAudioURL, referenceText: request.referenceText,
          language: request.language, variantPreference: request.variantPreference)
        await cache.releaseTTSModel(engine: .qwen3TTS, modelID: request.model.huggingFaceRepo)
        return audio
      } catch {
        await cache.releaseTTSModel(engine: .qwen3TTS, modelID: request.model.huggingFaceRepo)
        throw error
      }
    },
    ensureModel:
      @escaping @Sendable (ModelVariant, Bool, @escaping @Sendable (String) -> Void) async throws ->
      Void = { model, download, progress in
        try await CLIRequestHandler.defaultEnsureModel(model, download: download, progress: progress)
      }
  ) {
    self.config = config
    self.history = history
    self.persist = persist
    self.transcribe = transcribe
    self.ensureModel = ensureModel
    self.synthesize = synthesize
  }

  nonisolated private static func defaultEnsureModel(
    _ model: ModelVariant, download: Bool, progress: @escaping @Sendable (String) -> Void
  ) async throws {
    let downloads = ModelDownloadManager.shared
    guard !(await downloads.hasLocalArtifacts(for: model)) else { return }
    guard download else {
      throw CLIError(
        String(
          format: String(
            localized: "Model %@ is not downloaded. Download it in Cliptate or use --download."),
          model.rawValue))
    }
    try await downloads.download(
      model: model, progressHandler: { progress($0.currentStep) })
  }

  func execute(_ request: CLIRequest, progress: @escaping @Sendable (String) -> Void = { _ in })
    async throws -> CLIEvent
  {
    try Task.checkCancellation()
    switch request.operation {
    case .history:
      guard let query = request.history else { throw CLIChannel.protocolError() }
      return CLIEvent(.result, history: try (history ?? .shared).query(query))
    case .dictionaryList: return CLIEvent(.result, entries: config.voiceToTextCustomDictionary)
    case .dictionaryAdd, .dictionaryRemove:
      let previous = config.voiceToTextCustomDictionary
      if request.operation == .dictionaryAdd {
        config.appendDictionaryEntries(request.entries)
      } else {
        for entry in AppConfiguration.normalizeDictionaryEntries(request.entries) {
          config.removeDictionaryEntry(entry)
        }
      }
      do { try persist(config) } catch {
        config.replaceDictionaryEntries(with: previous)
        throw error
      }
      return CLIEvent(.result, entries: config.voiceToTextCustomDictionary)
    case .tts: return try await synthesizeSpeech(request, progress: progress)
    case .transcribe:
      let model: ModelVariant
      if let name = request.model {
        guard let value = ModelVariant(rawValue: name),
          TranscriberType.selectableCases.contains(where: { $0.supportedModels.contains(value) })
        else {
          throw CLIError(String(format: String(localized: "Unsupported ASR model: %@."), name))
        }
        model = value
      } else {
        model = config.modelVariant
      }
      guard
        let type = TranscriberType.selectableCases.first(where: {
          $0.supportedModels.contains(model)
        })
      else {
        throw CLIError(
          String(format: String(localized: "Unsupported ASR model: %@."), model.rawValue))
      }
      let language: Language
      if let code = request.language {
        guard let value = Language(rawValue: code) else {
          throw CLIError(String(format: String(localized: "Unsupported language code: %@."), code))
        }
        language = value
      } else {
        language = config.language
      }
      guard
        language == .auto || model.supportedLanguages.isEmpty
          || model.supportedLanguages.contains(language)
      else {
        throw CLIError(
          String(
            format: String(localized: "Model %@ does not support language %@."), model.rawValue,
            language.rawValue))
      }
      guard let bookmark = request.bookmark else { throw CLIChannel.protocolError() }
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil,
        bookmarkDataIsStale: &stale)
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      // Verify transferred read access before doing model work; no path-only fallback.
      let source = try FileHandle(forReadingFrom: url)
      try source.close()
      let batch = BatchTranscriptionRequest(
        sourceURL: url, workflow: .fileTranscription,
        transcriberType: type, asrModel: model, vadModel: config.vadModelVariant,
        alignModel: config.alignModelVariant, language: language,
        dictionaryEntries: request.useDictionary ? config.voiceToTextCustomDictionary : [])
      // Capture all defaults before suspending, so GUI changes affect subsequent commands only.
      var required = [batch.asrModel, batch.vadModel]
      if let aligner = batch.alignModel { required.append(aligner) }
      for model in required {
        try Task.checkCancellation()
        try await ensureModel(model, request.download, progress)
      }
      try Task.checkCancellation()
      let output = try await transcribe(batch, progress)
      try Task.checkCancellation()
      let result = CLIFileResult(
        file: url.path, model: output.result.modelUsed,
        duration: output.result.totalDuration,
        segments: output.result.segments.map {
          CLISegment(
            id: $0.id, text: $0.text, start: $0.startTime, end: $0.endTime, speakerId: $0.speakerId)
        })
      return CLIEvent(.result, transcript: result)
    }
  }

  private func synthesizeSpeech(
    _ request: CLIRequest, progress: @escaping @Sendable (String) -> Void
  )
    async throws -> CLIEvent
  {
    guard let parameters = request.tts, let outputBookmark = request.outputBookmark else {
      throw CLIChannel.protocolError()
    }
    let text = try CLITTSOptions.validatedText(Data(parameters.text.utf8))
    let name = request.model ?? config.ttsMLXModelId
    guard
      let model = MLXTTSModelDefinition.availableModels.first(where: {
        $0.id == name || $0.huggingFaceRepo == name || $0.modelVariant.rawValue == name
      })
    else {
      throw CLIError(String(format: String(localized: "Unsupported TTS model: %@."), name))
    }
    let language = request.language ?? config.ttsLanguage
    // Qwen checkpoints index codec languages by full names, while app settings use ISO codes.
    let languages = [
      "auto": "auto", "en": "english", "zh": "chinese", "ja": "japanese",
      "ko": "korean", "de": "german", "fr": "french", "ru": "russian",
      "pt": "portuguese", "es": "spanish", "it": "italian",
    ]
    guard let inferenceLanguage = languages[language] else {
      throw CLIError(String(format: String(localized: "Unsupported language code: %@."), language))
    }
    let variant: TTSVariantPreference
    if let raw = parameters.variant {
      guard let value = TTSVariantPreference(rawValue: raw) else {
        throw CLIChannel.protocolError()
      }
      variant = value
    } else {
      variant = config.ttsVariantPreference
    }
    let cloning = request.bookmark != nil
    let voice: String?
    if cloning {
      guard model.supportsVoiceClone, parameters.voice == nil, parameters.emotion == nil,
        let referenceText = parameters.referenceText,
        !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw invalidTTSVoice()
      }
      voice = nil
    } else {
      guard parameters.referenceText == nil else { throw invalidTTSVoice() }
      switch model.family {
      case .voiceDesign:
        guard parameters.emotion == nil else { throw invalidTTSVoice() }
        voice = parameters.voice ?? config.ttsVoiceDescription
        guard !(voice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
          throw invalidTTSVoice()
        }
      case .customVoice:
        let speaker = parameters.voice ?? config.ttsPresetSpeaker
        guard speaker.isEmpty || TTSPresetSpeaker.all.contains(where: { $0.name == speaker }) else {
          throw invalidTTSVoice()
        }
        voice = MLXTTSModelDefinition.customVoiceString(
          speaker: speaker, emotionPrompt: parameters.emotion ?? config.ttsEmotionPrompt)
      case .base:
        guard parameters.voice == nil, parameters.emotion == nil else { throw invalidTTSVoice() }
        voice = nil
      }
    }
    // Resolve and verify file access before model loading. CLI output stays private until success.
    let output = try resolve(outputBookmark)
    let outputAccess = output.startAccessingSecurityScopedResource()
    defer { if outputAccess { output.stopAccessingSecurityScopedResource() } }
    let target = try FileHandle(forWritingTo: output)
    try target.close()
    let reference = try request.bookmark.map(resolve)
    let referenceAccess = reference?.startAccessingSecurityScopedResource() ?? false
    defer { if referenceAccess { reference?.stopAccessingSecurityScopedResource() } }
    if let reference {
      guard reference.resolvingSymlinksInPath() != output.resolvingSymlinksInPath() else {
        throw invalidTTSVoice()
      }
      let source = try FileHandle(forReadingFrom: reference)
      try source.close()
    }
    let synthesis = CLISpeechRequest(
      text: text, model: model, voice: voice, language: inferenceLanguage,
      referenceAudioURL: reference, referenceText: parameters.referenceText,
      variantPreference: variant)
    try await ensureModel(model.modelVariant, request.download, progress)
    try Task.checkCancellation()
    progress(String(localized: "Generating speech…"))
    let audio = try await synthesize(synthesis)
    try Task.checkCancellation()
    try audio.write(to: output, options: .atomic)
    return CLIEvent(
      .result, audio: CLIAudioResult(file: output.path, model: model.id, bytes: audio.count))
  }

  private func invalidTTSVoice() -> CLIError {
    CLIError(
      String(
        localized:
          "Voice options do not match the TTS model. Use a CustomVoice speaker, a VoiceDesign description, or Base reference audio with its transcript."
      ))
  }

  private func resolve(_ bookmark: Data) throws -> URL {
    var stale = false
    return try URL(
      resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil,
      bookmarkDataIsStale: &stale)
  }

}
