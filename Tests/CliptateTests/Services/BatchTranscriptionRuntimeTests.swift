import Foundation
import Testing

@testable import Cliptate

@Suite("BatchTranscriptionRuntime")
struct BatchTranscriptionRuntimeTests {
  @Test("runtime forwards file transcription requests through its interface")
  func forwardsFileRequests() async throws {
    let expected = BatchTranscriptionOutput(
      result: TranscriptionResult(
        segments: [],
        totalDuration: 1,
        processingTime: 0.1,
        modelUsed: "test-model",
        createdAt: .distantPast
      ),
      speakerAnnotationApplied: false,
      sourceURLBookmark: nil
    )
    let executor = FakeBatchExecutor(fileResult: expected)
    let runtime = BatchTranscriptionRuntime(executor: executor)
    let request = BatchTranscriptionRequest(
      sourceURL: URL(fileURLWithPath: "/tmp/audio.wav"),
      workflow: .fileTranscription,
      transcriberType: .qwen3,
      asrModel: .qwen3ASR,
      vadModel: .sileroVAD,
      alignModel: nil,
      language: .english,
      dictionaryEntries: []
    )

    let result = try await runtime.transcribe(
      request: request,
      progressHandler: { _ in }
    )

    #expect(result.result.modelUsed == expected.result.modelUsed)
    #expect(result.result.totalDuration == expected.result.totalDuration)
    #expect(result.speakerAnnotationApplied == expected.speakerAnnotationApplied)
    let recordedRequests = await executor.fileRequests
    #expect(recordedRequests.count == 1)
    #expect(recordedRequests.first?.sourceURL == request.sourceURL)
    #expect(recordedRequests.first?.workflow == request.workflow)
    #expect(recordedRequests.first?.transcriberType == request.transcriberType)
    #expect(recordedRequests.first?.asrModel == request.asrModel)
  }
}

private actor FakeBatchExecutor: BatchTranscriptionExecuting {
  let fileResult: BatchTranscriptionOutput
  private(set) var fileRequests: [BatchTranscriptionRequest] = []

  init(fileResult: BatchTranscriptionOutput) {
    self.fileResult = fileResult
  }

  func transcribe(
    request: BatchTranscriptionRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput {
    fileRequests.append(request)
    return fileResult
  }

  func transcribe(
    request: BatchTranscriptionSamplesRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput {
    fileResult
  }
}
