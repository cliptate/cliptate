import Foundation

struct SegmentedAlignmentPipeline {
  typealias TranscribeClosure = @Sendable (AudioTimeRange) async throws -> String
  typealias AlignClosure = @Sendable (AudioTimeRange, String) async throws -> [WordTiming]

  let maxChunkDuration: Double

  init(maxChunkDuration: Double = 300) {
    self.maxChunkDuration = max(1, maxChunkDuration)
  }

  func run(
    speechSegments: [AudioTimeRange],
    totalDuration: Double,
    modelUsed: String,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void,
    transcribe: TranscribeClosure,
    align: AlignClosure
  ) async throws -> TranscriptionResult {
    let startTime = Date()
    let normalizedSegments = normalizeAndSplit(segments: speechSegments)

    guard !normalizedSegments.isEmpty else {
      return TranscriptionResult(
        segments: [],
        totalDuration: totalDuration,
        processingTime: Date().timeIntervalSince(startTime),
        modelUsed: modelUsed
      )
    }

    var finalSegments: [Segment] = []
    finalSegments.reserveCapacity(normalizedSegments.count)

    for (index, chunk) in normalizedSegments.enumerated() {
      let asrProgress = Float(index) / Float(normalizedSegments.count)
      progressHandler(
        TranscriptionProgress(
          currentSegments: finalSegments,
          progress: asrProgress,
          statusMessage: "ASR \(index + 1)/\(normalizedSegments.count)",
          estimatedTimeRemaining: nil
        )
      )

      let text = try await transcribe(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      let alignProgress = min(0.99, (Float(index) + 0.5) / Float(normalizedSegments.count))
      progressHandler(
        TranscriptionProgress(
          currentSegments: finalSegments,
          progress: alignProgress,
          statusMessage: "Align \(index + 1)/\(normalizedSegments.count)",
          estimatedTimeRemaining: nil
        )
      )

      let localWords = try await align(chunk, text)
      let rebasedWords = localWords.map { word in
        WordTiming(
          word: word.word,
          startTime: chunk.startTime + word.startTime,
          endTime: chunk.startTime + word.endTime,
          confidence: word.confidence,
          punctuation: word.punctuation
        )
      }
      guard !rebasedWords.isEmpty else { continue }

      let chunkText = WordTimingTextComposer.composeText(from: rebasedWords)
      finalSegments.append(
        Segment(
          startTime: rebasedWords[0].startTime,
          endTime: rebasedWords[rebasedWords.count - 1].endTime,
          text: chunkText,
          words: rebasedWords,
          confidence: nil,
          speakerId: chunk.speakerId
        )
      )
    }

    progressHandler(
      TranscriptionProgress(
        currentSegments: finalSegments,
        progress: 1.0,
        statusMessage: "Alignment completed",
        estimatedTimeRemaining: 0
      )
    )

    return TranscriptionResult(
      segments: finalSegments,
      totalDuration: totalDuration,
      processingTime: Date().timeIntervalSince(startTime),
      modelUsed: modelUsed
    )
  }

  private func normalizeAndSplit(segments: [AudioTimeRange]) -> [AudioTimeRange] {
    var result: [AudioTimeRange] = []
    result.reserveCapacity(segments.count)
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      guard segment.endTime > segment.startTime else { continue }
      var cursor = segment.startTime
      while cursor < segment.endTime {
        let next = min(segment.endTime, cursor + maxChunkDuration)
        result.append(AudioTimeRange(startTime: cursor, endTime: next, speakerId: segment.speakerId))
        cursor = next
      }
    }
    return result
  }
}
