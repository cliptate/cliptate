import Foundation

struct StreamingSpeechAccumulator: Sendable {
  private(set) var pendingSpeech: [Float] = []
  private let maxBufferedSamples: Int
  private let requiredConsecutiveSilentChunks: Int
  private var consecutiveSilentChunks: Int = 0

  init(maxBufferedSamples: Int, requiredConsecutiveSilentChunks: Int = 1) {
    self.maxBufferedSamples = max(1, maxBufferedSamples)
    self.requiredConsecutiveSilentChunks = max(1, requiredConsecutiveSilentChunks)
  }

  var hasPendingSpeech: Bool {
    !pendingSpeech.isEmpty
  }

  mutating func ingest(
    chunk: [Float],
    speechSampleRanges: [Range<Int>]
  ) -> [Float]? {
    guard !chunk.isEmpty else { return nil }

    if speechSampleRanges.isEmpty {
      guard !pendingSpeech.isEmpty else { return nil }
      consecutiveSilentChunks += 1
      guard consecutiveSilentChunks >= requiredConsecutiveSilentChunks else { return nil }
      return flush()
    }

    consecutiveSilentChunks = 0

    for range in speechSampleRanges {
      guard !range.isEmpty else { continue }
      let lowerBound = max(0, min(range.lowerBound, chunk.count))
      let upperBound = max(lowerBound, min(range.upperBound, chunk.count))
      guard lowerBound < upperBound else { continue }
      pendingSpeech.append(contentsOf: chunk[lowerBound..<upperBound])
    }

    guard pendingSpeech.count >= maxBufferedSamples else { return nil }
    let emission = Array(pendingSpeech.prefix(maxBufferedSamples))
    pendingSpeech.removeAll(keepingCapacity: true)
    consecutiveSilentChunks = 0
    return emission
  }

  mutating func flush() -> [Float]? {
    guard !pendingSpeech.isEmpty else { return nil }
    let emission = pendingSpeech
    pendingSpeech.removeAll(keepingCapacity: true)
    consecutiveSilentChunks = 0
    return emission
  }
}
