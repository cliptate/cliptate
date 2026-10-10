import Foundation
import Testing
@testable import Cliptate

@Suite("AICutProgressPresentation phase and display")
struct AICutProgressPresentationTests {

  private func makeBatch(
    statuses: [AICutBatchItem.Status]
  ) -> AICutBatchContext {
    let urls = statuses.indices.map { URL(fileURLWithPath: "/tmp/file\($0).mov") }
    let items = zip(urls, statuses).map { AICutBatchItem(id: $0, url: $0, status: $1) }
    return AICutBatchContext(urls: urls, language: .english, items: items)
  }

  // MARK: - Display phase

  @Test func displayPhase_modelInit_whenInitializingWithProgress() {
    let modelProgress = ModelDownloadProgress(
      currentStep: "Loading model…",
      progress: 0.4,
      estimatedTimeRemaining: nil,
      attemptNumber: 1,
      maxAttempts: 3
    )
    let presentation = AICutProgressPresentation(
      batch: nil,
      statusMessage: nil,
      isInitializingModel: true,
      modelDownloadProgress: modelProgress
    )
    #expect(presentation.displayPhase == .modelInit)
    #expect(abs(presentation.displayFraction - 0.4) < 0.001)
  }

  @Test func displayPhase_modelInit_whenInitializingButNilProgress() {
    let presentation = AICutProgressPresentation(
      batch: nil,
      statusMessage: nil,
      isInitializingModel: true,
      modelDownloadProgress: nil
    )
    #expect(presentation.displayPhase == .modelInit)
    #expect(presentation.displayFraction == 0)
  }

  @Test func displayPhase_transcribing_whenNotInitializing() {
    let batch = makeBatch(statuses: [.running])
    let presentation = AICutProgressPresentation(
      batch: batch,
      statusMessage: "[1/1] Decoding audio chunks... (50%)",
      isInitializingModel: false,
      modelDownloadProgress: nil
    )
    #expect(presentation.displayPhase == .transcribing)
    #expect(presentation.displayFraction > 0)
    #expect(presentation.detail == "Getting audio ready…")
    #expect(presentation.currentFileName == "file0.mov")
  }

  @Test func liveStatusMessage_hidesASRTermsBehindFriendlyCopy() {
    let batch = makeBatch(statuses: [.running])
    let presentation = AICutProgressPresentation(
      batch: batch,
      statusMessage: "ASR 1/3",
      isInitializingModel: false,
      modelDownloadProgress: nil
    )

    #expect(presentation.detail == "Converting speech to text…")
  }

  @Test func liveStatusMessage_hidesAlignmentTermsBehindFriendlyCopy() {
    let batch = makeBatch(statuses: [.running])
    let presentation = AICutProgressPresentation(
      batch: batch,
      statusMessage: "Align 1/3",
      isInitializingModel: false,
      modelDownloadProgress: nil
    )

    #expect(presentation.detail == "Matching words to timing…")
  }

  @Test func displayPhase_failed_overridesModelInit() {
    let presentation = AICutProgressPresentation(
      batch: nil,
      statusMessage: "Batch transcription failed: model error",
      isInitializingModel: true,
      modelDownloadProgress: ModelDownloadProgress(
        currentStep: "Loading…",
        progress: 0.5,
        estimatedTimeRemaining: nil,
        attemptNumber: 1,
        maxAttempts: 3
      )
    )
    #expect(presentation.displayPhase == .terminal)
    #expect(presentation.title == "Transcription failed")
  }

  @Test func displayPhase_cancelled_overridesModelInit() {
    let presentation = AICutProgressPresentation(
      batch: nil,
      statusMessage: "Transcription cancelled by user",
      isInitializingModel: true,
      modelDownloadProgress: nil
    )
    #expect(presentation.displayPhase == .terminal)
  }

  @Test func displayFraction_clampedToZeroOne() {
    let presentation = AICutProgressPresentation(
      batch: nil,
      statusMessage: nil,
      isInitializingModel: false,
      modelDownloadProgress: nil
    )
    #expect(presentation.displayFraction >= 0)
    #expect(presentation.displayFraction <= 1)
  }

  // MARK: - Backward compatibility

  @Test func legacyInit_stillWorks() {
    let batch = makeBatch(statuses: [.succeeded])
    let presentation = AICutProgressPresentation(batch: batch, statusMessage: nil)
    #expect(presentation.fractionComplete == 1.0)
    #expect(presentation.displayPhase == .transcribing)
    #expect(presentation.displayFraction == 1.0)
  }
}
