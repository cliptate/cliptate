import AppKit
import Darwin
import Foundation

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

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
        try stdout(Data(help.utf8))
        return 0
      case .version:
        let app = applicationURL()
        let version =
          app.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "CFBundleShortVersionString")
          as? String ?? "development"
        try stdout(Data("cliptate \(version) (protocol 1)\n".utf8))
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

  @MainActor private static func execute(_ request: CLIRequest) async throws -> CLIEvent {
    guard let app = applicationURL() else {
      throw CLIError(
        String(
          localized:
            "Cliptate was not found. Install the direct-download app or set CLIPTATE_APP to its path.",
          bundle: CLILocalization.bundle))
    }
    let endpoint = CLIEndpoint()
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
    let deadline = ContinuousClock.now + .seconds(30)
    var channel: CLIChannel?
    while ContinuousClock.now < deadline {
      try Task.checkCancellation()
      let candidate = CLIChannel()
      do {
        // A deadline also bounds a port occupied by a process that never responds.
        let timeout = Task {
          try? await Task.sleep(for: .seconds(2))
          if !Task.isCancelled { candidate.cancel() }
        }
        defer { timeout.cancel() }
        try await candidate.start()
        try await candidate.send(CLIEvent(.hello, token: endpoint.id))
        let hello = try await candidate.receive(CLIEvent.self)
        guard hello.kind == .hello, hello.token == endpoint.proof(for: "server") else {
          throw CLIChannel.protocolError()
        }
        channel = candidate
        break
      } catch {
        candidate.cancel()
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(150))
      }
    }
    guard let channel else {
      throw CLIError(
        String(
          localized:
            "Could not connect to Cliptate within 30 seconds. Check that it is a direct-download build and the CLI port is available.",
          bundle: CLILocalization.bundle))
    }
    defer { channel.cancel() }
    var authorized = request
    authorized.authorization = endpoint.proof(for: "client")
    try await channel.send(authorized)
    while true {
      let event = try await channel.receive(CLIEvent.self)
      switch event.kind {
      case .progress: if let message = event.message { stderr(message) }
      case .result: return event
      case .failure:
        throw CLIError(event.message ?? CLIChannel.protocolError().localizedDescription)
      case .hello: throw CLIChannel.protocolError()
      }
    }
  }

  @MainActor private static func applicationURL() -> URL? {
    if let explicit = ProcessInfo.processInfo.environment["CLIPTATE_APP"] { return path(explicit) }
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    if app.pathExtension == "app" { return app }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.voicepink.voicepinkpro")
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
      cliptate transcribe <file...> [options]
      cliptate dictionary list | export
      cliptate dictionary add <word...>
      cliptate dictionary remove <word...>
      cliptate dictionary import <UTF-8 text or JSON file>

      -f, --format text|json|srt|vtt|markdown   (default: text)
      -o, --output <file>                     Single-file output
          --output-dir <directory>           One output per input
          --overwrite                        Replace existing output files
          --model <model ID>                  Temporary ASR model override
          --language <language code>         Temporary language override
          --no-dictionary                    Ignore the app's dictionary
          --download                         Download missing required models
          --                                 Treat remaining arguments as paths
          --version | --help

      The direct-download Cliptate app starts in the background when needed.
      Results go to stdout; progress and errors go to stderr.
      Exit codes: 0 success, 1 failure, 2 usage error, 130 interrupted.

      """, bundle: CLILocalization.bundle)
}
