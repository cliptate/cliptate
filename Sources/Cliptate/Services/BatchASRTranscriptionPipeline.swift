import Foundation

/// Runs a VAD -> ASR batch transcription flow without forced alignment.
struct BatchASRTranscriptionPipeline: Sendable {
  let vad: any VADProvider
  let asr: any ASRChunkProvider
  let maxChunkDuration: Double

  init(
    vad: any VADProvider,
    asr: any ASRChunkProvider,
    maxChunkDuration: Double = 300
  ) {
    self.vad = vad
    self.asr = asr
    self.maxChunkDuration = max(1, maxChunkDuration)
  }

  func run(
    samples: [Float],
    totalDuration: Double,
    language: Language,
    modelUsed: String,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    let startTime = Date()
    let speechSegments = try await vad.detectSpeech(samples: samples, totalDuration: totalDuration)
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

    for (index, segment) in normalizedSegments.enumerated() {
      let progress = Float(index) / Float(normalizedSegments.count)
      progressHandler(
        TranscriptionProgress(
          currentSegments: finalSegments,
          progress: progress,
          statusMessage: "ASR \(index + 1)/\(normalizedSegments.count)",
          estimatedTimeRemaining: nil
        )
      )

      let chunkSamples = AudioProcessor.extractSamples(
        samples: samples,
        startTime: segment.startTime,
        endTime: segment.endTime
      )
      guard !chunkSamples.isEmpty else { continue }

      let text = try await asr.transcribe(samples: chunkSamples, language: language)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      finalSegments.append(
        Segment(
          startTime: segment.startTime,
          endTime: segment.endTime,
          text: text,
          words: nil,
          confidence: nil,
          speakerId: segment.speakerId
        )
      )
    }

    progressHandler(
      TranscriptionProgress(
        currentSegments: finalSegments,
        progress: 1.0,
        statusMessage: "ASR completed",
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
