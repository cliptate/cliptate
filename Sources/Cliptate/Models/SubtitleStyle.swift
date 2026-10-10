import Foundation

public enum SubtitleOrientation: String, Codable, Sendable {
  case landscape
  case portrait
}

public enum SubtitleStyleKind: String, CaseIterable, Identifiable, Codable, Sendable {
  case primary
  case translation
  case highlight

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .primary: return String(localized: "Primary Line", comment: "Subtitle style kind: main transcription line")
    case .translation: return String(localized: "Translation Line", comment: "Subtitle style kind: translation line")
    case .highlight: return String(localized: "Highlight", comment: "Subtitle style kind: keyword highlight")
    }
  }

  public var description: String {
    switch self {
    case .primary:
      return String(localized: "Displayed for the main transcription line.", comment: "Primary subtitle style description")
    case .translation:
      return String(localized: "Displayed for translated subtitles when a translation is available.", comment: "Translation subtitle style description")
    case .highlight:
      return String(localized: "Applied to emphasized keywords extracted by AI Enhance.", comment: "Highlight subtitle style description")
    }
  }
}

public enum SubtitleStylePreset: String, CaseIterable, Identifiable, Codable, Sendable {
  case whiteOnBlackOutline
  case orangeOnBlackOutline
  case yellowOnBlackOutline
  case blueOnBlackOutline

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .whiteOnBlackOutline: return String(localized: "White • Black Outline", comment: "Subtitle preset name: white text with black outline")
    case .orangeOnBlackOutline: return String(localized: "Orange • Black Outline", comment: "Subtitle preset name: orange text with black outline")
    case .yellowOnBlackOutline: return String(localized: "Yellow • Black Outline", comment: "Subtitle preset name: yellow text with black outline")
    case .blueOnBlackOutline: return String(localized: "Sky Blue • Black Outline", comment: "Subtitle preset name: sky blue text with black outline")
    }
  }

  public var description: String {
    switch self {
    case .whiteOnBlackOutline:
      return String(localized: "Classic white text with solid black stroke and soft shadow.", comment: "White subtitle preset description")
    case .orangeOnBlackOutline:
      return String(localized: "Warm orange fill, bold black outline and subtle glow.", comment: "Orange subtitle preset description")
    case .yellowOnBlackOutline:
      return String(localized: "Bright yellow fill with strong contrast for emphasis.", comment: "Yellow subtitle preset description")
    case .blueOnBlackOutline:
      return String(localized: "Cool blue fill for secondary or translation lines.", comment: "Blue subtitle preset description")
    }
  }

  private var fillColor: SubtitleColor {
    switch self {
    case .whiteOnBlackOutline:
      return SubtitleColor(red: 1, green: 1, blue: 1, alpha: 1)
    case .orangeOnBlackOutline:
      return SubtitleColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    case .yellowOnBlackOutline:
      return SubtitleColor(red: 1, green: 1, blue: 0, alpha: 1)
    case .blueOnBlackOutline:
      return SubtitleColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1)
    }
  }

  private var outlineColor: SubtitleColor {
    SubtitleColor(red: 0, green: 0, blue: 0, alpha: 1)
  }

  private var backColor: SubtitleColor {
    SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0)
  }

  private var shadowColor: SubtitleColor {
    let alpha: Double
    switch self {
    case .orangeOnBlackOutline:
      alpha = 0.6
    default:
      alpha = 0.75
    }
    return SubtitleColor(red: 0, green: 0, blue: 0, alpha: alpha)
  }

  func apply(
    to baseStyle: SubtitleStyle,
    kind: SubtitleStyleKind,
    overrideFontSize: Double? = nil
  ) -> SubtitleStyle {
    var next = baseStyle
    next.fillColor = fillColor
    next.outlineColor = outlineColor
    next.backColor = backColor
    next.shadowColor = shadowColor
    if let overrideFontSize {
      next.fontSize = overrideFontSize
    }
    if kind == .highlight {
      next.bold = true
    }
    return next
  }

  func matches(_ style: SubtitleStyle) -> Bool {
    SubtitleStyle.areColorsEqual(style.fillColor, fillColor)
      && SubtitleStyle.areColorsEqual(style.outlineColor, outlineColor)
      && SubtitleStyle.areColorsEqual(style.backColor, backColor)
      && SubtitleStyle.areColorsEqual(style.shadowColor, shadowColor)
  }
}

extension SubtitleStylePreset {
  public static func `default`(for kind: SubtitleStyleKind) -> SubtitleStylePreset {
    switch kind {
    case .primary: return .whiteOnBlackOutline
    case .translation: return .orangeOnBlackOutline
    case .highlight: return .yellowOnBlackOutline
    }
  }
}

public struct SubtitleColor: Equatable, Codable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
    self.red = SubtitleColor.clamp(red)
    self.green = SubtitleColor.clamp(green)
    self.blue = SubtitleColor.clamp(blue)
    self.alpha = SubtitleColor.clamp(alpha)
  }

  private static func clamp(_ value: Double) -> Double {
    if value.isNaN || !value.isFinite { return 0 }
    return min(max(value, 0), 1)
  }

  public var assHex: String {
    let alphaComponent = UInt8(round((1 - alpha) * 255))
    let blueComponent = UInt8(round(blue * 255))
    let greenComponent = UInt8(round(green * 255))
    let redComponent = UInt8(round(red * 255))
    return String(
      format: "&H%02X%02X%02X%02X", alphaComponent, blueComponent, greenComponent,
      redComponent)
  }

  public var fcpxmlRGBA: String {
    String(
      format: "%.3f %.3f %.3f %.3f",
      red,
      green,
      blue,
      alpha
    )
  }
}

#if canImport(AppKit)
  import AppKit

  extension SubtitleColor {
    public init(_ nsColor: NSColor) {
      let converted = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
      red = SubtitleColor.clamp(Double(converted.redComponent))
      green = SubtitleColor.clamp(Double(converted.greenComponent))
      blue = SubtitleColor.clamp(Double(converted.blueComponent))
      alpha = SubtitleColor.clamp(Double(converted.alphaComponent))
    }

    public var nsColor: NSColor {
      NSColor(
        calibratedRed: red,
        green: green,
        blue: blue,
        alpha: alpha
      )
    }
  }
#endif

#if canImport(SwiftUI)
  import SwiftUI

  extension SubtitleColor {
    public init(_ color: Color) {
      #if canImport(AppKit)
        let nsColor = NSColor(color)
        self.init(nsColor)
      #else
        self.init(red: 1, green: 1, blue: 1, alpha: 1)
      #endif
    }

    public var swiftUIColor: Color {
      Color(red: red, green: green, blue: blue, opacity: alpha)
    }
  }
#endif

public struct SubtitleStyle: Equatable, Codable, Sendable {
  public var fontName: String
  public var fontSize: Double
  public var bold: Bool
  public var italic: Bool
  public var fillColor: SubtitleColor
  public var outlineColor: SubtitleColor
  public var backColor: SubtitleColor
  public var outlineWidth: Double
  public var shadowColor: SubtitleColor
  public var shadowRadius: Double
  public var shadowAngle: Double
  public var kerning: Double

  public init(
    fontName: String,
    fontSize: Double,
    bold: Bool,
    italic: Bool,
    fillColor: SubtitleColor,
    outlineColor: SubtitleColor,
    backColor: SubtitleColor,
    outlineWidth: Double,
    shadowColor: SubtitleColor,
    shadowRadius: Double,
    shadowAngle: Double,
    kerning: Double
  ) {
    self.fontName = fontName
    self.fontSize = fontSize
    self.bold = bold
    self.italic = italic
    self.fillColor = fillColor
    self.outlineColor = outlineColor
    self.backColor = backColor
    self.outlineWidth = outlineWidth
    self.shadowColor = shadowColor
    self.shadowRadius = shadowRadius
    self.shadowAngle = shadowAngle
    self.kerning = kerning
  }

}

extension SubtitleStyle {
  static func areColorsEqual(_ lhs: SubtitleColor, _ rhs: SubtitleColor) -> Bool {
    let epsilon = 0.005
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < epsilon }
    return close(lhs.red, rhs.red)
      && close(lhs.green, rhs.green)
      && close(lhs.blue, rhs.blue)
      && close(lhs.alpha, rhs.alpha)
  }

  public func matchedPreset() -> SubtitleStylePreset? {
    SubtitleStylePreset.allCases.first { $0.matches(self) }
  }

  public func applyingPreset(_ preset: SubtitleStylePreset, kind: SubtitleStyleKind)
    -> SubtitleStyle
  {
    preset.apply(to: self, kind: kind)
  }
}

public struct SubtitleStyleSet: Equatable, Codable, Sendable {
  public var primary: SubtitleStyle
  public var translation: SubtitleStyle
  public var highlight: SubtitleStyle

  public init(primary: SubtitleStyle, translation: SubtitleStyle, highlight: SubtitleStyle) {
    self.primary = primary
    self.translation = translation
    self.highlight = highlight
  }

  public static func makeDefault(
    primaryFontSize: Double = 55,
    translationFontSize: Double = 40,
    highlightFontSize: Double = 60
  ) -> SubtitleStyleSet {
    let white = SubtitleColor(red: 1, green: 1, blue: 1, alpha: 1)
    let orange = SubtitleColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    let yellow = SubtitleColor(red: 1, green: 1, blue: 0, alpha: 1)
    let shadowColor = SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0.75)
    let outlineColor = SubtitleColor(red: 0, green: 0, blue: 0, alpha: 1)
    let transparent = SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0)

    // 使用 PingFang SC 作为默认中文字体，更适合在 macOS/FCP 中使用
    let primary = SubtitleStyle(
      fontName: "PingFang SC",
      fontSize: primaryFontSize,
      bold: false,
      italic: false,
      fillColor: white,
      outlineColor: outlineColor,
      backColor: transparent,
      outlineWidth: 2,
      shadowColor: shadowColor,
      shadowRadius: 3,
      shadowAngle: 315,
      kerning: 1.24
    )

    let translation = SubtitleStyle(
      fontName: "PingFang SC",
      fontSize: translationFontSize,
      bold: false,
      italic: false,
      fillColor: orange,
      outlineColor: outlineColor,
      backColor: transparent,
      outlineWidth: 2,
      shadowColor: SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0.6),
      shadowRadius: 2,
      shadowAngle: 300,
      kerning: 1.0
    )

    let highlight = SubtitleStyle(
      fontName: "PingFang SC",
      fontSize: highlightFontSize,
      bold: true,
      italic: false,
      fillColor: yellow,
      outlineColor: outlineColor,
      backColor: transparent,
      outlineWidth: 2,
      shadowColor: shadowColor,
      shadowRadius: 3,
      shadowAngle: 315,
      kerning: 1.24
    )

    return SubtitleStyleSet(primary: primary, translation: translation, highlight: highlight)
  }

  public subscript(kind: SubtitleStyleKind) -> SubtitleStyle {
    get {
      switch kind {
      case .primary: return primary
      case .translation: return translation
      case .highlight: return highlight
      }
    }
    set {
      switch kind {
      case .primary: primary = newValue
      case .translation: translation = newValue
      case .highlight: highlight = newValue
      }
    }
  }
}

public struct SubtitleStylesConfiguration: Equatable, Codable, Sendable {
  public var landscape: SubtitleStyleSet
  public var portrait: SubtitleStyleSet

  public init(landscape: SubtitleStyleSet, portrait: SubtitleStyleSet) {
    self.landscape = landscape
    self.portrait = portrait
  }

  public subscript(_ orientation: SubtitleOrientation) -> SubtitleStyleSet {
    get {
      switch orientation {
      case .landscape: return landscape
      case .portrait: return portrait
      }
    }
    set {
      switch orientation {
      case .landscape: landscape = newValue
      case .portrait: portrait = newValue
      }
    }
  }
}
