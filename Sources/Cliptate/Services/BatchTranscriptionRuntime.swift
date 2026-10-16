import CliptateCore
import Foundation

protocol BatchTranscriptionExecuting: Sendable {
  func transcribe(
    request: BatchTranscriptionRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput

  func transcribe(
    request: BatchTranscriptionSamplesRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput
}

extension BatchTranscriptionService: BatchTranscriptionExecuting, @unchecked Sendable {}

struct BatchTranscriptionRuntime: Sendable {
  static let shared = BatchTranscriptionRuntime()

  private let executor: any BatchTranscriptionExecuting

  init(executor: any BatchTranscriptionExecuting = BatchTranscriptionService()) {
    self.executor = executor
  }

  func transcribe(
    request: BatchTranscriptionRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in },
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput {
    let started = Date()
    do {
      let output = try await executor.transcribe(
        request: request,
        modelProgressHandler: modelProgressHandler,
        progressHandler: progressHandler
      )
      await AnalyticsRuntime.shared.record(.operationFinished(
        .transcription, outcome: .succeeded, durationSeconds: Date().timeIntervalSince(started)))
      return output
    } catch {
      await AnalyticsRuntime.shared.record(.operationFinished(
        .transcription,
        outcome: error is CancellationError || Task.isCancelled ? .cancelled : .failed,
        durationSeconds: Date().timeIntervalSince(started)))
      throw error
    }
  }

  func transcribe(
    request: BatchTranscriptionSamplesRequest,
    modelProgressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in },
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> BatchTranscriptionOutput {
    let started = Date()
    do {
      let output = try await executor.transcribe(
        request: request,
        modelProgressHandler: modelProgressHandler,
        progressHandler: progressHandler
      )
      await AnalyticsRuntime.shared.record(.operationFinished(
        .transcription, outcome: .succeeded, durationSeconds: Date().timeIntervalSince(started)))
      return output
    } catch {
      await AnalyticsRuntime.shared.record(.operationFinished(
        .transcription,
        outcome: error is CancellationError || Task.isCancelled ? .cancelled : .failed,
        durationSeconds: Date().timeIntervalSince(started)))
      throw error
    }
  }
}
