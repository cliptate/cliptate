import CliptateCore
import Foundation

struct AudioSubtitlePreviewSnapshot: Equatable, Sendable {
  let primaryText: String
  let translationText: String?
  let placement: SubtitleTranslationPlacement
}

enum AudioSubtitlePreviewResolver {
  static func snapshot(
    segments: [Segment],
    placement: SubtitleTranslationPlacement,
    filterSilentSegments: Bool,
    time: TimeInterval
  ) -> AudioSubtitlePreviewSnapshot? {
    let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
    guard let segment = resolveActiveSegment(
      in: sortedSegments,
      filterSilentSegments: filterSilentSegments,
      time: time
    ) else {
      return nil
    }

    let primaryText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !primaryText.isEmpty else { return nil }

    let translationText = segment.translation?.text
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedTranslation = translationText?.isEmpty == false ? translationText : nil

    return AudioSubtitlePreviewSnapshot(
      primaryText: primaryText,
      translationText: normalizedTranslation,
      placement: placement
    )
  }

  private static func resolveActiveSegment(
    in sortedSegments: [Segment],
    filterSilentSegments: Bool,
    time: TimeInterval
  ) -> Segment? {
    guard !sortedSegments.isEmpty else { return nil }

    if !filterSilentSegments {
      return sortedSegments.first { time >= $0.startTime && time <= $0.endTime }
    }

    let compression = SegmentCompressor.compress(sortedSegments)
    for (index, mapping) in compression.mappings.enumerated() {
      guard time >= mapping.compressedStart && time <= mapping.compressedEnd else { continue }
      return sortedSegments[index]
    }
    return nil
  }
}
