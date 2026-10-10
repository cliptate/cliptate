import Foundation

/// 用户在 Effect 配置页选择的参数集合
struct SegmentEffectConfiguration: Equatable, Codable {
  var extractHighlights: Bool
  var enableScaling: Bool
  var scaleMultiplier: Double
  var enableZoom: Bool
  var zoomMultiplier: Double
  var filterFillerWords: Bool
  var fillerWords: [String]

  static let defaultFillerWords: [String] = ["uh", "um", "额", "嗯"]

  enum CodingKeys: String, CodingKey {
    case extractHighlights
    case enableScaling
    case scaleMultiplier
    case enableZoom
    case zoomMultiplier
    case filterFillerWords
    case fillerWords
  }

  init(
    extractHighlights: Bool,
    enableScaling: Bool,
    scaleMultiplier: Double,
    enableZoom: Bool,
    zoomMultiplier: Double,
    filterFillerWords: Bool = true,
    fillerWords: [String] = SegmentEffectConfiguration.defaultFillerWords
  ) {
    self.extractHighlights = extractHighlights
    self.enableScaling = enableScaling
    self.scaleMultiplier = scaleMultiplier
    self.enableZoom = enableZoom
    self.zoomMultiplier = zoomMultiplier
    self.filterFillerWords = filterFillerWords
    self.fillerWords = SegmentEffectConfiguration.normalizeFillerWords(fillerWords)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    extractHighlights = try container.decode(Bool.self, forKey: .extractHighlights)
    enableScaling = try container.decode(Bool.self, forKey: .enableScaling)
    scaleMultiplier = try container.decode(Double.self, forKey: .scaleMultiplier)
    enableZoom = try container.decode(Bool.self, forKey: .enableZoom)
    zoomMultiplier = try container.decode(Double.self, forKey: .zoomMultiplier)
    filterFillerWords = try container.decodeIfPresent(Bool.self, forKey: .filterFillerWords) ?? true
    let rawWords =
      try container.decodeIfPresent([String].self, forKey: .fillerWords)
      ?? SegmentEffectConfiguration.defaultFillerWords
    fillerWords = SegmentEffectConfiguration.normalizeFillerWords(rawWords)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(extractHighlights, forKey: .extractHighlights)
    try container.encode(enableScaling, forKey: .enableScaling)
    try container.encode(scaleMultiplier, forKey: .scaleMultiplier)
    try container.encode(enableZoom, forKey: .enableZoom)
    try container.encode(zoomMultiplier, forKey: .zoomMultiplier)
    try container.encode(filterFillerWords, forKey: .filterFillerWords)
    try container.encode(
      SegmentEffectConfiguration.normalizeFillerWords(fillerWords), forKey: .fillerWords)
  }

  var normalizedFillerWordSet: Set<String> {
    Set(fillerWords.map { $0.lowercased() })
  }

  static func parseFillerWords(from rawText: String) -> [String] {
    let separators = CharacterSet(charactersIn: ",，、;|/\n")
    var tokens: [String] = []
    var current = ""

    func flushCurrent() {
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        tokens.append(trimmed)
      }
      current.removeAll(keepingCapacity: true)
    }

    let whitespace = CharacterSet.whitespacesAndNewlines

    for character in rawText {
      if character.unicodeScalars.allSatisfy({ separators.contains($0) || whitespace.contains($0) })
      {
        flushCurrent()
      } else {
        current.append(character)
      }
    }
    flushCurrent()

    return normalizeFillerWords(tokens)
  }

  static func normalizeFillerWords(_ rawWords: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    result.reserveCapacity(rawWords.count)

    for word in rawWords {
      let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let lower = trimmed.lowercased()
      if seen.insert(lower).inserted {
        result.append(trimmed)
      }
    }
    return result
  }
}

/// 每个段落对应的效果信息
public struct SegmentEffectState: Equatable, Codable {
  /// 提取出的关键字列表（已根据配置去重和排序）
  public var keywords: [String]
  /// 实际应用的缩放倍数（仅当启用缩放时生效）
  public var appliedScale: Double?
  /// 是否针对整句应用缩放（zoom）
  public var appliedZoom: Double?
  /// 高亮内容在整句中的占比 (0~1)
  public var highlightCoverage: Double
  /// 生成时间，便于调试或后续策略扩展
  public var generatedAt: Date

  public init(
    keywords: [String],
    appliedScale: Double?,
    appliedZoom: Double?,
    highlightCoverage: Double,
    generatedAt: Date = Date()
  ) {
    self.keywords = keywords
    self.appliedScale = appliedScale
    self.appliedZoom = appliedZoom
    self.highlightCoverage = highlightCoverage
    self.generatedAt = generatedAt
  }
}

extension SegmentEffectState {
  private static let zoomCoverageThreshold: Double = 0.5

  /// Returns a new state that reflects the supplied configuration without mutating the original data.
  func adjusted(for configuration: SegmentEffectConfiguration) -> SegmentEffectState {
    guard configuration.extractHighlights else {
      return SegmentEffectState(
        keywords: [],
        appliedScale: nil,
        appliedZoom: nil,
        highlightCoverage: 0,
        generatedAt: generatedAt
      )
    }

    let hasKeywords = !keywords.isEmpty
    let adjustedScale: Double?
    if configuration.enableScaling, hasKeywords {
      adjustedScale = configuration.scaleMultiplier
    } else {
      adjustedScale = nil
    }

    let adjustedZoom: Double?
    if configuration.enableZoom,
      hasKeywords,
      highlightCoverage >= Self.zoomCoverageThreshold
    {
      adjustedZoom = configuration.zoomMultiplier
    } else {
      adjustedZoom = nil
    }

    return SegmentEffectState(
      keywords: hasKeywords ? keywords : [],
      appliedScale: adjustedScale,
      appliedZoom: adjustedZoom,
      highlightCoverage: hasKeywords ? highlightCoverage : 0,
      generatedAt: generatedAt
    )
  }
}

extension Dictionary where Key == String, Value == SegmentEffectState {
  /// Applies the configuration to each stored effect and returns a new dictionary with derived states.
  func adjusted(for configuration: SegmentEffectConfiguration) -> [String: SegmentEffectState] {
    guard !isEmpty else { return [:] }
    return reduce(into: [:]) { partialResult, element in
      partialResult[element.key] = element.value.adjusted(for: configuration)
    }
  }
}
