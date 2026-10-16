import AppKit
import Darwin
import Foundation

import CliptateCore

@main
struct CliptateCommand {
  @MainActor static func main() async {
    signal(SIGPIPE, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let task = Task { await run() }
    let sources = [SIGINT, SIGTERM].map { number in
      let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
      source.setEventHandler { task.cancel() }
      source.resume()
      return source
    }
    let status = await task.value
    for source in sources { source.cancel() }
    exit(status)
  }

  @MainActor private static func run() async -> Int32 {
    do {
      let command: CLICommand
      do { command = try CLICommand.parse(Array(CommandLine.arguments.dropFirst())) } catch {
        stderr(error.localizedDescription)
        return 2
      }
      switch command {
      case .help:
        try stdout(Data((help + historyHelp).utf8))
        return 0
      case .version:
        let app = applicationURL()
        let version =
          app.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "CFBundleShortVersionString")
          as? String ?? "development"
        try stdout(Data("cliptate \(version) (protocol 1)\n".utf8))
        return 0
      case .tts(let options):
        let inputs = [options.textFile == "-" ? nil : options.textFile, options.referenceAudio]
          .compactMap { $0 }.map(path)
        let output = try CLITTSOutput(
          destination: path(options.output), inputs: inputs, overwrite: options.overwrite)
        let text: String
        if let inline = options.text {
          text = inline
        } else if options.textFile == "-" {
          text = try await readStdin()
        } else {
          guard let filename = options.textFile else { throw CLIChannel.protocolError() }
          let url = path(filename)
          guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
          }
          let file = try FileHandle(forReadingFrom: url)
          defer { try? file.close() }
          var data = Data()
          while data.count <= 1_048_576 {
            let chunk = try file.read(upToCount: min(16_384, 1_048_577 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
          }
          text = try CLITTSOptions.validatedText(data)
        }
        try Task.checkCancellation()
        let reference = try options.referenceAudio.map {
          let url = path($0)
          let file = try FileHandle(forReadingFrom: url)
          try file.close()
          return try url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        let bookmark = try output.stagingURL.bookmarkData(
          options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let event = try await execute(
          CLIRequest(
            operation: .tts, bookmark: reference, model: options.model, language: options.language,
            download: options.download,
            tts: CLITTSParameters(
              text: text, voice: options.voice, emotion: options.emotion,
              referenceText: options.referenceText, variant: options.variant),
            outputBookmark: bookmark))
        guard var audio = event.audio else { throw CLIChannel.protocolError() }
        try Task.checkCancellation()
        try output.publish(expectedBytes: audio.bytes)
        audio.file = output.destination.path
        try stdout(options.json ? CLIOutput.encode(audio) : Data((audio.file + "\n").utf8))
        return 0
      case .history(let query):
        let event = try await execute(CLIRequest(operation: .history, history: query))
        guard let page = event.history else { throw CLIChannel.protocolError() }
        try stdout(try CLIOutput.encode(page))
        return 0
      case .dictionary(let action, let values):
        let entries =
          action == "import"
          ? try CLICommand.importEntries(
            Data(contentsOf: path(values[0])),
            json: path(values[0]).pathExtension.lowercased() == "json") : values
        let operation: CLIOperation =
          switch action {
          case "add", "import": .dictionaryAdd
          case "remove": .dictionaryRemove
          default: .dictionaryList
          }
        let event = try await execute(CLIRequest(operation: operation, entries: entries))
        guard let entries = event.entries else { throw CLIChannel.protocolError() }
        try stdout(try CLIOutput.encode(entries))
        return 0
      case .transcribe(let options):
        let targets = try outputTargets(options)
        var results: [CLIFileResult] = []
        var failed = false
        do {
          for (index, filename) in options.files.enumerated() {
            try Task.checkCancellation()
            var result: CLIFileResult
            do {
              let url = path(filename)
              guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw CocoaError(.fileReadNoSuchFile)
              }
              // An implicit bookmark transfers this process's read access to the sandboxed app.
              let bookmark = try url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
              let event = try await execute(
                CLIRequest(
                  operation: .transcribe, bookmark: bookmark,
                  model: options.model, language: options.language,
                  useDictionary: options.useDictionary, download: options.download))
              guard let transcript = event.transcript else { throw CLIChannel.protocolError() }
              result = transcript
              result.file = url.path
              if let target = targets[index] {
                try write(
                  Data(try CLIOutput.render(result, format: options.format).utf8), to: target,
                  overwrite: options.overwrite)
              } else if options.format != .json {
                if options.files.count > 1 {
                  try stdout(
                    Data(
                      "\(options.format == .markdown ? "#" : "===") \(filename)\(options.format == .markdown ? "" : " ===")\n\n"
                        .utf8))
                }
                try stdout(Data(try CLIOutput.render(result, format: options.format).utf8))
              }
            } catch {
              if Task.isCancelled || error is CancellationError { throw CancellationError() }
              failed = true
              stderr("\(filename): \(error.localizedDescription)")
              result = CLIFileResult(file: path(filename).path, error: error.localizedDescription)
            }
            results.append(result)
          }
        } catch {
          if options.format == .json && options.output == nil && options.outputDirectory == nil {
            try stdout(try CLIOutput.json(results))
          }
          throw error
        }
        if options.format == .json && options.output == nil && options.outputDirectory == nil {
          try stdout(try CLIOutput.json(results))
        }
        return failed ? 1 : 0
      }
    } catch {
      if Task.isCancelled || error is CancellationError { return 130 }
      stderr(error.localizedDescription)
      return 1
    }
  }

  private static func readStdin() async throws -> String {
    // poll() keeps piped input cancellable even when its producer has not closed stdout.
    let reader = Task.detached {
      var data = Data()
      var bytes = [UInt8](repeating: 0, count: 16_384)
      while true {
        try Task.checkCancellation()
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 100)
        if ready < 0 {
          if errno == EINTR { continue }
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if ready == 0 { continue }
        let count = read(STDIN_FILENO, &bytes, bytes.count)
        if count < 0 {
          if errno == EINTR { continue }
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if count == 0 { return try CLITTSOptions.validatedText(data) }
        data.append(contentsOf: bytes.prefix(count))
        if data.count > 1_048_576 { return try CLITTSOptions.validatedText(data) }
      }
    }
    return try await withTaskCancellationHandler {
      try await reader.value
    } onCancel: {
      reader.cancel()
    }
  }

  @MainActor private static func execute(_ request: CLIRequest) async throws -> CLIEvent {
    guard let app = applicationURL() else {
      throw CLIError(
        String(
          localized:
            "Cliptate was not found. Install the direct-download app or set CLIPTATE_APP to its path.",
          bundle: CLILocalization.bundle))
    }
    let identity = AppIdentity(bundleIdentifier: Bundle(url: app)?.bundleIdentifier)
    return try await CLIRequestClient(
      launch: { try await launchApplication(app, for: $0) }, identity: identity
    ).execute(request, progress: { stderr($0) })
  }

  @MainActor private static func launchApplication(_ app: URL, for endpoint: CLIEndpoint)
    async throws
  {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    // Respect an explicitly selected development bundle instead of an older installation.
    let applications = NSWorkspace.shared.runningApplications
    let sameBundle = applications.contains {
      $0.bundleURL?.standardizedFileURL == app.standardizedFileURL
    }
    let identifier = Bundle(url: app)?.bundleIdentifier
    configuration.createsNewApplicationInstance =
      !sameBundle && applications.contains { $0.bundleIdentifier == identifier }
    configuration.hides = !sameBundle
    configuration.addsToRecentItems = false
    configuration.arguments = ["--cliptate-cli"]
    try await NSWorkspace.shared.open(
      [endpoint.url], withApplicationAt: app, configuration: configuration)
  }

  @MainActor private static func applicationURL() -> URL? {
    if let explicit = ProcessInfo.processInfo.environment["CLIPTATE_APP"] { return path(explicit) }
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    if app.pathExtension == "app" { return app }
    return NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: AppIdentity.production.rawValue)
  }

  private static func path(_ value: String) -> URL {
    URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
  }

  private static func outputTargets(_ options: CLITranscribeOptions) throws -> [URL?] {
    let targets: [URL?]
    if let output = options.output {
      targets = [path(output)]
    } else if let directory = options.outputDirectory {
      let folder = path(directory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let suffix =
        options.format == .text
        ? "txt" : options.format == .markdown ? "md" : options.format.rawValue
      targets = options.files.map {
        folder.appendingPathComponent(path($0).deletingPathExtension().lastPathComponent)
          .appendingPathExtension(suffix)
      }
    } else {
      targets = options.files.map { _ in nil }
    }
    let paths = targets.compactMap { $0?.resolvingSymlinksInPath().path }
    guard Set(paths).count == paths.count else {
      throw CLIError(
        String(
          localized: "Input filenames produce duplicate output paths. Transcribe them separately.",
          bundle: CLILocalization.bundle))
    }
    let inputPaths = Set(options.files.map { path($0).resolvingSymlinksInPath().path })
    for target in targets.compactMap({ $0 }) {
      guard !inputPaths.contains(target.resolvingSymlinksInPath().path) else {
        throw CLIError(
          String(
            localized: "An output path cannot replace an input file.",
            bundle: CLILocalization.bundle))
      }
      if !options.overwrite && FileManager.default.fileExists(atPath: target.path) {
        throw CLIError(
          String(
            format: String(
              localized: "Output already exists: %@. Use --overwrite to replace it.",
              bundle: CLILocalization.bundle), target.path))
      }
    }
    return targets
  }

  private static func write(_ data: Data, to url: URL, overwrite: Bool) throws {
    if overwrite {
      try data.write(to: url, options: .atomic)
      return
    }
    // O_EXCL makes the no-overwrite guarantee survive another process creating the file.
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: data)
    try handle.close()
  }

  private static func stdout(_ data: Data) throws {
    try FileHandle.standardOutput.write(contentsOf: data)
  }
  private static func stderr(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
  }

  private static let help = String(
    localized: "cli.help",
    defaultValue: """
      Cliptate CLI - local transcription, speech generation, and recognition dictionary.

      Requires the direct-download macOS app; starts it in the background if needed.
      Uses the app's model, language, segmentation, alignment, and dictionary settings.
      Transcription does not create projects or transcript-history entries.
      For AI agents and scripts, use --format json and inspect both exit status and files[].error.

      USAGE
        cliptate transcribe <file...> [options]
        cliptate tts (--text TEXT | --text-file PATH | --text-file -) -o OUTPUT.wav [options]
        cliptate dictionary list | export
        cliptate dictionary add <word...>
        cliptate dictionary remove <word...>
        cliptate dictionary import <file.txt|file.json>
        cliptate --help | -h
        cliptate --version

      TRANSCRIBE OPTIONS
        -f, --format <format>       text (default), json, srt, vtt, markdown
        -o, --output <file>         Save one input's result; cannot combine with --output-dir
            --output-dir <dir>     Create directory and save one result file per input
            --overwrite            Allow replacing existing output files (never input files)
            --model <model ID>     Override ASR model for this run; default: app setting
            --language <code>      Override language for this run; default: app setting
            --no-dictionary        Skip the app's recognition dictionary for this run
            --download             Allow downloading missing ASR, VAD, and alignment models
            --                     Treat all remaining arguments as file paths

      TTS OPTIONS
        --text <text>              Text to synthesize (quote it as one argument)
        --text-file <path|->       UTF-8 text file, or - to read stdin; maximum 1 MiB
        -o, --output <file.wav>     Required WAV destination; parent directory must exist
        --model <model ID>         TTS model ID or repository; default: app TTS setting
        --tts-model <model ID>     Alias for --model
        --language <code>          auto, en, zh, ja, ko, de, fr, ru, pt, es, it
        --voice <voice>            CustomVoice speaker name or VoiceDesign description
        --emotion <description>    CustomVoice emotion/style prompt
        --reference-audio <path>   Base voice-cloning audio; requires --reference-text
        --reference-text <text>    Transcript of reference audio
        --variant <variant>        automatic, short, extended; default: app TTS setting
        --download                Allow downloading the missing TTS model
        --overwrite               Replace an existing output only after successful synthesis
        --format json             Print {file, model, bytes} metadata instead of the output path
        Text sources are exclusive. Output is mono float32 WAV at the model's native rate.
        Voice flags must match the model family; overrides never change saved settings.
        Reference audio is explicit; saved GUI reference audio is not used by CLI commands.
        TTS does not create history entries. Progress/errors go to stderr.
        One CLI transcription or TTS request runs at a time; dictionary requests remain available.
        Example CustomVoice speakers: Vivian, Serena, Ryan, Aiden, Ono_Anna, Sohee.

      INPUT AND DEFAULTS
        Inputs are readable local audio/video file paths, e.g. WAV, MP3, or MP4.
        Relative paths use the current directory; quote paths and phrases with spaces.
        Transcription has no stdin input. Use -- before input paths starting with "-".
        Pass option values as separate arguments, e.g. --format json (not --format=json).
        Model IDs are raw identifiers, e.g. qwen3-asr-0.6b-8bit or parakeet-v3,
        not display names or Hugging Face repository paths.
        Language codes include auto (detect), en, zh, ja, ko, de, es, and fr;
        the selected model must support the requested language.
        Overrides do not change saved app settings. Missing models fail without --download.
        Only one CLI transcription or TTS request runs at a time in the app; batch inputs run sequentially.

      OUTPUT AND JSON
        Results go to stdout; progress and errors go to stderr. Keep the streams separate.
        With --output or --output-dir, results are written to files instead of stdout.
        --output-dir uses <input-basename>.txt|json|srt|vtt|md, according to --format.
        Existing outputs require --overwrite; duplicate output basenames are rejected.
        Multiple SRT/VTT inputs require --output-dir. Batch text/Markdown include file headings.
        JSON always wraps results in a files array, including single-input and saved JSON:
        {"files":[{"file":"/path/to/a.wav","model":"model-id","duration":1.42,
          "segments":[{"id":"segment-id","text":"Hello.","start":0,"end":1.42,"speakerId":0}]},
          {"file":"/path/to/missing.wav","segments":[],"error":"File not found"}]}
        file: absolute input path; segments: array of id, text, start, end, optional speakerId.
        start, end, and optional duration are seconds; speakerId is zero-based when available.
        model, duration, speakerId, and error are omitted when unavailable.
        Failed inputs have empty segments and error; remaining inputs still run.
        Batch JSON on stdout is emitted after all inputs finish. Exit 1 can still contain
        successful results; inspect every files entry. Setup failures may produce no JSON.
        Ctrl+C/SIGTERM stops later inputs; completed output remains available. Interrupted
        stdout JSON contains completed inputs, not an entry for the cancelled input.
        Transcription has no fixed timeout; initial app connection retries for up to 30 seconds.

      DICTIONARY
        list/export: print the current JSON string array.
        add/remove: accept one or more words/phrases as separate arguments.
        import: append UTF-8 lines or a JSON string array; does not replace existing entries.
        Entries are trimmed, blanks dropped, and duplicates compared ignoring case/diacritics.
        Mutations persist app settings and return the full updated JSON string array.
        Do not blindly retry a mutation after a lost connection; read dictionary list first.

      ENVIRONMENT
        CLIPTATE_APP=/path/to/Cliptate.app selects the app bundle.
        Otherwise the embedded helper uses its app; a standalone CLI finds the installed app.

      EXIT STATUS
        0  Success
        1  Execution/file failure (a batch may have partial results)
        2  Invalid command or arguments
        130  Interrupted (Ctrl+C or SIGTERM)

      EXAMPLES
        cliptate transcribe "interview.mp4" --format json
        cliptate transcribe a.wav b.mp4 --format json > transcripts.json
        cliptate transcribe interview.wav --format srt --output interview.srt
        cliptate transcribe a.wav b.mp4 --format vtt --output-dir subtitles
        cliptate transcribe recording.wav --model qwen3-asr-0.6b-8bit --language zh --download
        cliptate transcribe recording.wav --language auto --no-dictionary
        cliptate transcribe --format json -- -recording.wav
        cliptate tts --text "你好，欢迎使用 Cliptate。" --language zh -o speech.wav --download
        cliptate tts --text-file narration.txt -o narration.wav --format json
        printf 'Hello world.' | cliptate tts --text-file - -o hello.wav
        cliptate dictionary add "Cliptate" "Ada Lovelace"
        cliptate dictionary import words.txt
        cliptate dictionary export > words.json

      """, bundle: CLILocalization.bundle)
}

private extension CliptateCommand {
  static let historyHelp = String(localized: """
    HISTORY
      cliptate history list [filters]
      cliptate history show <session UUID> [--limit N] [--cursor TOKEN]
      cliptate history corrections [filters]
      --source <source>        voiceDictation, fileTranscription, ttsSynthesis
      --since <ISO-8601>       Inclusive lower time bound, e.g. 2026-10-01T00:00:00Z
      --until <ISO-8601>       Inclusive upper time bound
      --search <text>          Search transcript, filename, or correction evidence
      --session <UUID>         Restrict list/corrections to one session
      --corrections-only       List sessions that contain correction records
      --limit <N>              Records per page: 1-200, default 50
      --cursor <TOKEN>         Continue with nextCursor and the same filters
      --format json            Optional; history always returns JSON
      JSON: {schemaVersion, sessions, lines, corrections, nextCursor?}.
      List returns summaries; show pages transcript lines followed by correction records.
      Corrections pages evidence directly, newest-first by correction time. List uses session time.
      Dates are UTC ISO-8601. Follow nextCursor until absent; pages also have a byte limit.
      Changing text while paging show invalidates its cursor; restart that query.
      Correction kinds: phrase (AI Cut word pairs), dictation (before/after whole text).
      Status: applied, reverted, superseded. Applied means edited then, not user approval.
      No bookmarks, audio paths, recordings, or word timing are included.
      Retention: dictation 24 hours; file transcription 30 days. Older data has no invented corrections.
      AI workflow: query history corrections and dictionary list; analyze terms; dictionary add/import.
      Add correct vocabulary, not error spellings, grammar rewrites, or entire sentences.
      History reads remain available during CLI transcription or speech generation.

    """, bundle: CLILocalization.bundle)
}
