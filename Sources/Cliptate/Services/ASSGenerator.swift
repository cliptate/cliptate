import Foundation

public struct ASSStyleOptions: Sendable {
  public var playResX: Int = 1920
  public var playResY: Int = 1080
  public var fontName: String = "Arial Unicode MS"
  public var fontSize: Int = 40
  public var primaryColorASS: String = "&H00FFFFFF"  // white
  public var secondaryColorASS: String = "&H000000FF"
  public var outlineColorASS: String = "&H00000000"  // black
  public var backColorASS: String = "&H64000000"  // semi black
  public var bold: Bool = true
  public var italic: Bool = false
  public var outline: Int = 3
  public var shadow: Int = 0
  public var alignment: Int = 2  // bottom-center
  public var marginL: Int = 10
  public var marginR: Int = 10
  public var marginV: Int = 40

  public init() {}
}

public enum ASSGenerator {
  private enum StyleName {
    static let primary = "Default"
    static let translation = "SecondLine"
    static let highlight = "Highlight"
    static let title = "Title"
    static let subtitle = "Subtitle"
  }

  // New API: build ASS using predefined templates (horizontal/vertical)
  // filterSilentSegments: 当外部已经过滤掉静默段并希望时间轴压缩时设为 true；会将后续片段前移，去除中间空隙。
  public static func makeASS(
    segments: [Segment],
    orientation: SubtitleOrientation,
    filterSilentSegments: Bool = false,
    effects: [String: SegmentEffectState] = [:],
    translationPlacement: SubtitleTranslationPlacement = .below,
    styleConfiguration: SubtitleStylesConfiguration
  ) -> String {
    let renderItems = buildRenderItems(segments: segments, filterSilentSegments: filterSilentSegments)
    var lines: [String] = []
    let styleSet = styleConfiguration[orientation]
    lines.append(contentsOf: header(for: orientation, styles: styleSet))
    lines.append("")
    lines.append("[Events]")
    lines.append("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
    for item in renderItems {
      let seg = item.segment
      let start = assTime(item.startTime)
      let end = assTime(max(item.endTime, item.startTime + 0.01))
      let effectState = effects[seg.id]
      let effectDescription = metadataDescription(for: effectState)
      let translation = seg.translation
      let text = renderDialogueText(
        for: seg,
        effect: effectState,
        translation: translation,
        placement: translationPlacement,
        orientation: orientation,
        styles: styleSet
      )
      let effectField = effectDescription.isEmpty ? "" : effectDescription
      lines.append(
        "Dialogue: 0,\(start),\(end),Default,,0,0,0,\(effectField),\(text)")
    }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  // Backward-compatible API: 默认使用 horizontal 模板
  public static func makeASS(
    segments: [Segment],
    style _: ASSStyleOptions = .init(),
    filterSilentSegments: Bool = false,
    effects: [String: SegmentEffectState] = [:],
    translationPlacement: SubtitleTranslationPlacement = .below,
    styleConfiguration: SubtitleStylesConfiguration
  ) -> String {
    return makeASS(
      segments: segments,
      orientation: .landscape,
      filterSilentSegments: filterSilentSegments,
      effects: effects,
      translationPlacement: translationPlacement,
      styleConfiguration: styleConfiguration
    )
  }

  private static func renderDialogueText(
    for segment: Segment,
    effect: SegmentEffectState?,
    translation: SegmentTranslation?,
    placement: SubtitleTranslationPlacement,
    orientation: SubtitleOrientation,
    styles: SubtitleStyleSet
  ) -> String {
    let components = renderOriginalComponents(
      for: segment,
      effect: effect,
      styles: styles
    )
    guard let translation, !translation.isEmpty else {
      return components.prefix + components.body
    }

    let escapedTranslation = assEscape(translation.text)
    let translationStyled =
      "{\\r\(StyleName.translation)}\(escapedTranslation){\\r\(StyleName.primary)}"
    let hasOriginal = !components.body.isEmpty
    switch placement {
    case .above:
      if hasOriginal {
        return translationStyled + "\\N" + components.prefix + components.body
      } else {
        return translationStyled
      }
    case .below:
      if hasOriginal {
        return components.prefix + components.body + "\\N" + translationStyled
      } else {
        return translationStyled
      }
    }
  }

  private static func renderOriginalComponents(
    for segment: Segment,
    effect: SegmentEffectState?,
    styles: SubtitleStyleSet
  ) -> (prefix: String, body: String) {
    let rawText = segment.text
    let prefix = linePrefix(for: effect)
    guard let effect, !effect.keywords.isEmpty else {
      return (prefix, assEscape(rawText))
    }

    let ranges = keywordRanges(in: rawText, keywords: effect.keywords)
    guard !ranges.isEmpty else {
      return (prefix, assEscape(rawText))
    }

    let baseStyle = styles.primary
    let highlightStyle = styles.highlight
    let baseMultiplier = effect.appliedZoom ?? 1
    let basePercent = normalizedPercent(from: baseMultiplier)
    let highlightMultiplier =
      baseMultiplier
      * (effect.appliedScale ?? 1)
      * highlightStyle.fontSize
      / max(baseStyle.fontSize, 1)
    let highlightPercent = normalizedPercent(from: highlightMultiplier)

    var body = ""
    var cursor = rawText.startIndex

    for range in ranges {
      if range.lowerBound > cursor {
        let prefixText = String(rawText[cursor..<range.lowerBound])
        body.append(assEscape(prefixText))
      }

      let keyword = assEscape(String(rawText[range]))
      let highlightStart = highlightPrefix(
        highlightStyle: highlightStyle,
        baseStyle: baseStyle,
        basePercent: basePercent,
        highlightPercent: highlightPercent
      )
      let highlightEnd = highlightSuffix(
        highlightStyle: highlightStyle,
        baseStyle: baseStyle,
        basePercent: basePercent,
        highlightPercent: highlightPercent
      )
      body.append(highlightStart)
      body.append(keyword)
      body.append(highlightEnd)

      cursor = range.upperBound
    }

    if cursor < rawText.endIndex {
      let suffix = String(rawText[cursor...])
      body.append(assEscape(suffix))
    }

    return (prefix, body)
  }

  private static func metadataDescription(for effect: SegmentEffectState?) -> String {
    guard let effect else { return "" }

    var components: [String] = []
    if let zoom = effect.appliedZoom, zoom.isFinite {
      components.append(String(format: "zoom=%.2f", zoom))
    }
    if let scale = effect.appliedScale, scale.isFinite {
      components.append(String(format: "scale=%.2f", scale))
    }
    if effect.highlightCoverage.isFinite {
      components.append(String(format: "coverage=%.2f", effect.highlightCoverage))
    }
    if !effect.keywords.isEmpty {
      let joined = effect.keywords.joined(separator: "|")
      components.append("keywords=\(joined)")
    }
    guard !components.isEmpty else { return "" }
    return components.joined(separator: ";")
  }

  private static func linePrefix(for effect: SegmentEffectState?) -> String {
    guard let zoom = effect?.appliedZoom, zoom.isFinite, zoom > 0.999 else { return "" }
    let percent = normalizedPercent(from: zoom)
    guard percent != 100 else { return "" }
    return "{\\fscx\(percent)\\fscy\(percent)}"
  }

  private static func highlightPrefix(
    highlightStyle: SubtitleStyle,
    baseStyle: SubtitleStyle,
    basePercent: Int,
    highlightPercent: Int
  ) -> String {
    var overrides: [String] = []
    overrides.append("\\b\(highlightStyle.bold ? 1 : 0)")
    overrides.append("\\i\(highlightStyle.italic ? 1 : 0)")
    overrides.append("\\c\(highlightStyle.fillColor.assHex)")
    if highlightStyle.fontName != baseStyle.fontName {
      overrides.append("\\fn\(highlightStyle.fontName)")
    }
    let sizeValue = Int(round(highlightStyle.fontSize))
    overrides.append("\\fs\(sizeValue)")
    if highlightPercent != basePercent {
      overrides.append("\\fscx\(highlightPercent)\\fscy\(highlightPercent)")
    }
    return "{\(overrides.joined())}"
  }

  private static func highlightSuffix(
    highlightStyle: SubtitleStyle,
    baseStyle: SubtitleStyle,
    basePercent: Int,
    highlightPercent: Int
  ) -> String {
    var overrides: [String] = []
    overrides.append("\\b\(baseStyle.bold ? 1 : 0)")
    overrides.append("\\i\(baseStyle.italic ? 1 : 0)")
    overrides.append("\\c\(baseStyle.fillColor.assHex)")
    if highlightStyle.fontName != baseStyle.fontName {
      overrides.append("\\fn\(baseStyle.fontName)")
    }
    let sizeValue = Int(round(baseStyle.fontSize))
    overrides.append("\\fs\(sizeValue)")
    if highlightPercent != basePercent {
      overrides.append("\\fscx\(basePercent)\\fscy\(basePercent)")
    }
    return "{\(overrides.joined())}"
  }

  private static func normalizedPercent(from multiplier: Double) -> Int {
    guard multiplier.isFinite, multiplier > 0 else { return 100 }
    let clamped = max(0.25, min(multiplier, 4.0))
    return Int((clamped * 100).rounded())
  }

  private static func keywordRanges(in text: String, keywords: [String]) -> [Range<String.Index>] {
    guard !text.isEmpty else { return [] }

    let lowercasedText = text.lowercased()
    var collected: [Range<String.Index>] = []

    for keyword in keywords {
      let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { continue }
      let lowerKeyword = normalized.lowercased()

      var searchRange: Range<String.Index> = lowercasedText.startIndex..<lowercasedText.endIndex
      while let found = lowercasedText.range(of: lowerKeyword, options: [], range: searchRange) {
        let lowerStartOffset = lowercasedText.distance(
          from: lowercasedText.startIndex, to: found.lowerBound)
        let lowerEndOffset = lowercasedText.distance(
          from: lowercasedText.startIndex, to: found.upperBound)

        guard
          let start = text.index(
            text.startIndex, offsetBy: lowerStartOffset, limitedBy: text.endIndex),
          let end = text.index(text.startIndex, offsetBy: lowerEndOffset, limitedBy: text.endIndex)
        else {
          break
        }

        let candidate = start..<end
        if !collected.contains(where: { $0 == candidate }) {
          collected.append(candidate)
        }

        searchRange = found.upperBound..<lowercasedText.endIndex
      }
    }

    return collected.sorted { $0.lowerBound < $1.lowerBound }
  }

  private static func assTime(_ t: TimeInterval) -> String {
    // 使用 Decimal 提高精度，避免浮点数舍入误差
    let tDecimal = Decimal(t)
    var totalCentisecondsDecimal = tDecimal * Decimal(100)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &totalCentisecondsDecimal, 0, .bankers)
    let totalCentiseconds = Int(truncating: rounded as NSNumber)
    let cs = totalCentiseconds % 100
    let totalSeconds = totalCentiseconds / 100
    let s = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    let m = totalMinutes % 60
    let h = totalMinutes / 60
    return String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
  }

  private static func assEscape(_ s: String) -> String {
    // Replace actual newline characters and literal \n with ASS hard line break \N,
    // then escape braces used by ASS override tags.
    return s.replacingOccurrences(of: "\r\n", with: "\\N")
      .replacingOccurrences(of: "\r", with: "\\N")
      .replacingOccurrences(of: "\n", with: "\\N")
      .replacingOccurrences(of: "\\n", with: "\\N")
      .replacingOccurrences(of: "{", with: "(")
      .replacingOccurrences(of: "}", with: ")")
  }

  private struct RenderItem {
    let segment: Segment
    let startTime: TimeInterval
    let endTime: TimeInterval
  }

  private static func buildRenderItems(
    segments: [Segment],
    filterSilentSegments: Bool
  ) -> [RenderItem] {
    let sorted = segments.sorted { $0.startTime < $1.startTime }
    guard filterSilentSegments else {
      return sorted.map { RenderItem(segment: $0, startTime: $0.startTime, endTime: $0.endTime) }
    }

    var items: [RenderItem] = []
    items.reserveCapacity(sorted.count)
    var cursorDecimal = Decimal(0)
    for seg in sorted {
      let duration = max(0, seg.endTime - seg.startTime)
      let start = Double(truncating: cursorDecimal as NSNumber)
      let endDecimal = cursorDecimal + Decimal(duration)
      let end = Double(truncating: endDecimal as NSNumber)
      cursorDecimal = endDecimal
      items.append(RenderItem(segment: seg, startTime: start, endTime: end))
    }
    return items
  }

  private static func header(for orientation: SubtitleOrientation, styles: SubtitleStyleSet)
    -> [String]
  {
    let playResX = (orientation == .portrait) ? 1080 : 1920
    let playResY = (orientation == .portrait) ? 1920 : 1080
    let marginV = (orientation == .portrait) ? 450 : 60
    let titleMarginV = (orientation == .portrait) ? 250 : 200
    let titleAlignment = (orientation == .portrait) ? 8 : 5

    let primaryLine = styleLine(
      name: StyleName.primary,
      style: styles.primary,
      fontSize: styles.primary.fontSize,
      marginV: marginV
    )

    let translationLine = styleLine(
      name: StyleName.translation,
      style: styles.translation,
      fontSize: styles.translation.fontSize,
      marginV: marginV
    )

    let highlightLine = styleLine(
      name: StyleName.highlight,
      style: styles.highlight,
      fontSize: styles.highlight.fontSize,
      marginV: marginV,
      bold: styles.highlight.bold
    )

    let titleFontMultiplier = (orientation == .portrait) ? (120.0 / 54.0) : (140.0 / 60.0)
    let titleLine = styleLine(
      name: StyleName.title,
      style: styles.highlight,
      fontSize: styles.highlight.fontSize * titleFontMultiplier,
      marginV: titleMarginV,
      alignment: titleAlignment,
      bold: true,
      outline: max(styles.highlight.outlineWidth, 3.0),
      shadow: max(styles.highlight.shadowRadius, 2.0)
    )

    let subtitleFontMultiplier = (orientation == .portrait) ? (84.0 / 48.0) : (100.0 / 55.0)
    let subtitleLine = styleLine(
      name: StyleName.subtitle,
      style: styles.primary,
      fontSize: styles.primary.fontSize * subtitleFontMultiplier,
      marginV: titleMarginV,
      alignment: titleAlignment,
      bold: true,
      outline: max(styles.primary.outlineWidth, 2.0),
      shadow: max(styles.primary.shadowRadius, 1.5)
    )

    return [
      "[Script Info]",
      "Title: Generated Subtitle",
      "ScriptType: v4.00+",
      "WrapStyle: 0",
      "ScaledBorderAndShadow: yes",
      "PlayResX: \(playResX)",
      "PlayResY: \(playResY)",
      "",
      "[V4+ Styles]",
      "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
      primaryLine,
      translationLine,
      highlightLine,
      titleLine,
      subtitleLine,
    ]
  }

  private static func styleLine(
    name: String,
    style: SubtitleStyle,
    fontSize: Double,
    marginV: Int,
    alignment: Int = 2,
    borderStyle: Int = 1,
    bold: Bool? = nil,
    italic: Bool? = nil,
    outline: Double? = nil,
    shadow: Double? = nil
  ) -> String {
    let boldValue = (bold ?? style.bold) ? 1 : 0
    let italicValue = (italic ?? style.italic) ? 1 : 0
    let fontSizeString = String(format: "%.1f", fontSize)
    let outlineString = String(format: "%.1f", outline ?? style.outlineWidth)
    let shadowValue = shadow ?? style.shadowRadius
    let shadowString: String
    if abs(shadowValue.rounded() - shadowValue) < 1e-6 {
      shadowString = String(Int(round(shadowValue)))
    } else {
      shadowString = String(format: "%.1f", shadowValue)
    }

    return
      "Style: \(name),\(style.fontName),\(fontSizeString),\(style.fillColor.assHex),\(style.fillColor.assHex),\(style.outlineColor.assHex),\(style.backColor.assHex),\(boldValue),\(italicValue),0,0,100,100,0,0,\(borderStyle),\(outlineString),\(shadowString),\(alignment),20,20,\(marginV),1"
  }
}
