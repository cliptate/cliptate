import Foundation

enum SegmentSignature {
  static func compute(for segments: [Segment]) -> Int {
    segments.reduce(into: 17) { partial, segment in
      partial = partial &* 31 &+ Int(segment.startTime * 1000)
      partial = partial &* 31 &+ Int(segment.endTime * 1000)
      partial = partial &* 31 &+ segment.text.hashValue
      if let words = segment.words {
        partial = partial &* 31 &+ words.count
      }
    }
  }
}
