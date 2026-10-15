import CliptateCore
import AVFoundation
import CoreGraphics
import Foundation

public enum MediaOrientation: String {
  case landscape
  case portrait
}

extension MediaOrientation {
  init(_ orientation: SubtitleOrientation) {
    switch orientation {
    case .landscape: self = .landscape
    case .portrait: self = .portrait
    }
  }

  fileprivate var subtitleOrientation: SubtitleOrientation {
    switch self {
    case .landscape: return .landscape
    case .portrait: return .portrait
    }
  }
}

/// 表示单个文件的媒体信息
public struct MediaFile {
  public let url: URL
  public let segments: [Segment]
  public let duration: TimeInterval
  public let presentationSize: CGSize?
  public let effects: [String: SegmentEffectState]
  public let translationPlacement: SubtitleTranslationPlacement
  public let styleConfiguration: SubtitleStylesConfiguration

  public init(
    url: URL,
    segments: [Segment],
    duration: TimeInterval,
    presentationSize: CGSize? = nil,
    effects: [String: SegmentEffectState] = [:],
    translationPlacement: SubtitleTranslationPlacement = .below,
    styleConfiguration: SubtitleStylesConfiguration? = nil
  ) {
    let resolvedStyles = styleConfiguration ?? defaultSubtitleStyles
    self.url = url
    self.segments = segments
    self.duration = duration
    self.presentationSize = presentationSize
    self.effects = effects
    self.translationPlacement = translationPlacement
    self.styleConfiguration = resolvedStyles
  }

  /// 获取指定段落的效果信息
  public func effect(for segment: Segment) -> SegmentEffectState? {
    effects[segment.id]
  }

  /// 获取指定段落的翻译
  public func translation(for segment: Segment) -> SegmentTranslation? {
    segment.translation
  }

  public var orientation: MediaOrientation {
    let actual: SubtitleOrientation
    if let presentationSize, presentationSize.width > 0, presentationSize.height > 0 {
      actual = presentationSize.height >= presentationSize.width ? .portrait : .landscape
    } else {
      actual = .landscape
    }
    return MediaOrientation(actual)
  }

  public func styles(for orientation: SubtitleOrientation) -> SubtitleStyleSet {
    styleConfiguration[orientation]
  }
}

/// FCPXML 导出配置
public struct FCPXMLExportSettings {
  public let frameRate: Double
  public let projectName: String
  public let includeSubtitles: Bool
  public let filterEmptySegments: Bool
  public let isResolve: Bool  // DaVinci Resolve compatibility
  public let speed: Double

  public init(
    frameRate: Double = 25.0,
    projectName: String = "Cliptate Project",
    includeSubtitles: Bool = true,
    filterEmptySegments: Bool = true,
    isResolve: Bool = false,
    speed: Double = 1.0
  ) {
    self.frameRate = frameRate
    self.projectName = projectName
    self.includeSubtitles = includeSubtitles
    self.filterEmptySegments = filterEmptySegments
    self.isResolve = isResolve
    self.speed = max(0.1, min(speed, 10.0))
  }
}

/// FCPXML 导出器
public class FCPXMLExporter {

  /// 导出多文件 FCPXML
  public static func exportFCPXML(
    mediaFiles: [MediaFile],
    settings: FCPXMLExportSettings
  ) -> String {

    var buffer = ""
    var styleDefCounter = 1

    let formatDescriptor = resolveFormatDescriptor(
      for: mediaFiles,
      frameRate: settings.frameRate
    )

    // 将秒转换为帧数，使用向上取整确保不会丢帧
    func secondsToFrames(_ seconds: Double) -> Int {
      Int(ceil(seconds * settings.frameRate))
    }

    let timelineSpeed = settings.speed

    func sourceToTimelineFrames(_ sourceFrames: Int) -> Int {
      if timelineSpeed == 1.0 { return sourceFrames }
      return max(1, Int(ceil(Double(sourceFrames) / timelineSpeed)))
    }

    func buildTimeMap(sourceStart: Int, timelineDuration: Int, sourceDuration: Int) -> String {
      let fps = Int(settings.frameRate)
      var result = "              <timeMap>\n"
      result += "                <timept time=\"\(sourceStart)/\(fps)s\" value=\"\(sourceStart)/\(fps)s\" interp=\"smooth2\"/>\n"
      result += "                <timept time=\"\(sourceStart + timelineDuration)/\(fps)s\" value=\"\(sourceStart + sourceDuration)/\(fps)s\" interp=\"smooth2\"/>\n"
      result += "              </timeMap>\n"
      return result
    }

    // XML 头部和资源声明
    buffer += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    buffer += "<!DOCTYPE fcpxml>\n"
    buffer += "<fcpxml version=\"\(settings.isResolve ? "1.10" : "1.11")\">\n"
    buffer += "  <resources>\n"
    buffer += "    <format id=\"r1\" name=\"\(formatDescriptor.name)\""
    buffer += " frameDuration=\"1/\(Int(settings.frameRate))s\""
    buffer += " width=\"\(formatDescriptor.width)\" height=\"\(formatDescriptor.height)\""
    buffer += " colorSpace=\"1-1-1 (Rec. 709)\"/>\n"

    // 添加所有资源
    var assetId = 2
    for mediaFile in mediaFiles {
      let durationFrames = secondsToFrames(mediaFile.duration)
      let fileName = mediaFile.url.deletingPathExtension().lastPathComponent

      buffer += "    <asset id=\"r\(assetId)\""
      buffer += " name=\"\(escapeXML(fileName))\""
      buffer += " start=\"0/\(Int(settings.frameRate))s\""
      buffer += " hasVideo=\"1\" format=\"r1\" hasAudio=\"1\" audioChannels=\"2\""
      buffer += " duration=\"\(durationFrames)/\(Int(settings.frameRate))s\">\n"
      buffer +=
        "      <media-rep kind=\"original-media\" src=\"\(escapeXML(mediaFile.url.absoluteString))\"/>\n"
      buffer += "      <metadata>\n"
      buffer +=
        "        <md key=\"com.voicepink.orientation-resolved\" value=\"\(escapeXML(mediaFile.orientation.rawValue))\"/>\n"
      if let size = mediaFile.presentationSize {
        buffer +=
          "        <md key=\"com.voicepink.presentation-width\" value=\"\(formatFloat(size.width))\"/>\n"
        buffer +=
          "        <md key=\"com.voicepink.presentation-height\" value=\"\(formatFloat(size.height))\"/>\n"
      }
      buffer += "      </metadata>\n"
      buffer += "    </asset>\n"
      assetId += 1
    }

    // 添加标题与缩放效果资源
    buffer +=
      "    <effect id=\"r\(assetId)\" name=\"Title\" uid=\".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti\"/>\n"
    let titleEffectId = assetId
    let zoomEffectId = assetId + 1
    buffer +=
      "    <effect id=\"r\(zoomEffectId)\" name=\"Scale\" uid=\".../Video/Transform.localized/Scale.localized/Scale.motr\"/>\n"
    buffer += "  </resources>\n"

    // 第一阶段：计算总时长（帧为单位）
    var totalFrames = 0

    for mediaFile in mediaFiles {
      if mediaFile.segments.isEmpty { continue }

      var lastEndFrame = 0
      var fileFrames = 0

      for segment in mediaFile.segments {
        if settings.filterEmptySegments
          && segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          continue
        }

        let startFrame = secondsToFrames(segment.startTime)
        let endFrame = secondsToFrames(segment.endTime)
        let segmentFrames = endFrame - startFrame

        if !settings.filterEmptySegments && startFrame > lastEndFrame {
          let gapFrames = startFrame - lastEndFrame
          fileFrames += sourceToTimelineFrames(gapFrames)
        }

        fileFrames += sourceToTimelineFrames(max(segmentFrames, 0))
        lastEndFrame = endFrame
      }

      totalFrames += fileFrames
    }

    // 项目结构
    buffer += "  <library>\n"
    buffer += "    <event name=\"Cliptate_EXPORTED\">\n"
    buffer += "      <project name=\"\(escapeXML(settings.projectName))\">\n"
    buffer +=
      "        <sequence format=\"r1\" tcFormat=\"NDF\" audioLayout=\"stereo\" audioRate=\"48k\""
    buffer += " duration=\"\(totalFrames)/\(Int(settings.frameRate))s\">\n"
    buffer += "          <spine>\n"

    // 重置计数器以重新处理文件
    var currentAssetId = 2
    var timelinePosition = 0

    for mediaFile in mediaFiles {
      if mediaFile.segments.isEmpty { continue }

      let subtitleOrientation = mediaFile.orientation.subtitleOrientation
      let presentationSize =
        mediaFile.presentationSize
        ?? defaultPresentationSize(
          for: subtitleOrientation)
      let layout = VideoOrientationLayout.layout(
        for: presentationSize,
        targetOrientation: subtitleOrientation
      )

      var lastEndFrame = 0  // 文件内部帧位置跟踪

      for (index, segment) in mediaFile.segments.enumerated() {
        if settings.filterEmptySegments
          && segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          continue
        }

        let startFrame = secondsToFrames(segment.startTime)
        let endFrame = secondsToFrames(segment.endTime)
        let segmentFrames = endFrame - startFrame

        if segmentFrames <= 0 { continue }

        if !settings.filterEmptySegments && startFrame > lastEndFrame {
          let gapSourceFrames = startFrame - lastEndFrame
          let gapTimelineFrames = sourceToTimelineFrames(gapSourceFrames)

          if timelineSpeed != 1.0 {
            buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
            buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
            buffer += " duration=\"\(gapTimelineFrames)/\(Int(settings.frameRate))s\""
            buffer += " start=\"\(lastEndFrame)/\(Int(settings.frameRate))s\""
            buffer += " name=\"gap-\(currentAssetId)_\(index)\""
            buffer += " tcFormat=\"NDF\">\n"
            buffer += buildTimeMap(
              sourceStart: lastEndFrame,
              timelineDuration: gapTimelineFrames,
              sourceDuration: gapSourceFrames
            )
            buffer += "            </asset-clip>\n"
          } else {
            buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
            buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
            buffer += " duration=\"\(gapTimelineFrames)/\(Int(settings.frameRate))s\""
            buffer += " start=\"\(lastEndFrame)/\(Int(settings.frameRate))s\""
            buffer += " name=\"gap-\(currentAssetId)_\(index)\""
            buffer += " tcFormat=\"NDF\"/>\n"
          }

          timelinePosition += gapTimelineFrames
        }

        let effect = mediaFile.effect(for: segment)
        let zoomMultiplier = effect?.appliedZoom
        let segmentTimelineFrames = sourceToTimelineFrames(segmentFrames)

        buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
        buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
        buffer += " duration=\"\(segmentTimelineFrames)/\(Int(settings.frameRate))s\""
        buffer += " start=\"\(startFrame)/\(Int(settings.frameRate))s\""
        buffer += " name=\"\(currentAssetId)_\(index)\""
        buffer += " tcFormat=\"NDF\">\n"

        if timelineSpeed != 1.0 {
          buffer += buildTimeMap(
            sourceStart: startFrame,
            timelineDuration: segmentTimelineFrames,
            sourceDuration: segmentFrames
          )
        }

        if let zoom = zoomMultiplier, zoom > 1.0001 {
          let formatted = String(format: "%.3f", zoom)
          buffer += "              <adjust-transform scale=\"\(formatted) \(formatted)\"/>\n"
        }

        let translation = mediaFile.translation(for: segment)
        let hasOriginalText = !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTranslation = translation.map { !$0.isEmpty } ?? false

        if settings.includeSubtitles && (hasOriginalText || hasTranslation) {
          buffer += buildTitleElement(
            segment: segment,
            effect: effect,
            clipStartFrames: startFrame,
            durationFrames: segmentTimelineFrames,
            styleDefCounter: styleDefCounter,
            titleEffectId: titleEffectId,
            frameRate: Int(settings.frameRate),
            orientation: mediaFile.orientation,
            layout: layout,
            translation: translation,
            placement: mediaFile.translationPlacement,
            styles: mediaFile.styles(for: mediaFile.orientation.subtitleOrientation)
          )

          styleDefCounter += 1
        }

        buffer += "            </asset-clip>\n"

        timelinePosition += segmentTimelineFrames
        lastEndFrame = endFrame
      }

      currentAssetId += 1
    }

    // XML 尾部
    buffer += "          </spine>\n"
    if !mediaFiles.isEmpty {
      buffer += "          <metadata>\n"
      buffer +=
        "            <md key=\"com.voicepink.sequence-orientation\" value=\"\(escapeXML(formatDescriptor.orientation.rawValue))\"/>\n"
      buffer +=
        "            <md key=\"com.voicepink.sequence-format-width\" value=\"\(formatDescriptor.width)\"/>\n"
      buffer +=
        "            <md key=\"com.voicepink.sequence-format-height\" value=\"\(formatDescriptor.height)\"/>\n"
      buffer += "          </metadata>\n"
    }
    buffer += "        </sequence>\n"
    buffer += "      </project>\n"
    buffer += "    </event>\n"
    buffer += "  </library>\n"
    buffer += "</fcpxml>\n"

    return buffer
  }

  // MARK: - Private Helper Methods

  private struct FormatDescriptor {
    let width: Int
    let height: Int
    let name: String
    let orientation: MediaOrientation
  }

  private static func resolveFormatDescriptor(
    for mediaFiles: [MediaFile],
    frameRate: Double
  ) -> FormatDescriptor {
    let defaultWidth = 3840
    let defaultHeight = 2160

    let sizes = mediaFiles.compactMap { media -> CGSize? in
      guard var size = media.presentationSize, size.width > 0, size.height > 0 else { return nil }
      let orientation = media.orientation
      switch orientation {
      case .portrait where size.width > size.height:
        swap(&size.width, &size.height)
      case .landscape where size.height > size.width:
        swap(&size.width, &size.height)
      default:
        break
      }
      return size
    }

    guard !sizes.isEmpty else {
      return FormatDescriptor(
        width: defaultWidth,
        height: defaultHeight,
        name: "CustomFormat_\(defaultWidth)x\(defaultHeight)_\(Int(frameRate))fps",
        orientation: .landscape
      )
    }

    var orientationCounts: [MediaOrientation: Int] = [:]
    for media in mediaFiles {
      let orientation = media.orientation
      orientationCounts[orientation, default: 0] += 1
    }

    let orientation: MediaOrientation
    if let portrait = orientationCounts[.portrait], let landscape = orientationCounts[.landscape] {
      if portrait == landscape {
        orientation = sizes.first!.height >= sizes.first!.width ? .portrait : .landscape
      } else {
        orientation = portrait > landscape ? .portrait : .landscape
      }
    } else if orientationCounts[.portrait] != nil {
      orientation = .portrait
    } else {
      orientation = .landscape
    }

    let orientationMatchedSizes = sizes.filter { size in
      switch orientation {
      case .portrait:
        return size.height >= size.width
      case .landscape:
        return size.width >= size.height
      }
    }

    let chosenSize =
      (orientationMatchedSizes.isEmpty ? sizes : orientationMatchedSizes)
      .max { lhs, rhs in
        (lhs.width * lhs.height) < (rhs.width * rhs.height)
      } ?? sizes[0]

    var width = chosenSize.width
    var height = chosenSize.height
    if orientation == .portrait, width > height {
      swap(&width, &height)
    } else if orientation == .landscape, height > width {
      swap(&width, &height)
    }

    let widthInt = max(Int(round(width)), 1)
    let heightInt = max(Int(round(height)), 1)

    return FormatDescriptor(
      width: widthInt,
      height: heightInt,
      name: "CustomFormat_\(widthInt)x\(heightInt)_\(Int(frameRate))fps",
      orientation: orientation
    )
  }

  private static func buildTitleElement(
    segment: Segment,
    effect: SegmentEffectState?,
    clipStartFrames: Int,
    durationFrames: Int,
    styleDefCounter: Int,
    titleEffectId: Int,
    frameRate: Int,
    orientation: MediaOrientation,
    layout: VideoOrientationLayout.Result,
    translation: SegmentTranslation?,
    placement: SubtitleTranslationPlacement,
    styles: SubtitleStyleSet
  ) -> String {
    var buffer = ""

    buffer += "              <title ref=\"r\(titleEffectId)\" name=\"\(escapeXML(segment.text))\""
    buffer += " lane=\"1\""
    buffer += " offset=\"\(clipStartFrames)/\(frameRate)s\""
    buffer += " duration=\"\(durationFrames)/\(frameRate)s\">\n"
    buffer += "                <text>\n"

    let baseStyle = styles.primary
    let translationStyle = styles.translation
    let highlightStyle = styles.highlight

    // FCPXML 使用更大的字体以确保可见性
    let fcpFontScale: Double = 1.0
    let baseFontSize = baseStyle.fontSize * fcpFontScale
    let translationFontSize = translationStyle.fontSize * fcpFontScale

    let coverage = min(max(effect?.highlightCoverage ?? 0, 0), 1)
    let highlightScale = min(max(effect?.appliedScale ?? 1.0, 1.0), 2.5)
    let highlightFontSize =
      highlightStyle.fontSize * fcpFontScale * highlightScale

    let highlightBaseColor = highlightStyle.fillColor
    let highlightAlpha = min(max(highlightBaseColor.alpha * 0.65 + coverage * 0.35, 0), 1)
    let highlightColor = SubtitleColor(
      red: highlightBaseColor.red,
      green: highlightBaseColor.green,
      blue: highlightBaseColor.blue,
      alpha: highlightAlpha
    )

    // 处理文本，添加高亮样式及翻译内容
    let highlightedText = highlightKeywords(
      text: segment.text,
      effect: effect,
      styleDefCounter: styleDefCounter
    )

    let translationComponents: (line: String, separator: String)? = {
      guard let translation, !translation.isEmpty else { return nil }
      let escaped = escapeXML(translation.text)
      let line = "<text-style ref=\"ts\(styleDefCounter)_translation\">\(escaped)</text-style>"
      let separator = "<text-style>&#xA;</text-style>"
      return (line, separator)
    }()

    let hasOriginal = !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let composedText: String
    if let translationComponents {
      switch placement {
      case .above:
        composedText =
          hasOriginal
          ? "\(translationComponents.line)\(translationComponents.separator)\(highlightedText)"
          : translationComponents.line
      case .below:
        composedText =
          hasOriginal
          ? "\(highlightedText)\(translationComponents.separator)\(translationComponents.line)"
          : translationComponents.line
      }
    } else {
      composedText = highlightedText
    }

    buffer += "                  \(composedText)\n"
    buffer += "                </text>\n"

    let verticalRatio: Double = (orientation == .portrait) ? (-22.0 / 1920.0) : (-33.0 / 1080.0)
    let verticalPosition = verticalRatio * Double(layout.canvasSize.height)

    buffer += textStyleDef(
      id: "ts\(styleDefCounter)",
      style: baseStyle,
      fontSize: baseFontSize,
      color: baseStyle.fillColor,
      kerning: baseStyle.kerning,
      shadowRadius: baseStyle.shadowRadius,
      outlineWidth: max(baseStyle.outlineWidth, 0.05)
    )

    if translationComponents != nil {
      buffer += textStyleDef(
        id: "ts\(styleDefCounter)_translation",
        style: translationStyle,
        fontSize: translationFontSize,
        color: translationStyle.fillColor,
        kerning: translationStyle.kerning,
        shadowRadius: translationStyle.shadowRadius,
        outlineWidth: max(translationStyle.outlineWidth, 0.05)
      )
    }

    buffer += textStyleDef(
      id: "ts\(styleDefCounter)_highlight",
      style: highlightStyle,
      fontSize: highlightFontSize,
      color: highlightColor,
      bold: highlightStyle.bold,
      kerning: highlightStyle.kerning,
      shadowRadius: highlightStyle.shadowRadius,
      outlineWidth: max(highlightStyle.outlineWidth, 0.05)
    )
    buffer +=
      "                <adjust-transform position=\"0 \(String(format: "%.0f", verticalPosition))\"/>\n"
    buffer += "              </title>\n"

    return buffer
  }

  private static func textStyleDef(
    id: String,
    style: SubtitleStyle,
    fontSize: Double,
    color: SubtitleColor,
    bold: Bool? = nil,
    kerning: Double? = nil,
    shadowColor: SubtitleColor? = nil,
    shadowRadius: Double? = nil,
    shadowAngle: Double? = nil,
    outlineWidth: Double? = nil
  ) -> String {
    let boldValue = bold ?? style.bold
    let italicValue = style.italic
    
    // 修正：fontFace应该根据字体的实际样式来确定，而不是根据bold/italic属性
    // FCP需要字体名称和fontFace匹配，例如 "PingFang SC" + "Regular"
    let fontFace: String
    let normalizedFontName = style.fontName.lowercased()
    
    // 检查字体名称中是否已经包含样式信息
    if normalizedFontName.contains("bold") && normalizedFontName.contains("italic") {
      fontFace = "Bold Italic"
    } else if normalizedFontName.contains("bold") {
      fontFace = "Bold"
    } else if normalizedFontName.contains("italic") {
      fontFace = "Italic"
    } else {
      // 对于常规字体名称（如 "PingFang SC", "Arial Unicode MS"），使用 Regular
      // 即使 bold=true，也使用 Regular，让 bold 属性来控制粗体
      fontFace = "Regular"
    }

    // 字体大小不使用小数，FCP更倾向整数字体大小
    let fontSizeString = String(Int(round(fontSize)))
    let outlineValue = outlineWidth ?? style.outlineWidth
    // strokeWidth应该是负数，表示描边
    let strokeWidth = String(format: "-%.0f", max(round(outlineValue), 1))
    let shadowColorValue = shadowColor ?? style.shadowColor
    let shadowRadiusValue = shadowRadius ?? style.shadowRadius
    let shadowAngleValue = shadowAngle ?? style.shadowAngle
    let shadowOffset =
      "\(formatShadowComponent(shadowRadiusValue)) \(formatShadowComponent(shadowAngleValue, allowFractions: false))"

    var builder = ""
    builder += "                <text-style-def id=\"\(id)\">\n"
    builder += "                  <text-style font=\"\(escapeXML(style.fontName))\""
    builder += " fontSize=\"\(fontSizeString)\""
    builder += " fontFace=\"\(fontFace)\""
    builder += " fontColor=\"\(color.fcpxmlRGBA)\""
    builder += " bold=\"\(boldValue ? 1 : 0)\""
    builder += " italic=\"\(italicValue ? 1 : 0)\""
    builder += " strokeColor=\"\(style.outlineColor.fcpxmlRGBA)\""
    builder += " strokeWidth=\"\(strokeWidth)\""
    builder += " shadowColor=\"\(shadowColorValue.fcpxmlRGBA)\""
    builder += " shadowOffset=\"\(shadowOffset)\""
    builder += " alignment=\"center\"/>\n"
    builder += "                </text-style-def>\n"
    return builder
  }

  private static func formatShadowComponent(_ value: Double, allowFractions: Bool = true) -> String
  {
    guard allowFractions else {
      return String(Int(round(value)))
    }
    if abs(value.rounded() - value) < 1e-6 {
      return String(Int(round(value)))
    }
    return String(format: "%.1f", value)
  }

  private static func defaultPresentationSize(for orientation: SubtitleOrientation) -> CGSize {
    switch orientation {
    case .portrait:
      return CGSize(width: 1080, height: 1920)
    case .landscape:
      return CGSize(width: 1920, height: 1080)
    }
  }

  private static func highlightKeywords(
    text: String,
    effect: SegmentEffectState?,
    styleDefCounter: Int
  ) -> String {
    guard let effect, !effect.keywords.isEmpty else {
      return "<text-style ref=\"ts\(styleDefCounter)\">\(escapeXML(text))</text-style>"
    }

    let sanitizedKeywords = effect.keywords
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard !sanitizedKeywords.isEmpty else {
      return "<text-style ref=\"ts\(styleDefCounter)\">\(escapeXML(text))</text-style>"
    }

    let escapedKeywords = sanitizedKeywords.map { NSRegularExpression.escapedPattern(for: $0) }
    let pattern = escapedKeywords.joined(separator: "|")

    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return "<text-style ref=\"ts\(styleDefCounter)\">\(escapeXML(text))</text-style>"
    }

    let nsText = text as NSString
    let matches = regex.matches(
      in: text,
      options: [],
      range: NSRange(location: 0, length: nsText.length)
    )

    guard !matches.isEmpty else {
      return "<text-style ref=\"ts\(styleDefCounter)\">\(escapeXML(text))</text-style>"
    }

    var parts: [String] = []
    var cursor = 0

    for match in matches {
      if match.range.location > cursor {
        let normalRange = NSRange(location: cursor, length: match.range.location - cursor)
        let before = nsText.substring(with: normalRange)
        if !before.isEmpty {
          parts.append(
            "<text-style ref=\"ts\(styleDefCounter)\">\(escapeXML(before))</text-style>"
          )
        }
      }

      let keywordText = nsText.substring(with: match.range)
      parts.append(
        "<text-style ref=\"ts\(styleDefCounter)_highlight\">\(escapeXML(keywordText))</text-style>"
      )

      cursor = match.range.location + match.range.length
    }

    if cursor < nsText.length {
      let remainingRange = NSRange(location: cursor, length: nsText.length - cursor)
      let remaining = nsText.substring(with: remainingRange)
      if !remaining.isEmpty {
        parts.append(
          "<text-style ref=\"ts\(styleDefCounter)\">\(escapeXML(remaining))</text-style>"
        )
      }
    }

    return parts.joined()
  }

  /// 转义 XML 特殊字符
  private static func escapeXML(_ text: String) -> String {
    var result = text

    // 首先处理 &，这必须在其他转义之前
    result = result.replacingOccurrences(of: "&", with: "&amp;")

    // 然后处理其他特殊字符
    result = result.replacingOccurrences(of: "<", with: "&lt;")
    result = result.replacingOccurrences(of: ">", with: "&gt;")
    result = result.replacingOccurrences(of: "\"", with: "&quot;")
    result = result.replacingOccurrences(of: "'", with: "&apos;")

    // 处理控制字符和换行符
    result = result.replacingOccurrences(of: "\r\n", with: "&#xA;")  // Windows换行符
    result = result.replacingOccurrences(of: "\r", with: "&#xA;")  // Mac换行符
    result = result.replacingOccurrences(of: "\n", with: "&#xA;")  // Unix换行符
    result = result.replacingOccurrences(of: "\t", with: "&#x9;")  // 制表符

    // 移除或转义无效的控制字符 (0x00-0x1F，除了 0x09, 0x0A, 0x0D)
    result = result.replacingOccurrences(
      of: "[\u{0000}-\u{0008}\u{000B}\u{000C}\u{000E}-\u{001F}]",
      with: "",
      options: .regularExpression
    )

    return result
  }

  private static func formatFloat(_ value: CGFloat) -> String {
    String(format: "%.3f", value)
  }
}
