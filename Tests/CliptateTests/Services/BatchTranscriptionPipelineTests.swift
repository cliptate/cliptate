import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("BatchTranscriptionPipeline")
struct BatchTranscriptionPipelineTests {

  // MARK: - Test doubles

  struct StubVAD: VADProvider {
    let segments: [AudioTimeRange]
    func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
      segments
    }
  }

  struct StubASR: ASRChunkProvider {
    let text: String
    func transcribe(samples: [Float], language: Language) async throws -> String { text }
  }

  struct StubAlign: AlignChunkProvider {
    func align(samples: [Float], text: String, language: Language) async throws -> [WordTiming] {
      [WordTiming(word: text, startTime: 0.0, endTime: 0.1)]
    }
  }

  struct FailingVAD: VADProvider {
    struct VADError: Error, Equatable {}
    func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
      throw VADError()
    }
  }

  struct FailingASR: ASRChunkProvider {
    struct ASRError: Error, Equatable {}
    func transcribe(samples: [Float], language: Language) async throws -> String {
      throw ASRError()
    }
  }

  // MARK: - Tests

  @Test("run produces one segment per speech region")
  func runProducesSegmentsForSpeechRegions() async throws {
    let vad = StubVAD(segments: [
      AudioTimeRange(startTime: 0, endTime: 1),
      AudioTimeRange(startTime: 2, endTime: 3),
    ])
    let pipeline = BatchTranscriptionPipeline(vad: vad, asr: StubASR(text: "hello"), align: StubAlign())
    let samples = Array(repeating: Float(0.1), count: 16000 * 4)

    let result = try await pipeline.run(
      samples: samples, totalDuration: 4, language: .english, modelUsed: "test") { _ in }

    #expect(result.segments.count == 2)
  }

  @Test("run returns empty result when VAD finds no speech")
  func runReturnsEmptyWhenNoSpeech() async throws {
    let pipeline = BatchTranscriptionPipeline(
      vad: StubVAD(segments: []), asr: StubASR(text: "hello"), align: StubAlign())

    let result = try await pipeline.run(
      samples: Array(repeating: Float(0), count: 16000), totalDuration: 1, language: .english,
      modelUsed: "test") { _ in }

    #expect(result.segments.isEmpty)
  }

  @Test("run forwards totalDuration and modelUsed to result")
  func runForwardsTotalDurationAndModelUsed() async throws {
    let pipeline = BatchTranscriptionPipeline(
      vad: StubVAD(segments: []), asr: StubASR(text: "x"), align: StubAlign())

    let result = try await pipeline.run(
      samples: [0], totalDuration: 42.5, language: .english, modelUsed: "my-model") { _ in }

    #expect(result.totalDuration == 42.5)
    #expect(result.modelUsed == "my-model")
  }

  @Test("run propagates VAD errors")
  func runPropagatesVADError() async throws {
    let pipeline = BatchTranscriptionPipeline(
      vad: FailingVAD(), asr: StubASR(text: "x"), align: StubAlign())

    await #expect(throws: FailingVAD.VADError.self) {
      _ = try await pipeline.run(
        samples: [0], totalDuration: 1, language: .english, modelUsed: "test") { _ in }
    }
  }

  @Test("run propagates ASR errors")
  func runPropagatesASRError() async throws {
    let vad = StubVAD(segments: [AudioTimeRange(startTime: 0, endTime: 1)])
    let pipeline = BatchTranscriptionPipeline(vad: vad, asr: FailingASR(), align: StubAlign())
    let samples = Array(repeating: Float(0.1), count: 16000 * 2)

    await #expect(throws: FailingASR.ASRError.self) {
      _ = try await pipeline.run(
        samples: samples, totalDuration: 2, language: .english, modelUsed: "test") { _ in }
    }
  }

  @Test("run reports progress from 0 to 1")
  func runReportsProgressRange() async throws {
    let vad = StubVAD(segments: [
      AudioTimeRange(startTime: 0, endTime: 1),
      AudioTimeRange(startTime: 2, endTime: 3),
    ])
    let pipeline = BatchTranscriptionPipeline(vad: vad, asr: StubASR(text: "hi"), align: StubAlign())
    let samples = Array(repeating: Float(0.1), count: 16000 * 4)

    nonisolated(unsafe) var progressValues: [Float] = []
    _ = try await pipeline.run(
      samples: samples, totalDuration: 4, language: .english, modelUsed: "test"
    ) { progress in
      progressValues.append(progress.progress)
    }

    #expect(!progressValues.isEmpty)
    #expect(progressValues.first! >= 0)
    #expect(progressValues.last! == 1.0)
  }
}

@Suite("BatchASRTranscriptionPipeline")
struct BatchASRTranscriptionPipelineTests {
  struct StubVAD: VADProvider {
    let segments: [AudioTimeRange]
    func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
      segments
    }
  }

  struct StubASR: ASRChunkProvider {
    let text: String
    func transcribe(samples: [Float], language: Language) async throws -> String { text }
  }

  @Test("run produces plain segments without word timings")
  func runProducesPlainSegments() async throws {
    let pipeline = BatchASRTranscriptionPipeline(
      vad: StubVAD(segments: [AudioTimeRange(startTime: 0, endTime: 1)]),
      asr: StubASR(text: "hello world")
    )

    let result = try await pipeline.run(
      samples: Array(repeating: Float(0.1), count: 16000 * 2),
      totalDuration: 2,
      language: .english,
      modelUsed: "test"
    ) { _ in }

    #expect(result.segments.count == 1)
    #expect(result.segments[0].text == "hello world")
    #expect(result.segments[0].words == nil)
  }

  @Test("run preserves speaker ids from VAD ranges")
  func runPreservesSpeakerIDs() async throws {
    let pipeline = BatchASRTranscriptionPipeline(
      vad: StubVAD(segments: [AudioTimeRange(startTime: 0, endTime: 1, speakerId: 7)]),
      asr: StubASR(text: "hello")
    )

    let result = try await pipeline.run(
      samples: Array(repeating: Float(0.1), count: 16000 * 2),
      totalDuration: 2,
      language: .english,
      modelUsed: "test"
    ) { _ in }

    #expect(result.segments.count == 1)
    #expect(result.segments[0].speakerId == 7)
  }
}

@Suite("BatchTranscriptionService samples-backed requests")
struct BatchTranscriptionServiceSamplesTests {
  final class MockChunkTranscriber: ChunkTranscriber, @unchecked Sendable {
    func warmUpModelWithProgress(progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void)
      async throws
    {}

    func transcribeWithProgress(
      audioPath: String,
      language: Language,
      progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResult {
      Issue.record("File-backed transcription path should not be used for samples-backed requests")
      return TranscriptionResult(segments: [], totalDuration: 0, processingTime: 0, modelUsed: "mock")
    }

    func transcribeChunk(samples: [Float], language: Language) async throws -> String {
      "samples-\(samples.count)"
    }
  }

  private func makeFakeLease() -> ASRModelLease {
    unsafeBitCast(
      (ModelLifecycleKey(kind: .asr, identifier: "test"), UUID()),
      to: ASRModelLease.self
    )
  }

  struct StubVAD: VADProvider {
    func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
      [AudioTimeRange(startTime: 0, endTime: totalDuration)]
    }
  }

  struct StubASR: ASRChunkProvider {
    func transcribe(samples: [Float], language: Language) async throws -> String {
      "samples-\(samples.count)"
    }
  }

  @Test("samples-backed request bypasses source URL loading")
  func samplesBackedRequestBypassesSourceURLLoading() async throws {
    let transcriber = MockChunkTranscriber()
    let service = BatchTranscriptionService(
      loadAudioSamples: { _ in
        Issue.record("Samples-backed requests should not load audio from URL")
        return []
      },
      loadDuration: { _ in
        Issue.record("Samples-backed requests should not load duration from URL")
        return 0
      },
      acquireASRTranscriber: { _, _, _ in
        (transcriber, makeFakeLease())
      },
      releaseASRLease: { _ in },
      acquireAlignTranscriber: { _, _ in
        Issue.record("Dictation finalization should not request alignment")
        return Qwen3ForcedAlignerTranscriber(model: .qwen3ForcedAligner)
      },
      makePostProcessor: { _ in
        TranscriptionPostProcessor(
          speakerPropagation: PlainASRSpeakerPropagation(
            vadModel: .sileroVAD,
            loadAudioSamples: { _ in [] },
            detectSpeakerRanges: { _, _ in [] }
          )
        )
      },
      makeSourceBookmark: { _ in
        Issue.record("Samples-backed dictation finalization should not create a source bookmark")
        return nil
      },
      makeBatchPlan: { _, _, _, _ in
        BatchTranscriptionPlan(vad: StubVAD(), asr: StubASR(), align: nil)
      }
    )

    let output = try await service.transcribe(
      request: BatchTranscriptionSamplesRequest(
        audioSamples: Array(repeating: 0.1, count: 16_000),
        totalDuration: 1.0,
        workflow: .dictationFinalization,
        transcriberType: .parakeet,
        asrModel: .parakeetV3,
        vadModel: .sileroVAD,
        alignModel: nil,
        language: .english,
        dictionaryEntries: []
      ),
      progressHandler: { _ in }
    )

    #expect(output.result.totalDuration == 1.0)
    #expect(output.result.segments.count == 1)
    #expect(output.result.segments[0].text == "samples-16000")
    #expect(output.sourceURLBookmark == nil)
  }
}
