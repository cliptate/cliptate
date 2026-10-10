import Foundation

enum SegmentEffectGenerator {
  struct KeywordExtractionContext {
    var isEnabled: Bool
    var provider: AIProvider
    var apiKey: String?
    var language: Language
    var maxKeywords: Int = 4
    var openAIEndpoint: String? = nil
    var model: String? = nil
    var systemPrompt: String? = nil

    var resolvedAPIKey: String? {
      guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
        return nil
      }
      return key
    }

    var resolvedOpenAIEndpoint: String? {
      guard provider == .openai else { return nil }
      guard let endpoint = openAIEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
        !endpoint.isEmpty
      else { return nil }
      return endpoint
    }

    var canUseAI: Bool {
      isEnabled && resolvedAPIKey != nil
    }
  }

  struct GenerationResult {
    let effects: [String: SegmentEffectState]
    let usedAI: Bool
    let errorMessage: String?
  }

  /// 根据配置生成所有段落的效果信息
  static func generateEffects(
    for segments: [Segment],
    configuration: SegmentEffectConfiguration,
    keywordContext: KeywordExtractionContext
  ) async -> GenerationResult {
    guard !segments.isEmpty else {
      return GenerationResult(effects: [:], usedAI: false, errorMessage: nil)
    }

    let fillerWordSet: Set<String> =
      configuration.filterFillerWords
      ? configuration.normalizedFillerWordSet
      : []

    var segmentInfos: [(segment: Segment, processed: String)] = []
    segmentInfos.reserveCapacity(segments.count)

    for segment in segments {
      let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !fillerWordSet.isEmpty else {
        segmentInfos.append((segment: segment, processed: trimmed))
        continue
      }

      let sanitized = await FillerWordFilter.filter(text: trimmed, fillerWords: fillerWordSet)
      segmentInfos.append(
        (segment: segment, processed: sanitized.trimmingCharacters(in: .whitespacesAndNewlines))
      )
    }

    var aiKeywordMap: [String: [String]] = [:]
    var usedAI = false
    var errorMessage: String?

    if configuration.extractHighlights {
      if keywordContext.canUseAI {
        let resolvableSegments = segmentInfos.filter { !$0.processed.isEmpty }
        if !resolvableSegments.isEmpty {
          do {
            aiKeywordMap = try await fetchKeywordsUsingAI(
              segments: resolvableSegments,
              context: keywordContext,
              fillerWords: fillerWordSet
            )
            usedAI = !aiKeywordMap.isEmpty
          } catch {
            errorMessage =
              (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print(
              "⚠️ [SegmentEffectGenerator] AI keyword extraction failed: \(errorMessage ?? error.localizedDescription)"
            )
          }
        }
      } else if keywordContext.isEnabled {
        print(
          "⚠️ [SegmentEffectGenerator] Missing API credentials for \(keywordContext.provider.displayName)"
        )
      }
    }

    var effects: [String: SegmentEffectState] = [:]
    effects.reserveCapacity(segments.count)

    for info in segmentInfos {
      let keywords: [String]
      if configuration.extractHighlights {
        if info.processed.isEmpty {
          keywords = []
        } else if let aiKeywords = aiKeywordMap[info.segment.id], !aiKeywords.isEmpty {
          keywords = Array(
            deduplicate(keywords: aiKeywords, excluding: fillerWordSet)
              .prefix(keywordContext.maxKeywords)
          )
        } else {
          keywords = []
        }
      } else {
        keywords = []
      }

      let coverage = calculateHighlightCoverage(text: info.processed, keywords: keywords)
      let appliedScale: Double?
      if configuration.enableScaling, !keywords.isEmpty {
        appliedScale = configuration.scaleMultiplier
      } else {
        appliedScale = nil
      }

      let appliedZoom: Double?
      if configuration.enableZoom, coverage >= 0.5, !keywords.isEmpty {
        appliedZoom = configuration.zoomMultiplier
      } else {
        appliedZoom = nil
      }

      effects[info.segment.id] = SegmentEffectState(
        keywords: keywords,
        appliedScale: appliedScale,
        appliedZoom: appliedZoom,
        highlightCoverage: coverage
      )
    }

    return GenerationResult(
      effects: effects,
      usedAI: usedAI,
      errorMessage: errorMessage
    )
  }

  private static func fetchKeywordsUsingAI(
    segments: [(segment: Segment, processed: String)],
    context: KeywordExtractionContext,
    fillerWords: Set<String>
  ) async throws -> [String: [String]] {
    guard let apiKey = context.resolvedAPIKey else {
      return [:]
    }

    var keywordMap: [String: [String]] = [:]
    keywordMap.reserveCapacity(segments.count)

    let texts = segments.map { $0.processed }
    guard !texts.isEmpty else { return keywordMap }

    let aiKeywords = try await AICorrector.extractKeywords(
      from: texts,
      provider: context.provider,
      model: context.model,
      systemPrompt: context.systemPrompt,
      apiKey: apiKey,
      language: context.language,
      maxKeywords: context.maxKeywords,
      openAIBaseURL: context.resolvedOpenAIEndpoint
    )

    if aiKeywords.count != segments.count {
      print(
        "⚠️ [SegmentEffectGenerator] Keyword response count mismatch: expected \(segments.count), received \(aiKeywords.count)"
      )
    }

    for (index, keywords) in aiKeywords.enumerated() where index < segments.count {
      let limited = Array(
        deduplicate(keywords: keywords, excluding: fillerWords)
          .prefix(context.maxKeywords)
      )
      if !limited.isEmpty {
        keywordMap[segments[index].segment.id] = limited
      }
    }

    return keywordMap
  }

  private static func deduplicate(keywords: [String], excluding: Set<String> = []) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    result.reserveCapacity(keywords.count)
    for keyword in keywords {
      let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { continue }
      let lowered = normalized.lowercased()
      if excluding.contains(lowered) { continue }
      if seen.insert(lowered).inserted {
        result.append(normalized)
      }
    }
    return result
  }

  private static func calculateHighlightCoverage(text: String, keywords: [String]) -> Double {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }
    guard !keywords.isEmpty else { return 0 }

    let escapedKeywords = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
    guard !escapedKeywords.isEmpty else { return 0 }

    let pattern = escapedKeywords.joined(separator: "|")
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return 0
    }

    let nsText = trimmed as NSString
    var highlightedIndices: Set<Int> = []
    let fullRange = NSRange(location: 0, length: nsText.length)
    regex.enumerateMatches(in: trimmed, options: [], range: fullRange) { match, _, _ in
      guard let match else { return }
      if match.range.length <= 0 { return }
      for idx in match.range.location..<(match.range.location + match.range.length) {
        highlightedIndices.insert(idx)
      }
    }

    guard !highlightedIndices.isEmpty else { return 0 }
    return Double(highlightedIndices.count) / Double(nsText.length)
  }
}
