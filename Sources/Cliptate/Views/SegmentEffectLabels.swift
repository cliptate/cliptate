import CliptateCore
import SwiftUI

struct HighlightedSegmentText: View {
  let text: String
  let effect: SegmentEffectState?

  private let baseHighlightFontSize: CGFloat = 13

  var body: some View {
    buildText()
      .font(.subheadline)
      .foregroundColor(.primary)
      .lineLimit(6)
      .fixedSize(horizontal: false, vertical: true)
      .multilineTextAlignment(.leading)
      .animation(nil, value: effect?.keywords)  // 避免频繁更新导致闪烁
  }

  private func buildText() -> Text {
    let keywords = effect?.keywords ?? []
    guard !keywords.isEmpty else {
      return Text(text)
    }

    let matches = keywordRanges(in: text, keywords: keywords)
    guard !matches.isEmpty else {
      return Text(text)
    }

    var components: [Text] = []
    var cursor = text.startIndex

    for range in matches {
      if range.lowerBound > cursor {
        let prefix = String(text[cursor..<range.lowerBound])
        if !prefix.isEmpty {
          components.append(Text(prefix))
        }
      }

      let keyword = String(text[range])
      var highlight = Text(keyword)
        .bold()
        .foregroundColor(.accentColor)
      if let scale = effect?.appliedScale, scale > 0 {
        let fontSize = baseHighlightFontSize * scale
        highlight = highlight.font(.system(size: fontSize, weight: .bold))
      }
      components.append(highlight)

      cursor = range.upperBound
    }

    if cursor < text.endIndex {
      let suffix = String(text[cursor...])
      if !suffix.isEmpty {
        components.append(Text(suffix))
      }
    }

    guard let first = components.first else {
      return Text(text)
    }

    return components.dropFirst().reduce(first) { $0 + $1 }
  }

  private func keywordRanges(in text: String, keywords: [String]) -> [Range<String.Index>] {
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
}

struct ZoomBadgeView: View {
  let scale: Double
  let coverage: Double

  private var displayText: String {
    if scale >= 2.0 {
      return String(format: "×%.1f", scale)
    } else {
      return String(format: "×%.2f", scale)
    }
  }

  private var accentOpacity: Double {
    let normalized = min(max(coverage, 0), 1)
    return 0.35 + (normalized * 0.25)
  }

  var body: some View {
    Label {
      Text(displayText)
        .fontWeight(.semibold)
    } icon: {
      Image(systemName: "viewfinder")
        .font(.caption2)
    }
    .font(.caption2)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule(style: .continuous)
        .fill(AppSurface.selectedFill)
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.accentColor.opacity(accentOpacity), lineWidth: 1)
        )
    )
    .foregroundColor(.accentColor)
  }
}

// MARK: - State Change Handlers
