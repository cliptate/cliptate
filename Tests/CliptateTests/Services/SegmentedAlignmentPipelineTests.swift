import Foundation
import Testing

@testable import Cliptate

@Suite("SegmentedAlignmentPipeline")
struct SegmentedAlignmentPipelineTests {
  @Test("splits long segments to keep chunk duration under cap")
  func splitsLongSegmentsForAlignmentCap() async throws {
    nonisolated(unsafe) var observedDurations: [Double] = []
    let pipeline = SegmentedAlignmentPipeline(maxChunkDuration: 300)

    _ = try await pipeline.run(
      speechSegments: [AudioTimeRange(startTime: 0, endTime: 420)],
      totalDuration: 420,
      modelUsed: "test",
      progressHandler: { _ in },
      transcribe: { _ in "hello" },
      align: { segment, _ in
        observedDurations.append(segment.endTime - segment.startTime)
        return [WordTiming(word: "hello", startTime: 0.1, endTime: 0.3)]
      }
    )

    #expect(observedDurations.count == 2)
    #expect(observedDurations.allSatisfy { $0 <= 300 })
  }

  @Test("speakerId preserved when long segment is split into sub-chunks")
  func speakerIdPreservedAcrossChunkSplits() async throws {
    let pipeline = SegmentedAlignmentPipeline(maxChunkDuration: 300)

    let result = try await pipeline.run(
      speechSegments: [AudioTimeRange(startTime: 0, endTime: 420, speakerId: 2)],
      totalDuration: 420,
      modelUsed: "test",
      progressHandler: { _ in },
      transcribe: { _ in "hi" },
      align: { _, _ in [WordTiming(word: "hi", startTime: 0.1, endTime: 0.3)] }
    )

    #expect(result.segments.count == 2)
    #expect(result.segments.allSatisfy { $0.speakerId == 2 })
  }

  @Test("rebases local chunk timings into monotonic global timeline")
  func rebasesTimingsMonotonically() async throws {
    let pipeline = SegmentedAlignmentPipeline(maxChunkDuration: 300)

    let result = try await pipeline.run(
      speechSegments: [
        AudioTimeRange(startTime: 0, endTime: 2),
        AudioTimeRange(startTime: 5, endTime: 7),
      ],
      totalDuration: 7,
      modelUsed: "test",
      progressHandler: { _ in },
      transcribe: { _ in "x" },
      align: { _, _ in
        [WordTiming(word: "x", startTime: 0.1, endTime: 0.2)]
      }
    )

    #expect(result.segments.count == 2)
    let w0 = result.segments[0].words?.first
    let w1 = result.segments[1].words?.first
    #expect(w0?.startTime == 0.1)
    #expect(w1?.startTime == 5.1)
  }

  @Test("speaker IDs are propagated to output segments")
  func speakerIdsPropagate() async throws {
    let pipeline = SegmentedAlignmentPipeline(maxChunkDuration: 300)

    let result = try await pipeline.run(
      speechSegments: [
        AudioTimeRange(startTime: 0, endTime: 2, speakerId: 0),
        AudioTimeRange(startTime: 5, endTime: 7, speakerId: 1),
      ],
      totalDuration: 7,
      modelUsed: "test",
      progressHandler: { _ in },
      transcribe: { _ in "hello" },
      align: { _, _ in [WordTiming(word: "hello", startTime: 0.1, endTime: 0.5)] }
    )

    #expect(result.segments.count == 2)
    #expect(result.segments[0].speakerId == 0)
    #expect(result.segments[1].speakerId == 1)
  }

  @Test("fails fast when any chunk transcription or alignment fails")
  func failsFastOnChunkFailure() async throws {
    let pipeline = SegmentedAlignmentPipeline(maxChunkDuration: 300)
    await #expect(throws: Error.self) {
      _ = try await pipeline.run(
        speechSegments: [
          AudioTimeRange(startTime: 0, endTime: 2),
          AudioTimeRange(startTime: 3, endTime: 5),
        ],
        totalDuration: 5,
        modelUsed: "test",
        progressHandler: { _ in },
        transcribe: { segment in
          if segment.startTime >= 3 {
            throw NSError(domain: "SegmentedAlignmentPipelineTests", code: 1)
          }
          return "ok"
        },
        align: { _, _ in
          [WordTiming(word: "ok", startTime: 0.1, endTime: 0.2)]
        }
      )
    }
  }
}
