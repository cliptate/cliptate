import Foundation

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

@MainActor
final class CLIRequestHandler {
  private let config: AppConfiguration
  private let persist: @MainActor (AppConfiguration) throws -> Void
  private let transcribe:
    @Sendable (BatchTranscriptionRequest, @escaping @Sendable (String) -> Void) async throws ->
      BatchTranscriptionOutput
  private let ensureModel:
    @Sendable (ModelVariant, Bool, @escaping @Sendable (String) -> Void) async throws -> Void

  init(
    config: AppConfiguration,
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
    ensureModel:
      @escaping @Sendable (ModelVariant, Bool, @escaping @Sendable (String) -> Void) async throws ->
      Void = { model, download, progress in
        guard !(await ModelDownloadManager.shared.hasLocalArtifacts(for: model)) else { return }
        guard download else {
          throw CLIError(
            String(
              format: String(
                localized: "Model %@ is not downloaded. Download it in Cliptate or use --download."),
              model.rawValue))
        }
        try await ModelDownloadManager.shared.download(
          model: model, progressHandler: { progress($0.currentStep) })
      }
  ) {
    self.config = config
    self.persist = persist
    self.transcribe = transcribe
    self.ensureModel = ensureModel
  }

  func execute(_ request: CLIRequest, progress: @escaping @Sendable (String) -> Void = { _ in })
    async throws -> CLIEvent
  {
    try Task.checkCancellation()
    switch request.operation {
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
}
