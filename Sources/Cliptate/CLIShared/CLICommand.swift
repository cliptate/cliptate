import Darwin
import Foundation

public enum CLIFormat: String, Sendable, CaseIterable { case text, json, srt, vtt, markdown }

public struct CLITranscribeOptions: Sendable {
  public var files: [String] = []
  public var format: CLIFormat = .text
  public var output: String?
  public var outputDirectory: String?
  public var overwrite = false
  public var model: String?
  public var language: String?
  public var useDictionary = true
  public var download = false
}

public enum CLICommand: Sendable {
  case help, version
  case transcribe(CLITranscribeOptions)
  case tts(CLITTSOptions)
  case dictionary(action: String, values: [String])

  public static func parse(_ arguments: [String]) throws -> Self {
    guard let command = arguments.first else { return .help }
    if arguments == ["--version"] { return .version }
    if arguments == ["--help"] || arguments == ["-h"] || arguments == [command, "--help"] {
      return .help
    }
    if command == "tts" { return .tts(try CLITTSOptions.parse(Array(arguments.dropFirst()))) }
    if command == "dictionary" {
      guard arguments.count >= 2 else { throw invalid(command) }
      let action = arguments[1]
      let values = Array(arguments.dropFirst(2))
      switch action {
      case "list", "export": guard values.isEmpty else { throw invalid(action) }
      case "add", "remove": guard !values.isEmpty else { throw invalid(action) }
      case "import": guard values.count == 1 else { throw invalid(action) }
      default: throw invalid(action)
      }
      return .dictionary(action: action, values: values)
    }
    guard command == "transcribe" else { throw invalid(command) }
    var options = CLITranscribeOptions()
    var index = 1
    var pathsOnly = false
    while index < arguments.count {
      let argument = arguments[index]
      index += 1
      func value() throws -> String {
        guard index < arguments.count else { throw invalid(argument) }
        let result = arguments[index]
        guard !result.isEmpty, !result.hasPrefix("-") else { throw invalid(argument) }
        index += 1
        return result
      }
      if pathsOnly {
        options.files.append(argument)
        continue
      }
      switch argument {
      case "--": pathsOnly = true
      case "-f", "--format":
        let raw = try value()
        guard let format = CLIFormat(rawValue: raw) else { throw invalid(raw) }
        options.format = format
      case "-o", "--output": options.output = try value()
      case "--output-dir": options.outputDirectory = try value()
      case "--model": options.model = try value()
      case "--language": options.language = try value()
      case "--overwrite": options.overwrite = true
      case "--no-dictionary": options.useDictionary = false
      case "--download": options.download = true
      default:
        guard !argument.hasPrefix("-") else { throw invalid(argument) }
        options.files.append(argument)
      }
    }
    guard !options.files.isEmpty else { throw invalid("transcribe <file...>") }
    guard options.output == nil || (options.files.count == 1 && options.outputDirectory == nil)
    else {
      throw invalid("--output")
    }
    if options.files.count > 1 && [.srt, .vtt].contains(options.format)
      && options.outputDirectory == nil
    {
      throw CLIError(
        String(
          localized: "Multiple subtitle files require --output-dir.", bundle: CLILocalization.bundle
        ))
    }
    return .transcribe(options)
  }

  public static func importEntries(_ data: Data, json: Bool = false) throws -> [String] {
    guard var text = String(data: data, encoding: .utf8) else {
      throw CLIError(
        String(
          localized: "Dictionary files must be UTF-8 text or a JSON string array.",
          bundle: CLILocalization.bundle))
    }
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    if json || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
      return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }
    return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  private static func invalid(_ value: String) -> CLIError {
    CLIError(
      String(
        format: String(
          localized: "Invalid command or argument: %@. Run cliptate --help.",
          bundle: CLILocalization.bundle), value))
  }
}

public enum CLIOutput {
  public static func json(_ files: [CLIFileResult]) throws -> Data {
    struct Batch: Encodable { let files: [CLIFileResult] }
    return try encode(Batch(files: files))
  }

  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value) + Data([10])
  }

  public static func render(_ file: CLIFileResult, format: CLIFormat) throws -> String {
    switch format {
    case .json: return String(decoding: try json([file]), as: UTF8.self)
    case .text: return file.segments.map(\.text).joined(separator: " ") + "\n"
    case .markdown:
      return file.segments.map { segment in
        let speaker =
          segment.speakerId.map {
            " **"
              + String(
                format: String(localized: "Speaker %lld", bundle: CLILocalization.bundle), $0 + 1)
              + "**"
          } ?? ""
        return "[\(timestamp(segment.start, separator: "."))]\(speaker) \(segment.text)"
      }.joined(separator: "\n\n") + "\n"
    case .srt, .vtt:
      let separator = format == .srt ? "," : "."
      let cues = file.segments.enumerated().map { index, segment in
        "\(index + 1)\n\(timestamp(segment.start, separator: separator)) --> \(timestamp(segment.end, separator: separator))\n\(segment.text)\n"
      }.joined(separator: "\n")
      return (format == .vtt ? "WEBVTT\n\n" : "") + cues + "\n"
    }
  }

  private static func timestamp(_ seconds: Double, separator: String) -> String {
    let milliseconds = Int(
      (seconds.isFinite ? min(max(seconds, 0), 359_999_999) * 1000 : 0).rounded())
    return String(
      format: "%02d:%02d:%02d%@%03d", milliseconds / 3_600_000,
      milliseconds / 60_000 % 60, milliseconds / 1000 % 60, separator, milliseconds % 1000)
  }
}

public struct CLITTSOptions: Sendable {
  public var text: String?
  public var textFile: String?
  public var output = ""
  public var model: String?
  public var language: String?
  public var voice: String?
  public var emotion: String?
  public var referenceAudio: String?
  public var referenceText: String?
  public var variant: String?
  public var overwrite = false
  public var download = false
  public var json = false

  static func parse(_ arguments: [String]) throws -> Self {
    var options = Self()
    var index = 0
    var seen = Set<String>()
    func invalid() -> CLIError {
      CLIError(
        String(
          localized: "Invalid TTS arguments. Run cliptate tts --help.",
          bundle: CLILocalization.bundle))
    }
    while index < arguments.count {
      var option = arguments[index]
      index += 1
      if option == "-o" { option = "--output" }
      if option == "--tts-model" { option = "--model" }
      guard seen.insert(option).inserted else { throw invalid() }
      func value() throws -> String {
        guard index < arguments.count, !arguments[index].isEmpty,
          !arguments[index].hasPrefix("--")
        else { throw invalid() }
        let result = arguments[index]
        index += 1
        return result
      }
      switch option {
      case "--text": options.text = try value()
      case "--text-file": options.textFile = try value()
      case "--output": options.output = try value()
      case "--model": options.model = try value()
      case "--language": options.language = try value()
      case "--voice": options.voice = try value()
      case "--emotion": options.emotion = try value()
      case "--reference-audio": options.referenceAudio = try value()
      case "--reference-text": options.referenceText = try value()
      case "--variant":
        let raw = try value()
        guard ["automatic", "short", "extended"].contains(raw) else { throw invalid() }
        options.variant = raw
      case "--format":
        guard try value() == "json" else { throw invalid() }
        options.json = true
      case "--overwrite": options.overwrite = true
      case "--download": options.download = true
      default: throw invalid()
      }
    }
    guard (options.text != nil) != (options.textFile != nil),
      !options.output.isEmpty, options.output != "-",
      URL(fileURLWithPath: options.output).pathExtension.lowercased() == "wav",
      (options.referenceText == nil) == (options.referenceAudio == nil),
      options.referenceAudio == nil || (options.voice == nil && options.emotion == nil)
    else { throw invalid() }
    if let text = options.text { _ = try validatedText(Data(text.utf8)) }
    if let referenceText = options.referenceText { _ = try validatedText(Data(referenceText.utf8)) }
    return options
  }

  public static func validatedText(_ data: Data) throws -> String {
    guard data.count <= 1_048_576, var text = String(data: data, encoding: .utf8) else {
      throw CLIError(
        String(
          localized: "TTS input must be UTF-8 text no larger than 1 MiB.",
          bundle: CLILocalization.bundle))
    }
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw CLIError(
        String(localized: "Enter some text to synthesize.", bundle: CLILocalization.bundle))
    }
    return text
  }
}

/// The app writes only a private staging file. The CLI publishes it after success,
/// keeping audio out of the framed JSON transport and existing output intact on failure.
public final class CLITTSOutput {
  public let destination: URL
  public let stagingURL: URL
  private let directory: URL
  private let overwrite: Bool

  public init(destination: URL, inputs: [URL], overwrite: Bool) throws {
    self.destination = destination.standardizedFileURL
    self.overwrite = overwrite
    let resolved = destination.resolvingSymlinksInPath().standardizedFileURL
    guard !inputs.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == resolved })
    else {
      throw CLIError(
        String(
          localized: "An output path cannot replace an input file.", bundle: CLILocalization.bundle)
      )
    }
    if !overwrite && FileManager.default.fileExists(atPath: destination.path) {
      throw CLIError(
        String(
          format: String(
            localized: "Output already exists: %@. Use --overwrite to replace it.",
            bundle: CLILocalization.bundle), destination.path))
    }
    directory = destination.deletingLastPathComponent().appendingPathComponent(
      ".cliptate-tts-" + UUID().uuidString, isDirectory: true)
    stagingURL = directory.appendingPathComponent("audio.wav")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    do { try Data().write(to: stagingURL) } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  deinit { try? FileManager.default.removeItem(at: directory) }

  public func publish(expectedBytes: Int) throws {
    let handle = try FileHandle(forReadingFrom: stagingURL)
    defer { try? handle.close() }
    let header = try handle.read(upToCount: 12) ?? Data()
    let size = try handle.seekToEnd()
    guard expectedBytes > 44, size == UInt64(expectedBytes),
      header.prefix(4) == Data("RIFF".utf8), header.suffix(4) == Data("WAVE".utf8)
    else {
      throw CLIChannel.protocolError()
    }
    // link() refuses an existing destination atomically. Both files are on the same volume.
    let result =
      overwrite
      ? rename(stagingURL.path, destination.path) : link(stagingURL.path, destination.path)
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }
}
