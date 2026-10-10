import CoreGraphics
import Foundation

enum SubtitleFileExporter {
  static func export(
    mediaFiles: [MediaFile],
    formats: Set<SubtitleExportFormat>,
    directory: URL,
    filterSilentSegments: Bool
  ) throws {
    guard !formats.isEmpty else { return }
    try ensureDirectoryExists(at: directory)

    var nameUsage: [String: Int] = [:]

    for media in mediaFiles {
      guard !media.segments.isEmpty else { continue }
      let baseName = sanitizedFileName(from: media.url.deletingPathExtension().lastPathComponent)
      let collisionCount = nameUsage[baseName, default: 0]
      nameUsage[baseName] = collisionCount + 1
      let resolvedName = collisionCount == 0 ? baseName : "\(baseName)-\(collisionCount + 1)"

      for format in formats {
        let fileURL = directory.appendingPathComponent(resolvedName)
          .appendingPathExtension(format.fileExtension)
        let content = makeContent(
          for: media, format: format, filterSilentSegments: filterSilentSegments)
        try encodedData(for: content, format: format).write(to: fileURL, options: .atomic)
      }
    }
  }

  private static func encodedData(for content: String, format: SubtitleExportFormat) throws -> Data {
    guard let utf8Data = content.data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }

    switch format {
    case .ass:
      return Data([0xEF, 0xBB, 0xBF]) + utf8Data
    case .srt, .txt:
      return utf8Data
    }
  }

  private static func makeContent(
    for media: MediaFile,
    format: SubtitleExportFormat,
    filterSilentSegments: Bool
  ) -> String {
    switch format {
    case .srt:
      return makeSRT(for: media)
    case .ass:
      return makeASS(for: media, filterSilentSegments: filterSilentSegments)
    case .txt:
      return makePlainText(for: media)
    }
  }

  private static func makeSRT(for media: MediaFile) -> String {
    var blocks: [String] = []
    var index = 1

    for segment in media.segments {
      let primaryText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let translation = media.translation(for: segment)?.text.trimmingCharacters(
        in: .whitespacesAndNewlines)
      if (primaryText.isEmpty) && (translation?.isEmpty ?? true) { continue }
      let start = srtTimestamp(segment.startTime)
      let end = srtTimestamp(segment.endTime)

      var lines: [String] = []
      if let translation, !translation.isEmpty, media.translationPlacement == .above {
        lines.append(translation)
      }
      if !primaryText.isEmpty {
        lines.append(primaryText)
      }
      if let translation, !translation.isEmpty, media.translationPlacement == .below {
        lines.append(translation)
      }

      blocks.append("\(index)")
      blocks.append("\(start) --> \(end)")
      blocks.append(contentsOf: lines)
      blocks.append("")
      index += 1
    }

    return blocks.joined(separator: "\n")
  }

  private static func makeASS(for media: MediaFile, filterSilentSegments: Bool) -> String {
    let orientation: SubtitleOrientation = media.orientation == .portrait ? .portrait : .landscape
    return ASSGenerator.makeASS(
      segments: media.segments,
      orientation: orientation,
      filterSilentSegments: filterSilentSegments,
      effects: media.effects,
      translationPlacement: media.translationPlacement,
      styleConfiguration: media.styleConfiguration
    )
  }

  private static func defaultPresentationSize(for orientation: SubtitleOrientation) -> CGSize {
    switch orientation {
    case .portrait:
      return CGSize(width: 1080, height: 1920)
    case .landscape:
      return CGSize(width: 1920, height: 1080)
    }
  }

  private static func makePlainText(for media: MediaFile) -> String {
    var lines: [String] = []

    for segment in media.segments {
      let primaryText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let translation = media.translation(for: segment)?.text.trimmingCharacters(
        in: .whitespacesAndNewlines)
      if (primaryText.isEmpty) && (translation?.isEmpty ?? true) { continue }
      let start = plainTimestamp(segment.startTime)
      let end = plainTimestamp(segment.endTime)
      var entryLines: [String] = []
      entryLines.append("[\(start) - \(end)] \(primaryText)")
      if let translation, !translation.isEmpty {
        entryLines.append("    ↳ \(translation)")
      }
      lines.append(contentsOf: entryLines)
    }

    return lines.joined(separator: "\n")
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

  private static func sanitizedFileName(from raw: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.whitespacesAndNewlines)
    let components = raw.components(separatedBy: invalid).filter { !$0.isEmpty }
    let sanitized = components.joined(separator: "_")
    return sanitized.isEmpty ? "Subtitle" : sanitized
  }

  private static func ensureDirectoryExists(at url: URL) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
  }
}
