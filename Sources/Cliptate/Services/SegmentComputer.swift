import Foundation

/// Pure-function segment processing pipeline.
/// Computes display-ready segments from raw transcription segments + configuration.
/// Used by both the UI (SegmentsPanelView) and export (AICutView).
enum SegmentComputer {

  struct Input {
    let segments: [Segment]
    let totalDuration: TimeInterval
    let filterSilent: Bool
    let splitBySentence: Bool
    let maxCharsPerSegment: Int
    let leftPadMs: Int
    let rightPadMs: Int
    let effectFilterFillerWords: Bool
    let fillerWords: [String]
    let dictionaryEntries: [String]
    let removedSegmentIDs: Set<SegmentIdentifier>
    let processedTranslations: [String: SegmentTranslation]
  }

  @MainActor
  static func compute(_ input: Input) -> [Segment] {
    if input.segments.isEmpty { return [] }

    // 1. Filter silent/empty segments
    let base: [Segment]
    if input.filterSilent {
      base = input.segments.filter {
        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && $0.text != "..." && $0.text != "[*]"
      }
    } else {
      base = input.segments
    }

    // 2. Build operations pipeline
    var ops: [SegmentProcess.Operation] = []
    if input.splitBySentence {
      ops.append(.splitBySentence)
    }
    if input.maxCharsPerSegment > 0 {
      ops.append(.splitByNatural(.init(maxChars: input.maxCharsPerSegment)))
    }
    ops.append(.padding(leftMs: input.leftPadMs, rightMs: input.rightPadMs))

    var processed = SegmentProcess.process(
      segments: base,
      totalDuration: input.totalDuration,
      operations: ops
    )

    // 3. Filler word filtering
    if input.effectFilterFillerWords {
      let fillerSet = Set(input.fillerWords.map { $0.lowercased() })
      processed = FillerWordFilter.filterSegments(processed, fillerWords: fillerSet)
    }

    // 4. Dictionary bias
    processed = ASRDictionaryBiasService.apply(
      to: processed,
      dictionaryEntries: input.dictionaryEntries
    )

    // 5. Remove deleted segments
    if !input.removedSegmentIDs.isEmpty {
      processed = processed.filter { segment in
        !input.removedSegmentIDs.contains(SegmentIdentifier(segment: segment))
      }
    }

    // 6. Inject translations
    if !input.processedTranslations.isEmpty {
      processed = VideoState.injectTranslations(input.processedTranslations, into: processed)
    }

    return processed
  }
}
