import CoreGraphics
import Darwin
import Foundation

public enum CliptateCLI {
  enum CLIError: Error, CustomStringConvertible, LocalizedError {
    case usage(String)

    var description: String {
      switch self {
      case .usage(let message):
        return message
      }
    }

    var errorDescription: String? { description }
  }

  enum CutFormat: String, CaseIterable, Sendable {
    case ass
    case srt
    case fcpxml
    case video
    case txt
    case json
  }

  struct CutRequest: Sendable {
    var videoURL: URL
    var sourceLanguage: Language
    var asrModel: ModelVariant
    var alignerModel: ModelVariant?
    var enableAlign: Bool
  }

  struct CutTranscription: Sendable {
    var segments: [Segment]
    var duration: TimeInterval
    var modelUsed: String
  }

  struct TTSRequest: Sendable {
    var text: String
    var outputURL: URL
    var model: MLXTTSModelDefinition
    var voice: String?
    var language: String?
    var referenceAudioURL: URL?
    var referenceText: String?
    var variantPreference: TTSVariantPreference
  }

  struct Dependencies: Sendable {
    var transcribe: @Sendable (CutRequest) async throws -> CutTranscription
    var synthesize: @Sendable (TTSRequest) async throws -> Data
    var renderVideo:
      @Sendable (
        URL,
        [Segment],
        URL,
        Bool,
        SubtitleTranslationPlacement,
        VideoExportQuality,
        SubtitleStylesConfiguration
      ) async throws -> Void

    init(
      transcribe: @escaping @Sendable (CutRequest) async throws -> CutTranscription =
        Self.defaultTranscribe,
      synthesize: @escaping @Sendable (TTSRequest) async throws -> Data = Self.defaultSynthesize,
      renderVideo: @escaping @Sendable (
        URL,
        [Segment],
        URL,
        Bool,
        SubtitleTranslationPlacement,
        VideoExportQuality,
        SubtitleStylesConfiguration
      ) async throws -> Void = Self.defaultRenderVideo
    ) {
      self.transcribe = transcribe
      self.synthesize = synthesize
      self.renderVideo = renderVideo
    }

    private static func defaultTranscribe(_ request: CutRequest) async throws -> CutTranscription {
      let output = try await BatchTranscriptionRuntime.shared.transcribe(
        request: BatchTranscriptionRequest(
          sourceURL: request.videoURL,
          workflow: .fileTranscription,
          transcriberType: transcriberType(for: request.asrModel),
          asrModel: request.asrModel,
          vadModel: .sileroVAD,
          alignModel: request.enableAlign ? request.alignerModel : nil,
          language: request.sourceLanguage,
          dictionaryEntries: []
        ),
        progressHandler: { progress in
          print(progress.statusMessage)
        }
      )
      return CutTranscription(
        segments: output.result.segments,
        duration: output.result.totalDuration,
        modelUsed: output.result.modelUsed
      )
    }

    private static func defaultSynthesize(_ request: TTSRequest) async throws -> Data {
      try await MLXTTSService.shared.synthesize(
        text: request.text,
        modelDefinition: request.model,
        voiceDescription: request.voice,
        referenceAudioURL: request.referenceAudioURL,
        referenceText: request.referenceText,
        language: request.language,
        variantPreference: request.variantPreference
      )
    }

    @MainActor
    private static func defaultRenderVideo(
      videoURL: URL,
      segments: [Segment],
      outputURL: URL,
      filterSilentSegments: Bool,
      translationPlacement: SubtitleTranslationPlacement,
      quality: VideoExportQuality,
      styleConfiguration: SubtitleStylesConfiguration
    ) async throws {
      try await VideoExporter().exportVideoWithSubtitles(
        videoURL: videoURL,
        segments: segments,
        outputURL: outputURL,
        filterSilentSegments: filterSilentSegments,
        translationPlacement: translationPlacement,
        styleConfiguration: styleConfiguration,
        quality: quality
      )
    }
  }

  struct RunResult: Sendable {
    var exitCode: Int
    var outputs: [String: [String: URL]]
  }

  struct CutOptions: Sendable {
    var transcriptURL: URL?
    var outputDir: URL?
    var asrModel: String?
    var alignerModel: String?
    var enableAlign = true
    var segmentDuration: Int = 300
    var maxDuration: TimeInterval = 30.0
    var maxChars = 30
    var translate = false
    var sourceLanguage: Language?
    var targetLanguage: Language?
    var orientation: SubtitleOrientation = .landscape
    var translationPlacement: SubtitleTranslationPlacement = .above
    var originalSubtitleColor = "#FFFFFF"
    var translationSubtitleColor = "#FFA500"
    var firstSubtitleDelay: TimeInterval = 1.0
    var filterEmptySegments = true
    var filterFillers = true
    var marginLeftMilliseconds: Double = -100.0
    var marginRightMilliseconds: Double = 150.0
    var formats: [CutFormat] = [.srt]
    var fcpxmlFrameRate: Double = 25.0
    var fcpxmlSpeed: Double = 1.0
    var videoInputs: [String] = []
  }

  struct TTSOptions: Sendable {
    var text: String?
    var textFile: URL?
    var outputURL: URL?
    var ttsModel: String?
    var voice: String?
    var language: String?
    var referenceAudioURL: URL?
    var promptText: String?
    var variantPreference: TTSVariantPreference = .automatic
  }

  private struct TranscriptDocument: Sendable {
    var title: String
    var subtitle: String
    var translationSourceLanguage: Language?
    var translationTargetLanguage: Language?
    var segments: [Segment]
  }

  private static let supportedMediaExtensions: Set<String> = [
    "mp4", "mov", "mkv", "avi", "m4v", "webm",
    "wav", "mp3", "m4a", "aac", "flac", "ogg",
  ]

  private static let fillerWords: Set<String> = [
    "um", "uh", "erm", "ah", "eh",
    "额", "啊", "嗯", "呃", "唔",
  ]

  public static func main(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) async -> Int {
    do {
      _ = try await run(arguments: arguments)
      return 0
    } catch {
      writeStandardError("\(error.localizedDescription)\n")
      return 1
    }
  }

  @discardableResult
  @MainActor
  static func run(
    arguments: [String],
    dependencies: Dependencies = Dependencies()
  ) async throws -> RunResult {
    guard !arguments.isEmpty else {
      throw CLIError.usage(topLevelUsage())
    }

    if arguments.first == "-h" || arguments.first == "--help" {
      print(topLevelUsage())
      return RunResult(exitCode: 0, outputs: [:])
    }

    let subcommand = arguments.first ?? "cut"
    switch subcommand {
    case "cut":
      return try await runCut(
        options: parseCutOptions(Array(arguments.dropFirst())),
        dependencies: dependencies
      )
    case "tts":
      return try await runTTS(
        options: parseTTSOptions(Array(arguments.dropFirst())),
        dependencies: dependencies
      )
    default:
      return try await runCut(
        options: parseCutOptions(arguments),
        dependencies: dependencies
      )
    }
  }

  @MainActor
  private static func runCut(
    options: CutOptions,
    dependencies: Dependencies
  ) async throws -> RunResult {
    let inputs = expandMediaInputs(options.videoInputs)
    guard !inputs.isEmpty else {
      throw CLIError.usage("No valid media files found in inputs")
    }
    if options.transcriptURL != nil && inputs.count > 1 {
      throw CLIError.usage("--transcript can only be used with a single media input")
    }

    let appConfig = AppConfiguration.shared
    let sourceLanguage = options.sourceLanguage ?? appConfig.language
    let targetLanguage = options.targetLanguage ?? appConfig.language
    let asrModel = try resolveASRModel(options.asrModel, fallbackModel: appConfig.modelVariant)
    let alignerModel = try resolveAlignerModel(options.alignerModel, enableAlign: options.enableAlign)
    let styleConfiguration = try makeStyleConfiguration(
      originalHex: options.originalSubtitleColor,
      translationHex: options.translationSubtitleColor
    )

    var allOutputs: [String: [String: URL]] = [:]
    for input in inputs {
      let outputDir = resolvedOutputDirectory(for: input, explicitOutputDir: options.outputDir)
      try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

      let sourceDocument: TranscriptDocument
      let duration: TimeInterval
      if let transcriptURL = options.transcriptURL {
        sourceDocument = try loadTranscriptJSON(
          from: transcriptURL,
          fallbackTargetLanguage: targetLanguage
        )
        duration = max(sourceDocument.segments.map(\.endTime).max() ?? 0, 0.001)
      } else {
        let transcription = try await dependencies.transcribe(
          CutRequest(
            videoURL: input,
            sourceLanguage: sourceLanguage,
            asrModel: asrModel,
            alignerModel: alignerModel,
            enableAlign: options.enableAlign
          )
        )
        sourceDocument = TranscriptDocument(
          title: "",
          subtitle: "",
          translationSourceLanguage: nil,
          translationTargetLanguage: nil,
          segments: transcription.segments
        )
        duration = max(transcription.duration, transcription.segments.map(\.endTime).max() ?? 0.001)
      }

      var exportSegments = prepareSegments(sourceDocument.segments, options: options, duration: duration)
      if !options.translate {
        exportSegments = exportSegments.map { segment in
          var copy = segment
          copy.translation = nil
          return copy
        }
      }

      let outputBase = outputDir.appendingPathComponent(input.deletingPathExtension().lastPathComponent)
      let transcriptOutputURL = outputDir
        .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)_transcript.json")
      let outputDocument = TranscriptDocument(
        title: sourceDocument.title,
        subtitle: sourceDocument.subtitle,
        translationSourceLanguage: sourceDocument.translationSourceLanguage ?? sourceLanguage,
        translationTargetLanguage: options.translate
          ? (sourceDocument.translationTargetLanguage ?? targetLanguage)
          : sourceDocument.translationTargetLanguage,
        segments: exportSegments
      )
      try writeTranscriptJSON(outputDocument, to: transcriptOutputURL, includeTranslation: options.translate)

      var outputs: [String: URL] = ["transcript": transcriptOutputURL]
      let formats = Set(options.formats)
      if formats.contains(.txt) {
        let url = outputBase.appendingPathExtension("txt")
        try makePlainText(segments: exportSegments, includeTranslation: options.translate)
          .write(to: url, atomically: true, encoding: .utf8)
        outputs["txt"] = url
      }
      if formats.contains(.srt) {
        let url = outputDir
          .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)_subtitles")
          .appendingPathExtension("srt")
        try makeSRT(
          segments: exportSegments,
          includeTranslation: options.translate,
          placement: options.translationPlacement
        ).write(to: url, atomically: true, encoding: .utf8)
        outputs["srt"] = url
      }
      if formats.contains(.ass) {
        let url = outputDir
          .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)_subtitles")
          .appendingPathExtension("ass")
        let ass = ASSGenerator.makeASS(
          segments: exportSegments,
          orientation: options.orientation,
          filterSilentSegments: options.filterEmptySegments,
          translationPlacement: options.translationPlacement,
          styleConfiguration: styleConfiguration
        )
        try (Data([0xEF, 0xBB, 0xBF]) + Data(ass.utf8)).write(to: url, options: .atomic)
        outputs["ass"] = url
      }
      if formats.contains(.fcpxml) {
        let url = outputBase.appendingPathExtension("fcpxml")
        let media = MediaFile(
          url: input,
          segments: exportSegments,
          duration: duration,
          presentationSize: defaultPresentationSize(for: options.orientation),
          translationPlacement: options.translationPlacement,
          styleConfiguration: styleConfiguration
        )
        let content = FCPXMLExporter.exportFCPXML(
          mediaFiles: [media],
          settings: FCPXMLExportSettings(
            frameRate: options.fcpxmlFrameRate,
            projectName: input.deletingPathExtension().lastPathComponent,
            includeSubtitles: true,
            filterEmptySegments: options.filterEmptySegments,
            speed: options.fcpxmlSpeed
          )
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        outputs["fcpxml"] = url
      }
      if formats.contains(.video) {
        let url = outputDir
          .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)_final")
          .appendingPathExtension("mp4")
        try await dependencies.renderVideo(
          input,
          exportSegments,
          url,
          options.filterEmptySegments,
          options.translationPlacement,
          .high,
          styleConfiguration
        )
        outputs["video"] = url
      }

      allOutputs[input.path] = outputs
    }

    return RunResult(exitCode: 0, outputs: allOutputs)
  }

  @MainActor
  private static func runTTS(
    options: TTSOptions,
    dependencies: Dependencies
  ) async throws -> RunResult {
    guard let outputURL = options.outputURL else {
      throw CLIError.usage("tts requires -o/--output")
    }
    let text: String
    if let literal = options.text {
      text = literal
    } else if let textFile = options.textFile {
      text = try String(contentsOf: textFile, encoding: .utf8)
    } else {
      throw CLIError.usage("tts requires --text or --text-file")
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw CLIError.usage("TTS text is empty")
    }

    let appConfig = AppConfiguration.shared
    let model = try resolveTTSModel(options.ttsModel, fallbackModelID: appConfig.ttsMLXModelId)
    let request = TTSRequest(
      text: trimmed,
      outputURL: outputURL,
      model: model,
      voice: options.voice,
      language: options.language ?? appConfig.ttsLanguage,
      referenceAudioURL: options.referenceAudioURL,
      referenceText: options.promptText,
      variantPreference: options.variantPreference
    )
    let audio = try await dependencies.synthesize(request)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try audio.write(to: outputURL, options: .atomic)

    return RunResult(exitCode: 0, outputs: ["tts": ["audio": outputURL]])
  }

  private static func parseCutOptions(_ arguments: [String]) throws -> CutOptions {
    var options = CutOptions()
    var index = 0
    while index < arguments.count {
      let arg = arguments[index]
      switch arg {
      case "-h", "--help":
        throw CLIError.usage(cutUsage())
      case "--transcript":
        options.transcriptURL = URL(fileURLWithPath: try value(after: arg, in: arguments, at: &index)).expandedFileURL
      case "-o", "--output-dir":
        options.outputDir = URL(fileURLWithPath: try value(after: arg, in: arguments, at: &index)).expandedFileURL
      case "--asr-model":
        options.asrModel = try value(after: arg, in: arguments, at: &index)
      case "--aligner-model":
        options.alignerModel = try value(after: arg, in: arguments, at: &index)
      case "--no-align":
        options.enableAlign = false
      case "--segment-duration":
        options.segmentDuration = try parseIntOption(arg, arguments, &index)
      case "--max-duration":
        options.maxDuration = try parseDoubleOption(arg, arguments, &index)
      case "--max-chars":
        options.maxChars = try parseIntOption(arg, arguments, &index)
      case "--translate":
        options.translate = true
      case "--source-lang":
        options.sourceLanguage = try parseLanguage(try value(after: arg, in: arguments, at: &index), option: arg)
      case "--target-lang":
        options.targetLanguage = try parseLanguage(try value(after: arg, in: arguments, at: &index), option: arg)
      case "--orientation":
        options.orientation = try parseOrientation(try value(after: arg, in: arguments, at: &index))
      case "--subtitle-position":
        options.translationPlacement = try parseSubtitlePosition(
          try value(after: arg, in: arguments, at: &index)
        )
      case "--original-subtitle-color":
        options.originalSubtitleColor = try normalizeHexColor(try value(after: arg, in: arguments, at: &index))
      case "--translation-subtitle-color":
        options.translationSubtitleColor = try normalizeHexColor(try value(after: arg, in: arguments, at: &index))
      case "--first-subtitle-delay":
        options.firstSubtitleDelay = try parseDoubleOption(arg, arguments, &index)
      case "--no-filter-empty-segments":
        options.filterEmptySegments = false
      case "--no-filter-fillers":
        options.filterFillers = false
      case "--margin-left":
        options.marginLeftMilliseconds = try parseDoubleOption(arg, arguments, &index)
      case "--margin-right":
        options.marginRightMilliseconds = try parseDoubleOption(arg, arguments, &index)
      case "--format":
        options.formats = try parseFormats(try value(after: arg, in: arguments, at: &index))
      case "--fcpxml-frame-rate":
        options.fcpxmlFrameRate = try parseDoubleOption(arg, arguments, &index)
      case "--fcpxml-speed":
        options.fcpxmlSpeed = try parseDoubleOption(arg, arguments, &index)
      default:
        if let value = inlineValue(for: "--transcript", in: arg) {
          options.transcriptURL = URL(fileURLWithPath: value).expandedFileURL
        } else if let value = inlineValue(for: "--output-dir", in: arg) {
          options.outputDir = URL(fileURLWithPath: value).expandedFileURL
        } else if let value = inlineValue(for: "--format", in: arg) {
          options.formats = try parseFormats(value)
        } else if arg.hasPrefix("-") {
          throw CLIError.usage("Unknown cut option: \(arg)")
        } else {
          options.videoInputs.append(arg)
        }
      }
      index += 1
    }
    guard !options.videoInputs.isEmpty else {
      throw CLIError.usage("cut requires at least one media input")
    }
    return options
  }

  private static func parseTTSOptions(_ arguments: [String]) throws -> TTSOptions {
    var options = TTSOptions()
    var index = 0
    while index < arguments.count {
      let arg = arguments[index]
      switch arg {
      case "-h", "--help":
        throw CLIError.usage(ttsUsage())
      case "--text":
        guard options.textFile == nil else { throw CLIError.usage("--text conflicts with --text-file") }
        options.text = try value(after: arg, in: arguments, at: &index)
      case "--text-file":
        guard options.text == nil else { throw CLIError.usage("--text-file conflicts with --text") }
        options.textFile = URL(fileURLWithPath: try value(after: arg, in: arguments, at: &index)).expandedFileURL
      case "-o", "--output":
        options.outputURL = URL(fileURLWithPath: try value(after: arg, in: arguments, at: &index)).expandedFileURL
      case "--tts-model":
        options.ttsModel = try value(after: arg, in: arguments, at: &index)
      case "--voice":
        options.voice = try value(after: arg, in: arguments, at: &index)
      case "--lang-code":
        options.language = try value(after: arg, in: arguments, at: &index)
      case "--reference-audio", "--prompt-audio":
        options.referenceAudioURL = URL(fileURLWithPath: try value(after: arg, in: arguments, at: &index)).expandedFileURL
      case "--prompt-text":
        options.promptText = try value(after: arg, in: arguments, at: &index)
      case "--variant":
        let raw = try value(after: arg, in: arguments, at: &index)
        guard let variant = TTSVariantPreference(rawValue: raw) else {
          throw CLIError.usage("unsupported --variant '\(raw)'")
        }
        options.variantPreference = variant
      case "--speed", "--split-pattern", "--split_pattern", "--max-tokens", "--max_tokens",
        "--temperature", "--top-p", "--top_p", "--top-k", "--top_k",
        "--repetition-penalty", "--repetition_penalty", "--device", "--stt-model", "--stt_model",
        "--cfg", "--steps":
        _ = try value(after: arg, in: arguments, at: &index)
      case "--verbose", "--normalize", "--join-audio", "--join_audio", "--no-join-audio",
        "--no-join_audio":
        break
      default:
        if arg.hasPrefix("-") {
          throw CLIError.usage("Unknown tts option: \(arg)")
        } else {
          throw CLIError.usage("Unexpected tts argument: \(arg)")
        }
      }
      index += 1
    }
    return options
  }

  private static func prepareSegments(
    _ inputSegments: [Segment],
    options: CutOptions,
    duration: TimeInterval
  ) -> [Segment] {
    var segments = inputSegments.sorted { $0.startTime < $1.startTime }
    if options.filterFillers {
      segments = filterFillers(in: segments)
    }
    segments = applyMargins(
      to: segments,
      leftSeconds: options.marginLeftMilliseconds / 1000.0,
      rightSeconds: options.marginRightMilliseconds / 1000.0,
      duration: duration
    )
    if options.maxChars > 0 {
      segments = SegmentProcess.process(
        segments: segments,
        totalDuration: duration,
        operations: [.splitByCharCount(.init(maxChars: options.maxChars))]
      )
    }
    if options.maxDuration > 0 {
      segments = splitSegmentsByDuration(segments, maxDuration: options.maxDuration)
    }
    if options.filterEmptySegments {
      segments = segments.filter { segment in
        !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !(segment.translation?.isEmpty ?? true)
      }
    }
    return segments
  }

  private static func applyMargins(
    to segments: [Segment],
    leftSeconds: TimeInterval,
    rightSeconds: TimeInterval,
    duration: TimeInterval
  ) -> [Segment] {
    let shifted = segments.map { segment in
      Segment(
        id: segment.id,
        startTime: max(0, segment.startTime + leftSeconds),
        endTime: min(max(duration, segment.endTime), max(0, segment.endTime + rightSeconds)),
        text: segment.text,
        words: segment.words,
        confidence: segment.confidence,
        speakerId: segment.speakerId,
        translation: segment.translation
      )
    }
    var resolved: [Segment] = []
    for index in shifted.indices {
      var segment = shifted[index]
      if let previous = resolved.last, segment.startTime < previous.endTime {
        let midpoint = (previous.endTime + segment.startTime) / 2
        resolved[resolved.count - 1] = Segment(
          id: previous.id,
          startTime: previous.startTime,
          endTime: max(previous.startTime, midpoint),
          text: previous.text,
          words: previous.words,
          confidence: previous.confidence,
          speakerId: previous.speakerId,
          translation: previous.translation
        )
        segment = Segment(
          id: segment.id,
          startTime: max(0, midpoint),
          endTime: max(midpoint, segment.endTime),
          text: segment.text,
          words: segment.words,
          confidence: segment.confidence,
          speakerId: segment.speakerId,
          translation: segment.translation
        )
      }
      resolved.append(segment)
    }
    return resolved
  }

  private static func splitSegmentsByDuration(_ segments: [Segment], maxDuration: TimeInterval) -> [Segment] {
    var result: [Segment] = []
    for segment in segments {
      guard segment.duration > maxDuration, let words = segment.words, words.count > 1 else {
        result.append(segment)
        continue
      }
      var bucket: [WordTiming] = []
      var bucketStart = words[0].startTime
      for word in words {
        if !bucket.isEmpty, word.endTime - bucketStart > maxDuration {
          appendSegment(from: bucket, parent: segment, into: &result)
          bucket.removeAll()
          bucketStart = word.startTime
        }
        bucket.append(word)
      }
      appendSegment(from: bucket, parent: segment, into: &result)
    }
    return result
  }

  private static func appendSegment(from words: [WordTiming], parent: Segment, into result: inout [Segment]) {
    guard let first = words.first, let last = words.last else { return }
    result.append(
      Segment(
        id: Segment.deterministicChildId(
          parentId: parent.id,
          startTime: first.startTime,
          endTime: last.endTime
        ),
        startTime: first.startTime,
        endTime: last.endTime,
        text: WordTimingTextComposer.composeText(from: words),
        words: words,
        confidence: parent.confidence,
        speakerId: parent.speakerId,
        translation: parent.translation
      )
    )
  }

  private static func filterFillers(in segments: [Segment]) -> [Segment] {
    segments.compactMap { segment in
      let filteredText = segment.text
        .split(separator: " ", omittingEmptySubsequences: false)
        .filter { token in
          !fillerWords.contains(
            token.trimmingCharacters(in: .punctuationCharacters).lowercased()
          )
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !filteredText.isEmpty else { return nil }
      return Segment(
        id: segment.id,
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: filteredText,
        words: segment.words,
        confidence: segment.confidence,
        speakerId: segment.speakerId,
        translation: segment.translation
      )
    }
  }

  private static func makePlainText(segments: [Segment], includeTranslation: Bool) -> String {
    var lines: [String] = []
    for segment in segments {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let translation = includeTranslation
        ? segment.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        : nil
      guard !text.isEmpty || !(translation?.isEmpty ?? true) else { continue }
      lines.append("[\(plainTimestamp(segment.startTime)) - \(plainTimestamp(segment.endTime))] \(text)")
      if let translation, !translation.isEmpty {
        lines.append("    -> \(translation)")
      }
    }
    return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
  }

  private static func makeSRT(
    segments: [Segment],
    includeTranslation: Bool,
    placement: SubtitleTranslationPlacement
  ) -> String {
    var blocks: [String] = []
    var index = 1
    for segment in segments {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let translation = includeTranslation
        ? segment.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        : nil
      guard !text.isEmpty || !(translation?.isEmpty ?? true) else { continue }
      var lines: [String] = []
      if placement == .above, let translation, !translation.isEmpty {
        lines.append(translation)
      }
      if !text.isEmpty {
        lines.append(text)
      }
      if placement == .below, let translation, !translation.isEmpty {
        lines.append(translation)
      }
      blocks.append(
        """
        \(index)
        \(srtTimestamp(segment.startTime)) --> \(srtTimestamp(segment.endTime))
        \(lines.joined(separator: "\n"))
        """
      )
      index += 1
    }
    return blocks.joined(separator: "\n\n") + (blocks.isEmpty ? "" : "\n")
  }

  private static func loadTranscriptJSON(
    from url: URL,
    fallbackTargetLanguage: Language
  ) throws -> TranscriptDocument {
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    let root: [String: Any]
    let rawSegments: [Any]
    if let array = object as? [Any] {
      root = [:]
      rawSegments = array
    } else if let dictionary = object as? [String: Any] {
      root = dictionary
      rawSegments = dictionary["segments"] as? [Any] ?? []
    } else {
      throw CLIError.usage("Transcript JSON root must be an object or array")
    }

    let translationMeta = root["translation"] as? [String: Any]
    let targetLanguage = (translationMeta?["target_lang"] as? String)
      .flatMap { Language(rawValue: $0) }
      ?? fallbackTargetLanguage
    let sourceLanguage = (translationMeta?["source_lang"] as? String)
      .flatMap { Language(rawValue: $0) }

    let segments = rawSegments.compactMap { item -> Segment? in
      guard let dictionary = item as? [String: Any] else { return nil }
      guard let start = number(dictionary["start"] ?? dictionary["startTime"]) else { return nil }
      let end = number(dictionary["end"] ?? dictionary["endTime"]) ?? start
      let text = dictionary["text"] as? String ?? ""
      let id = dictionary["id"] as? String ?? UUID().uuidString
      let words = parseWords(dictionary["words"] as? [Any])
      var segment = Segment(
        id: id,
        startTime: start,
        endTime: end,
        text: text,
        words: words,
        confidence: number(dictionary["confidence"]).map(Float.init)
      )
      if let translation = dictionary["translation"] as? String,
        !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        segment.translation = SegmentTranslation(text: translation, language: targetLanguage)
      }
      return segment
    }

    return TranscriptDocument(
      title: root["title"] as? String ?? "",
      subtitle: root["subtitle"] as? String ?? "",
      translationSourceLanguage: sourceLanguage,
      translationTargetLanguage: targetLanguage,
      segments: segments
    )
  }

  private static func parseWords(_ rawWords: [Any]?) -> [WordTiming]? {
    guard let rawWords else { return nil }
    let words = rawWords.compactMap { item -> WordTiming? in
      guard let dictionary = item as? [String: Any] else { return nil }
      guard let word = dictionary["word"] as? String else { return nil }
      let start = number(dictionary["start"] ?? dictionary["startTime"]) ?? 0
      let end = number(dictionary["end"] ?? dictionary["endTime"]) ?? start
      return WordTiming(
        word: word,
        startTime: start,
        endTime: end,
        confidence: number(dictionary["confidence"]).map(Float.init),
        punctuation: dictionary["punctuation"] as? String ?? ""
      )
    }
    return words.isEmpty ? nil : words
  }

  private static func writeTranscriptJSON(
    _ document: TranscriptDocument,
    to url: URL,
    includeTranslation: Bool
  ) throws {
    var payload: [String: Any] = [
      "title": document.title,
      "subtitle": document.subtitle,
      "segments": document.segments.map { segment in
        var item: [String: Any] = [
          "id": segment.id,
          "start": segment.startTime,
          "end": segment.endTime,
          "text": segment.text,
          "words": (segment.words ?? []).map { word in
            var wordItem: [String: Any] = [
              "word": word.word,
              "start": word.startTime,
              "end": word.endTime,
              "punctuation": word.punctuation,
            ]
            if let confidence = word.confidence {
              wordItem["confidence"] = confidence
            }
            return wordItem
          },
        ]
        if let confidence = segment.confidence {
          item["confidence"] = confidence
        }
        if includeTranslation, let translation = segment.translation, !translation.isEmpty {
          item["translation"] = translation.text
        }
        return item
      },
    ]
    if includeTranslation || document.translationSourceLanguage != nil || document.translationTargetLanguage != nil {
      payload["translation"] = [
        "source_lang": document.translationSourceLanguage?.rawValue ?? "",
        "target_lang": document.translationTargetLanguage?.rawValue ?? "",
      ]
    }
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }

  private static func expandMediaInputs(_ rawInputs: [String]) -> [URL] {
    var resolved: [URL] = []
    for raw in rawInputs {
      let url = URL(fileURLWithPath: raw).expandedFileURL
      if isDirectory(url) {
        resolved.append(contentsOf: mediaFiles(in: url))
      } else if isMediaFile(url) {
        resolved.append(url.standardizedFileURL)
      } else if containsWildcard(raw) {
        resolved.append(contentsOf: globMediaFiles(raw))
      }
    }
    var seen: Set<String> = []
    return resolved.filter { url in
      let key = url.standardizedFileURL.path
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }

  private static func mediaFiles(in directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    return enumerator.compactMap { item in
      guard let url = item as? URL, isMediaFile(url) else { return nil }
      return url.standardizedFileURL
    }.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
  }

  private static func globMediaFiles(_ raw: String) -> [URL] {
    var globResult = glob_t()
    defer { globfree(&globResult) }
    let expanded = NSString(string: raw).expandingTildeInPath
    guard glob(expanded, 0, nil, &globResult) == 0 else { return [] }
    guard let paths = globResult.gl_pathv else { return [] }
    var urls: [URL] = []
    for index in 0..<Int(globResult.gl_matchc) {
      guard let path = paths[index] else { continue }
      let url = URL(fileURLWithPath: String(cString: path))
      if isMediaFile(url) {
        urls.append(url.standardizedFileURL)
      }
    }
    return urls.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
  }

  private static func isMediaFile(_ url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    return supportedMediaExtensions.contains(url.pathExtension.lowercased())
  }

  private static func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func resolvedOutputDirectory(for input: URL, explicitOutputDir: URL?) -> URL {
    if let explicitOutputDir {
      return explicitOutputDir
    }
    return input.deletingLastPathComponent()
      .appendingPathComponent(input.deletingPathExtension().lastPathComponent, isDirectory: true)
  }

  private static func resolveASRModel(_ raw: String?, fallbackModel: ModelVariant) throws -> ModelVariant {
    if let raw {
      return try resolveModelVariant(raw, option: "--asr-model")
    }
    return fallbackModel
  }

  private static func resolveAlignerModel(_ raw: String?, enableAlign: Bool) throws -> ModelVariant? {
    guard enableAlign else { return nil }
    if let raw {
      let variant = try resolveModelVariant(raw, option: "--aligner-model")
      guard variant.isQwen3AlignerModel else {
        throw CLIError.usage("--aligner-model must be a Qwen3 ForcedAligner model")
      }
      return variant
    }
    return .qwen3ForcedAligner
  }

  private static func resolveModelVariant(_ raw: String, option: String) throws -> ModelVariant {
    if let variant = ModelVariant(rawValue: raw) {
      return variant
    }
    if let variant = ModelVariant.allCases.first(where: { $0.huggingFaceRepoId == raw }) {
      return variant
    }
    throw CLIError.usage("unknown \(option) '\(raw)'")
  }

  private static func resolveTTSModel(_ raw: String?, fallbackModelID: String) throws -> MLXTTSModelDefinition {
    let value = raw ?? fallbackModelID
    if let model = MLXTTSModelDefinition.availableModels.first(where: {
      $0.id == value || $0.huggingFaceRepo == value || $0.modelVariant.rawValue == value
    }) {
      return model
    }
    throw CLIError.usage("unknown --tts-model '\(value)'")
  }

  private static func transcriberType(for model: ModelVariant) -> TranscriberType {
    if model.isWhisperModel { return .whisper }
    if model.isQwen3ASRModel { return .qwen3 }
    if model.isFireRedASRModel { return .fireRed }
    if model.isCohereTranscribeModel { return .cohere }
    return .parakeet
  }

  private static func makeStyleConfiguration(
    originalHex: String,
    translationHex: String
  ) throws -> SubtitleStylesConfiguration {
    var configuration = defaultSubtitleStyles
    let originalColor = try subtitleColor(hex: originalHex)
    let translationColor = try subtitleColor(hex: translationHex)
    configuration.landscape.primary.fillColor = originalColor
    configuration.portrait.primary.fillColor = originalColor
    configuration.landscape.translation.fillColor = translationColor
    configuration.portrait.translation.fillColor = translationColor
    return configuration
  }

  private static func subtitleColor(hex: String) throws -> SubtitleColor {
    let normalized = try normalizeHexColor(hex)
    let start = normalized.index(after: normalized.startIndex)
    let rEnd = normalized.index(start, offsetBy: 2)
    let gEnd = normalized.index(rEnd, offsetBy: 2)
    let red = UInt8(normalized[start..<rEnd], radix: 16) ?? 255
    let green = UInt8(normalized[rEnd..<gEnd], radix: 16) ?? 255
    let blue = UInt8(normalized[gEnd..<normalized.endIndex], radix: 16) ?? 255
    return SubtitleColor(
      red: Double(red) / 255.0,
      green: Double(green) / 255.0,
      blue: Double(blue) / 255.0,
      alpha: 1
    )
  }

  private static func normalizeHexColor(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    guard value.count == 6, value.allSatisfy(\.isHexDigit) else {
      throw CLIError.usage("Invalid color '\(raw)'. Expected #RRGGBB.")
    }
    return "#\(value.uppercased())"
  }

  private static func parseFormats(_ raw: String) throws -> [CutFormat] {
    let values = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    guard !values.isEmpty else {
      throw CLIError.usage("output format list is empty")
    }
    var formats: [CutFormat] = []
    for value in values {
      guard let format = CutFormat(rawValue: value) else {
        let supported = CutFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw CLIError.usage("unsupported format '\(value)', supported formats: \(supported)")
      }
      if !formats.contains(format) {
        formats.append(format)
      }
    }
    return formats
  }

  private static func parseLanguage(_ raw: String, option: String) throws -> Language {
    guard let language = Language(rawValue: raw) else {
      throw CLIError.usage("unsupported \(option) '\(raw)'")
    }
    return language
  }

  private static func parseOrientation(_ raw: String) throws -> SubtitleOrientation {
    guard let orientation = SubtitleOrientation(rawValue: raw) else {
      throw CLIError.usage("--orientation must be landscape or portrait")
    }
    return orientation
  }

  private static func parseSubtitlePosition(_ raw: String) throws -> SubtitleTranslationPlacement {
    switch raw {
    case "original-top":
      return .below
    case "translated-top":
      return .above
    default:
      throw CLIError.usage("--subtitle-position must be original-top or translated-top")
    }
  }

  private static func value(after option: String, in arguments: [String], at index: inout Int) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
      throw CLIError.usage("\(option) requires a value")
    }
    index = valueIndex
    return arguments[valueIndex]
  }

  private static func parseIntOption(_ option: String, _ arguments: [String], _ index: inout Int) throws -> Int {
    let raw = try value(after: option, in: arguments, at: &index)
    guard let value = Int(raw) else {
      throw CLIError.usage("\(option) requires an integer")
    }
    return value
  }

  private static func parseDoubleOption(_ option: String, _ arguments: [String], _ index: inout Int) throws -> Double {
    let raw = try value(after: option, in: arguments, at: &index)
    guard let value = Double(raw), value.isFinite else {
      throw CLIError.usage("\(option) requires a number")
    }
    return value
  }

  private static func inlineValue(for option: String, in argument: String) -> String? {
    let prefix = option + "="
    guard argument.hasPrefix(prefix) else { return nil }
    return String(argument.dropFirst(prefix.count))
  }

  private static func number(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
      return value
    case let value as Float:
      return Double(value)
    case let value as Int:
      return Double(value)
    case let value as NSNumber:
      return value.doubleValue
    case let value as String:
      return Double(value)
    default:
      return nil
    }
  }

  private static func containsWildcard(_ raw: String) -> Bool {
    raw.contains("*") || raw.contains("?") || raw.contains("[")
  }

  private static func defaultPresentationSize(for orientation: SubtitleOrientation) -> CGSize {
    switch orientation {
    case .landscape:
      return CGSize(width: 1920, height: 1080)
    case .portrait:
      return CGSize(width: 1080, height: 1920)
    }
  }

  private static func srtTimestamp(_ time: TimeInterval) -> String {
    let totalMilliseconds = Int((max(time, 0) * 1000).rounded())
    let hours = totalMilliseconds / 3_600_000
    let minutes = (totalMilliseconds % 3_600_000) / 60_000
    let seconds = (totalMilliseconds % 60_000) / 1000
    let milliseconds = totalMilliseconds % 1000
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
  }

  private static func plainTimestamp(_ time: TimeInterval) -> String {
    let totalMilliseconds = Int((max(time, 0) * 1000).rounded())
    let minutes = totalMilliseconds / 60_000
    let seconds = (totalMilliseconds % 60_000) / 1000
    let milliseconds = totalMilliseconds % 1000
    return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
  }

  private static func topLevelUsage() -> String {
    """
    usage: cliptate-cli <cut|tts> [options]

    Commands:
      cut   Local media processing with ASR, subtitles, FCPXML, and rendered video output
      tts   Generate speech WAV from text
    """
  }

  private static func cutUsage() -> String {
    """
    usage: cliptate-cli cut [--transcript JSON_FILE] [-o OUTPUT_DIR] [--format FORMAT] video_inputs...

    Formats: ass,srt,fcpxml,video,txt,json
    """
  }

  private static func ttsUsage() -> String {
    """
    usage: cliptate-cli tts (--text TEXT | --text-file PATH) -o OUTPUT.wav [--tts-model MODEL] [--voice VOICE]
    """
  }

  private static func writeStandardError(_ text: String) {
    if let data = text.data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }
}

private extension URL {
  var expandedFileURL: URL {
    URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
  }
}
