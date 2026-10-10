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
  case dictionary(action: String, values: [String])

  public static func parse(_ arguments: [String]) throws -> Self {
    guard let command = arguments.first else { return .help }
    if arguments == ["--version"] { return .version }
    if arguments == ["--help"] || arguments == ["-h"] || arguments == [command, "--help"] {
      return .help
    }
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
