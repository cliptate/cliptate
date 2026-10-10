import Foundation

/// Shared pure helper that maps VAD speaker ranges onto ASR segments by maximum overlap.
enum SegmentSpeakerAnnotator {
  /// Annotates each Segment with the speakerId of the VAD range that has the
  /// most temporal overlap. Segments with no overlapping VAD range keep speakerId=nil.
  static func annotate(
    _ segments: [Segment],
    withSpeakers vadRanges: [AudioTimeRange]
  ) -> [Segment] {
    segments.map { segment in
      var bestSpeaker: Int?
      var bestOverlap: Double = 0

      for range in vadRanges {
        guard let speakerId = range.speakerId else { continue }
        let overlapStart = max(segment.startTime, range.startTime)
        let overlapEnd = min(segment.endTime, range.endTime)
        let overlap = overlapEnd - overlapStart
        if overlap > bestOverlap {
          bestOverlap = overlap
          bestSpeaker = speakerId
        }
      }

      guard let bestSpeaker else { return segment }
      return Segment(
        id: segment.id,
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: segment.text,
        words: segment.words,
        confidence: segment.confidence,
        speakerId: bestSpeaker,
        translation: segment.translation
      )
    }
  }
}
