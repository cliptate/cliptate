import Foundation
import Testing

@testable import Cliptate

@Suite("AI Cut flow model")
@MainActor
struct AICutFlowModelTests {
  @Test("import normalizes files before opening setup")
  func importNormalizesFilesBeforeOpeningSetup() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let duplicate = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mp4")
    let remote = URL(string: "https://example.com/video.mp4")!

    let model = AICutFlowModel()

    model.beginImport(urls: [first, duplicate, remote, second])

    #expect(model.phase == .importSetup)
    #expect(model.pendingURLs == [first, second])
  }

  @Test("starting batch stores one shared language and enters progress")
  func startingBatchStoresOneSharedLanguage() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first, second])
    model.selectedLanguage = .japanese

    let batch = model.startBatch()

    #expect(model.phase == .transcribing)
    #expect(batch.language == .japanese)
    #expect(batch.items.map(\.url) == [first, second])
  }

  @Test("begin import moves shell from landing to setup without editing data")
  func beginImportDoesNotCreateEditingSelection() async throws {
    let model = AICutFlowModel()
    let first = URL(fileURLWithPath: "/tmp/a.mov")

    model.beginImport(urls: [first])

    #expect(model.phase == .importSetup)
    #expect(model.successfulEditingURLs.isEmpty)
    #expect(model.pendingURLs == [first])
  }

  @Test("editor handoff becomes ready only after every file reaches a terminal state")
  func editorHandoffBecomesReadyOnlyAfterEveryFileFinishes() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first, second])
    _ = model.startBatch()
    model.markFileSucceeded(first)

    #expect(model.phase == .transcribing)

    model.markFileFailed(second, message: "Mock failure")

    #expect(model.phase == .readyToEdit)
    #expect(model.successfulEditingURLs == [first])
    #expect(model.failedURLs == [second])
  }

  @Test("successful files keep import order when editor handoff becomes ready")
  func successfulFilesKeepImportOrder() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mov")
    let third = URL(fileURLWithPath: "/tmp/c.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first, second, third])
    _ = model.startBatch()
    model.markFileSucceeded(first)
    model.markFileFailed(second, message: "Mock failure")
    model.markFileSucceeded(third)

    #expect(model.phase == .readyToEdit)
    #expect(model.successfulEditingURLs == [first, third])
    #expect(model.failedURLs == [second])
  }

  @Test("all failures return to landing instead of opening editor")
  func allFailuresReturnToLanding() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first])
    _ = model.startBatch()
    model.markFileFailed(first, message: "Decode error")

    #expect(model.phase == .landing)
    #expect(model.lastErrorSummary == "Decode error")
  }

  @Test("begin import does not replace an active transcription batch")
  func beginImportDoesNotReplaceActiveTranscriptionBatch() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mov")
    let replacement = URL(fileURLWithPath: "/tmp/c.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first, second])
    let batch = model.startBatch()
    model.beginImport(urls: [replacement])

    #expect(model.phase == .transcribing)
    #expect(model.currentBatch == batch)
    #expect(model.pendingURLs == [first, second])
  }

  @Test("begin import does not replace an active editing session")
  func beginImportDoesNotReplaceActiveEditingSession() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mov")
    let replacement = URL(fileURLWithPath: "/tmp/c.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first, second])
    _ = model.startBatch()
    model.markFileSucceeded(first)
    model.markFileFailed(second, message: "Mock failure")
    model.beginImport(urls: [replacement])

    #expect(model.phase == .readyToEdit)
    #expect(model.successfulEditingURLs == [first])
    #expect(model.failedURLs == [second])
    #expect(model.pendingURLs == [first, second])
  }

  @Test("editing session is established only when handoff is committed")
  func editingSessionIsEstablishedOnlyWhenHandoffIsCommitted() async throws {
    let first = URL(fileURLWithPath: "/tmp/a.mov")
    let second = URL(fileURLWithPath: "/tmp/b.mov")
    let model = AICutFlowModel()

    model.beginImport(urls: [first, second])
    _ = model.startBatch()
    model.markFileSucceeded(first)
    model.markFileFailed(second, message: "Mock failure")

    #expect(model.phase == .readyToEdit)

    model.establishEditingSession()

    #expect(model.phase == .editing)
  }

  @Test("progress presentation reports running file and completion fraction")
  func progressPresentationReportsRunningFile() async throws {
    let batch = AICutBatchContext(
      urls: [
        URL(fileURLWithPath: "/tmp/a.mov"),
        URL(fileURLWithPath: "/tmp/b.mov"),
      ],
      language: .english,
      items: [
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/a.mov"),
          url: URL(fileURLWithPath: "/tmp/a.mov"),
          status: .succeeded
        ),
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/b.mov"),
          url: URL(fileURLWithPath: "/tmp/b.mov"),
          status: .running
        ),
      ]
    )

    let presentation = AICutProgressPresentation(batch: batch)

    #expect(presentation.title == "Transcribing 1/2")
    #expect(presentation.detail == "b.mov")
    #expect(presentation.fractionComplete == 0.5)
  }

  @Test("progress presentation uses preparation copy when nothing is running yet")
  func progressPresentationUsesPreparationCopyWhenNothingRunningYet() async throws {
    // This test will fail until AICutProgressPresentation is updated to match the spec
    let batch = AICutBatchContext(
      urls: [
        URL(fileURLWithPath: "/tmp/a.mov"),
        URL(fileURLWithPath: "/tmp/b.mov"),
      ],
      language: .english,
      items: [
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/a.mov"),
          url: URL(fileURLWithPath: "/tmp/a.mov"),
          status: .pending
        ),
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/b.mov"),
          url: URL(fileURLWithPath: "/tmp/b.mov"),
          status: .pending
        ),
      ]
    )
    let presentation = AICutProgressPresentation(batch: batch)
    #expect(presentation.title == "Preparing transcription…")
    #expect(presentation.detail == "Waiting for next file…")
    #expect(presentation.fractionComplete == 0)
  }

  @Test("progress presentation surfaces batch failure before any file starts running")
  func progressPresentationSurfacesBatchFailureBeforeRunning() async throws {
    let batch = AICutBatchContext(
      urls: [
        URL(fileURLWithPath: "/tmp/a.mov"),
        URL(fileURLWithPath: "/tmp/b.mov"),
      ],
      language: .english,
      items: [
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/a.mov"),
          url: URL(fileURLWithPath: "/tmp/a.mov"),
          status: .pending
        ),
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/b.mov"),
          url: URL(fileURLWithPath: "/tmp/b.mov"),
          status: .pending
        ),
      ]
    )

    let presentation = AICutProgressPresentation(
      batch: batch,
      statusMessage: "Batch transcription failed: Please download Parakeet V3 first."
    )

    #expect(presentation.title == "Transcription failed")
    #expect(presentation.detail == "Batch transcription failed: Please download Parakeet V3 first.")
    #expect(presentation.fractionComplete == 0)
  }

  @Test("progress presentation surfaces live transcription status while a file is running")
  func progressPresentationSurfacesLiveTranscriptionStatus() async throws {
    let batch = AICutBatchContext(
      urls: [
        URL(fileURLWithPath: "/tmp/a.mov"),
        URL(fileURLWithPath: "/tmp/b.mov"),
      ],
      language: .english,
      items: [
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/a.mov"),
          url: URL(fileURLWithPath: "/tmp/a.mov"),
          status: .succeeded
        ),
        AICutBatchItem(
          id: URL(fileURLWithPath: "/tmp/b.mov"),
          url: URL(fileURLWithPath: "/tmp/b.mov"),
          status: .running
        ),
      ]
    )

    let presentation = AICutProgressPresentation(
      batch: batch,
      statusMessage: "[2/2] Decoding audio chunks... (35%)"
    )

    #expect(presentation.title == "Transcribing 1/2")
    #expect(presentation.detail == "Getting audio ready…")
    #expect(presentation.currentFileName == "b.mov")
    #expect(presentation.fractionComplete == 0.675)
  }
}
