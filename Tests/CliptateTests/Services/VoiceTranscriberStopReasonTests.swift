import CliptateCore
import AppKit
import Foundation
import Testing

@testable import Cliptate

@Suite("VoiceTranscriber stop reason and retranscription state", .serialized)
@MainActor
struct VoiceTranscriberStopReasonTests {


  @Test("streaming startup does not fail before provider is available")
  func streamingStartupKeepsMissingProviderTolerant() throws {
    let source = try voiceTranscriberSource()

    #expect(source.contains("if let provider = activeStreamingProvider"))
    #expect(source.contains("no active streaming provider available") == false)
  }

  @Test("StopReason enum has normal and cancelled cases")
  func stopReasonCases() {
    let normal = VoiceTranscriber.StopReason.normal
    let cancelled = VoiceTranscriber.StopReason.cancelled
    #expect(normal == .normal)
    #expect(cancelled == .cancelled)
    #expect(normal != cancelled)
  }

  @Test("isRetranscribing defaults to false")
  func initialRetranscribingState() {
    let transcriber = VoiceTranscriber.shared
    #expect(transcriber.isRetranscribing == false)
  }

  @Test("retranscriptionStatus defaults to nil")
  func initialRetranscriptionStatus() {
    let transcriber = VoiceTranscriber.shared
    #expect(transcriber.retranscriptionStatus == nil)
  }

  @Test("Qwen3 streaming does not update session lines (display-only)")
  func qwen3StreamingDoesNotUpdateSession() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()

    // Set up a fresh session
    transcriber.testSetSession(TranscriptSession())

    // Simulate a Qwen3 streaming update
    transcriber.testHandleQwen3StreamUpdate("Hello streaming world")

    // Session lines should remain empty — streaming is display-only
    #expect(transcriber.session?.lines.isEmpty == true)
    // But liveText should be updated for display
    #expect(transcriber.liveText.contains("Hello"))

    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Parakeet streaming does not update session lines (display-only)")
  func parakeetStreamingDoesNotUpdateSession() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()  // reuse same preparation

    // Set up a fresh session
    transcriber.testSetSession(TranscriptSession())

    // Simulate a Parakeet streaming update
    transcriber.testHandleParakeetStreamUpdate("Hello parakeet streaming")

    // Session lines should remain empty — streaming is display-only
    #expect(transcriber.session?.lines.isEmpty == true)
    // But liveText should be updated for display
    #expect(transcriber.liveText.contains("Hello"))

    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Revised previews remain display-only and batch output replaces them for delivery and history")
  func batchResultReplacesRevisedPreviews() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    let previousAutoType = transcriber.autoTypeEnabled
    let session = TranscriptSession()
    defer {
      TranscriptHistoryStore.shared.remove(id: session.id)
      transcriber.autoTypeEnabled = previousAutoType
      transcriber.testResetAfterQwen3StreamAssertions()
    }
    transcriber.autoTypeEnabled = false
    transcriber.testSetSession(session)
    transcriber.testHandleQwen3StreamUpdate("I scream")
    transcriber.testHandleQwen3StreamUpdate("Ice cream")
    #expect(transcriber.liveText == "Ice cream")
    #expect(transcriber.session?.lines.isEmpty == true)
    let deliveredBeforeBatch = Mirror(reflecting: transcriber).children
      .first { $0.label == "deliveredText" }?.value as? String
    #expect(deliveredBeforeBatch == "")

    let batch = BatchTranscriptionOutput(
      result: TranscriptionResult(
        segments: [Segment(startTime: 0, endTime: 1, text: "Ice cream, please.")],
        totalDuration: 1, processingTime: 0, modelUsed: ModelVariant.whisperTiny.rawValue
      ), speakerAnnotationApplied: false, sourceURLBookmark: nil
    )
    transcriber.testApplyDictationBatchOutput(batch)
    #expect(transcriber.liveText == "Ice cream, please.")
    #expect(transcriber.session?.combinedText == "Ice cream, please.")
    #expect(TranscriptHistoryStore.shared.recentDictationSessions
      .first { $0.id == session.id }?.combinedText == "Ice cream, please.")
    let deliveredAfterBatch = Mirror(reflecting: transcriber).children
      .first { $0.label == "deliveredText" }?.value as? String
    #expect(deliveredAfterBatch == "Ice cream, please.")
  }

  @Test("An empty revised hypothesis clears the preview without changing the session")
  func emptyRevisionClearsPreview() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    defer { transcriber.testResetAfterQwen3StreamAssertions() }
    transcriber.testSetSession(TranscriptSession())
    transcriber.testHandleQwen3StreamUpdate("false start")
    transcriber.testHandleQwen3StreamUpdate("")
    #expect(transcriber.liveText.isEmpty)
    #expect(transcriber.session?.lines.isEmpty == true)
  }

  @Test("Delivered dictation output collapses embedded newlines before typing")
  func deliveredOutputCollapsesEmbeddedNewlines() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.autoTypeEnabled = false
    transcriber.testSetSession(
      TranscriptSession(
        lines: [
          TranscriptLine(timestamp: 0, text: "It's a test."),
          TranscriptLine(timestamp: 1, text: "What test?"),
          TranscriptLine(timestamp: 2, text: "Yeah."),
        ]
      )
    )
    transcriber.testDeliverFinalSessionOutput()

    let mirror = Mirror(reflecting: transcriber)
    let deliveredText = mirror.children.first { $0.label == "deliveredText" }?.value as? String

    #expect(deliveredText == "It's a test. What test? Yeah.")

    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Assistant output collapses embedded newlines before typing")
  func assistantOutputCollapsesEmbeddedNewlines() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.autoTypeEnabled = false

    transcriber.deliverAssistantOutput("It's a test.\nWhat test?\nYeah.")

    let mirror = Mirror(reflecting: transcriber)
    let deliveredText = mirror.children.first { $0.label == "deliveredText" }?.value as? String

    #expect(deliveredText == "It's a test. What test? Yeah.")

    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Whitespace-only delivery differences do not replace already delivered text")
  func normalizedDuplicateOutputDoesNotRedeliver() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.autoTypeEnabled = false
    transcriber.testSetSession(
      TranscriptSession(
        lines: [
          TranscriptLine(timestamp: 0, text: "It's a test."),
          TranscriptLine(timestamp: 1, text: "What test?"),
          TranscriptLine(timestamp: 2, text: "Yeah."),
        ]
      )
    )

    transcriber.testDeliverFinalSessionOutput()
    transcriber.deliverAssistantOutput("It's a test.\nWhat test?\nYeah.")

    let mirror = Mirror(reflecting: transcriber)
    let deliveredText = mirror.children.first { $0.label == "deliveredText" }?.value as? String

    #expect(deliveredText == "It's a test. What test? Yeah.")

    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("AI dictation delivers only the final AI text, including after reopening Voice To Text", arguments: [false, true])
  func aiDictationDeliversOnlyAfterPostProcessing(reopenView: Bool) async {
    let transcriber = VoiceTranscriber.shared
    let shortcuts = VoiceShortcutState.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    let previousAutoType = transcriber.autoTypeEnabled
    let session = TranscriptSession()
    defer {
      TranscriptHistoryStore.shared.remove(id: session.id)
      shortcuts.cancelSession()
      transcriber.deliverTranscriptsDirectly = true
      transcriber.autoTypeEnabled = previousAutoType
      transcriber.testResetAfterQwen3StreamAssertions()
    }
    shortcuts.activateMode(.dictation)
    // ContentView suppresses raw delivery when activating an AI-enhanced shortcut.
    transcriber.deliverTranscriptsDirectly = false
    transcriber.testSetSession(session)
    transcriber.testHandleQwen3StreamUpdate("raw spoken words")

    // Replay the real view appearance setup during this recording.
    if reopenView {
      VoiceToTextView(transcriber: transcriber).configureTranscriptDeliveryOnAppear()
    }
    transcriber.autoTypeEnabled = false
    shortcuts.requestEndSession()
    await transcriber.stop()
    let beforeAI = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(beforeAI == "", "Raw transcription must not be delivered while AI enhancement is pending")

    transcriber.deliverAssistantOutput("AI corrected words")
    let afterAI = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(afterAI == "AI corrected words")
  }

  @Test("Batch finalization retains this recording's delivery policy when defaults change", arguments: [false, true])
  func batchFinalizationKeepsSessionDeliveryPolicy(allowRawDelivery: Bool) {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    let previousAutoType = transcriber.autoTypeEnabled
    let session = TranscriptSession()
    defer {
      TranscriptHistoryStore.shared.remove(id: session.id)
      transcriber.deliverTranscriptsDirectly = true
      transcriber.autoTypeEnabled = previousAutoType
      transcriber.testResetAfterQwen3StreamAssertions()
    }
    transcriber.autoTypeEnabled = false
    transcriber.testSetSession(session)
    transcriber.deliverTranscriptsDirectly = allowRawDelivery
    transcriber.testCaptureTranscriptDeliveryForSession()
    // Navigation/finish observers or a new shortcut can change the future default.
    transcriber.deliverTranscriptsDirectly = !allowRawDelivery
    let batch = BatchTranscriptionOutput(
      result: TranscriptionResult(
        segments: [Segment(startTime: 0, endTime: 1, text: "raw batch words")],
        totalDuration: 1, processingTime: 0, modelUsed: ModelVariant.whisperTiny.rawValue
      ), speakerAnnotationApplied: false, sourceURLBookmark: nil
    )
    transcriber.testApplyDictationBatchOutput(batch)
    let beforeAI = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(beforeAI == (allowRawDelivery ? "raw batch words" : ""))
    if !allowRawDelivery {
      transcriber.deliverAssistantOutput("AI corrected words")
    }
    // A repeated completion must also leave the chosen final output intact.
    transcriber.testDeliverFinalSessionOutput()
    let afterAI = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(afterAI == (allowRawDelivery ? "raw batch words" : "AI corrected words"))
  }

  @Test("Leaving Voice To Text preserves pending AI delivery until final transcription arrives")
  func navigationKeepsPendingAIOutput() {
    let transcriber = VoiceTranscriber.shared
    let shortcuts = VoiceShortcutState.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    let previousAutoType = transcriber.autoTypeEnabled
    let session = TranscriptSession()
    defer {
      TranscriptHistoryStore.shared.remove(id: session.id)
      shortcuts.cancelSession()
      transcriber.deliverTranscriptsDirectly = true
      transcriber.autoTypeEnabled = previousAutoType
      transcriber.testResetAfterQwen3StreamAssertions()
    }
    shortcuts.activateMode(.dictation)
    transcriber.deliverTranscriptsDirectly = false
    VoiceToTextView(transcriber: transcriber).finishShortcutSessionOnDisappear()
    #expect(shortcuts.pendingEndMode == .dictation)
    #expect(transcriber.deliverTranscriptsDirectly == false)
    // Startup/finalization continues after SwiftUI runs the navigation callbacks.
    transcriber.testCaptureTranscriptDeliveryForSession()
    transcriber.autoTypeEnabled = false
    transcriber.testSetSession(session)
    transcriber.testApplyDictationBatchOutput(BatchTranscriptionOutput(
      result: TranscriptionResult(
        segments: [Segment(startTime: 0, endTime: 1, text: "raw batch words")],
        totalDuration: 1, processingTime: 0, modelUsed: ModelVariant.whisperTiny.rawValue
      ), speakerAnnotationApplied: false, sourceURLBookmark: nil
    ))
    shortcuts.absorbSessionTextOnce(sessionID: session.id, text: transcriber.session?.combinedText ?? "")
    shortcuts.finalizeEndSession()
    #expect(shortcuts.consumePendingResult()?.transcript == "raw batch words")
    let beforeAI = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(beforeAI == "")
    transcriber.deliverAssistantOutput("AI corrected words")
    let afterAI = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(afterAI == "AI corrected words")
  }

  @Test("VoiceTranscriber uses accuracy-first endpointing for live dictation")
  func voiceTranscriberUsesAccuracyFirstEndpointing() {
    let transcriber = VoiceTranscriber.shared

    #expect(transcriber.testStreamingChunkDuration == 0.5)
    #expect(transcriber.testStreamingSpeechWindowDuration == 2.5)
    #expect(transcriber.testStreamingRequiredSilentChunks == 3)
  }

  @Test("Mic overlay starts as soon as dictation enters startup states")
  func micOverlayStartsDuringStartup() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForOverlayStateAssertions()

    transcriber.testSetOverlayLifecycleState(.requestingPermission)

    #expect(transcriber.testOverlayIsActive == true)
    #expect(transcriber.testOverlayStatus == .listening)

    transcriber.testResetAfterOverlayStateAssertions()
  }

  @Test("Mic overlay dismisses when startup fails")
  func micOverlayDismissesOnStartupFailure() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForOverlayStateAssertions()

    transcriber.testSetOverlayLifecycleState(.preparing)
    #expect(transcriber.testOverlayIsActive == true)

    transcriber.testSetOverlayLifecycleState(.error(message: "Failed"))

    #expect(transcriber.testOverlayStatus == .idle)
    transcriber.testCompletePendingOverlayDismiss()
    #expect(transcriber.testOverlayIsActive == false)

    transcriber.testResetAfterOverlayStateAssertions()
  }

  @Test("Model warmup keeps startup in preparing state instead of failing immediately")
  func modelWarmupKeepsStartupPreparing() async {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForOverlayStateAssertions()
    transcriber.testSetOverlayLifecycleState(.preparing)

    let handled = await transcriber.testApplyWarmupWaitingStateIfNeeded(
      type: .parakeet,
      model: .parakeetV3,
      isModelLoadingOverride: true
    )

    #expect(handled == true)
    #expect(transcriber.state == .preparing)
    #expect(transcriber.statusMessage.contains("warming up"))
    #expect(transcriber.testOverlayIsActive == true)
    #expect(transcriber.testOverlayStatus == .listening)

    transcriber.testResetAfterOverlayStateAssertions()
  }

  @Test("Startup continuation aborts once preparing state has been cancelled")
  func startupContinuationAbortsWhenPreparingEnds() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForOverlayStateAssertions()
    transcriber.testSetOverlayLifecycleState(.idle)

    #expect(throws: CancellationError.self) {
      try transcriber.testThrowIfStartupNoLongerPreparing()
    }

    transcriber.testResetAfterOverlayStateAssertions()
  }

  @Test("Warmup completion cannot reactivate a cancelled dictation")
  func warmupDoesNotReactivateCancelledDictation() async {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForOverlayStateAssertions()
    defer { transcriber.testResetAfterOverlayStateAssertions() }
    let handled = await transcriber.testApplyWarmupWaitingStateIfNeeded(
      type: .parakeet, model: .parakeetV3, isModelLoadingOverride: true
    )
    #expect(!handled)
    #expect(transcriber.state == .idle)
    #expect(!transcriber.testOverlayIsActive)
  }

  @Test("AI enhance helper restores overlay after shortcut retranscription finishes")
  func aiEnhanceHelperRestoresOverlayAfterRetranscription() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForOverlayStateAssertions()

    transcriber.testSetOverlayLifecycleState(.stopping)
    transcriber.testSetOverlayLifecycleState(.idle)
    #expect(transcriber.testOverlayStatus == .idle)

    transcriber.testBeginAIEnhanceOverlay()

    #expect(transcriber.testOverlayIsActive == true)
    #expect(transcriber.testOverlayStatus == .aiEnhance)

    transcriber.testResetAfterOverlayStateAssertions()
  }

  @Test("Deferred recording backfill updates matching dictation session and history")
  func deferredRecordingBackfillUpdatesMatchingSessionAndHistory() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    TranscriptHistoryStore.shared.removeAll(source: .voiceDictation)

    let recordingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("wav")
    let sessionID = UUID()
    var session = TranscriptSession(
      id: sessionID,
      lines: [TranscriptLine(timestamp: 0, text: "hello world")],
      source: .voiceDictation
    )
    session.finish()
    transcriber.testSetSession(session)
    TranscriptHistoryStore.shared.add(session)

    transcriber.testBackfillDeferredRecording(url: recordingURL, for: sessionID)

    #expect(transcriber.session?.recordingURL == recordingURL)
    #expect(
      TranscriptHistoryStore.shared.recentDictationSessions.first(where: { $0.id == sessionID })?
        .recordingURL == recordingURL
    )

    TranscriptHistoryStore.shared.removeAll(source: .voiceDictation)
    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Deferred recording backfill does not overwrite a newer active session")
  func deferredRecordingBackfillDoesNotOverwriteNewerActiveSession() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    TranscriptHistoryStore.shared.removeAll(source: .voiceDictation)

    let oldSessionID = UUID()
    var oldSession = TranscriptSession(
      id: oldSessionID,
      lines: [TranscriptLine(timestamp: 0, text: "old")],
      source: .voiceDictation
    )
    oldSession.finish()
    TranscriptHistoryStore.shared.add(oldSession)

    let newerSessionID = UUID()
    var newerSession = TranscriptSession(
      id: newerSessionID,
      lines: [TranscriptLine(timestamp: 0, text: "new")],
      source: .voiceDictation
    )
    newerSession.finish()
    transcriber.testSetSession(newerSession)

    let recordingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("wav")

    transcriber.testBackfillDeferredRecording(url: recordingURL, for: oldSessionID)

    #expect(transcriber.session?.id == newerSessionID)
    #expect(transcriber.session?.recordingURL == nil)
    #expect(
      TranscriptHistoryStore.shared.recentDictationSessions.first(where: { $0.id == oldSessionID })?
        .recordingURL == recordingURL
    )

    TranscriptHistoryStore.shared.removeAll(source: .voiceDictation)
    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Normal stop with no microphone buffers reports missing input instead of silent success")
  func normalStopWithoutAudioReportsInputIssue() async {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.testSetSession(TranscriptSession())
    await transcriber.stop()
    #expect(transcriber.state == .idle)
    #expect(transcriber.inputIssue == .noInput)
    #expect(transcriber.statusMessage != "Ready")
    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Completed microphone errors can be dismissed and clear the page feedback")
  func dismissCompletedInputIssue() async {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    defer { transcriber.testResetAfterQwen3StreamAssertions() }
    transcriber.testSetSession(TranscriptSession())
    await transcriber.stop()
    #expect(transcriber.canDismissInputIssue)
    transcriber.dismissInputIssue()
    #expect(transcriber.inputIssue == nil)
    #expect(!transcriber.canDismissInputIssue)
    #expect(transcriber.state == .idle)
    #expect(!transcriber.testOverlayIsActive)
  }

  @Test("Acknowledging input feedback cannot stop a live dictation")
  func dismissInputIssueWhileRecording() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    defer { transcriber.testResetAfterQwen3StreamAssertions() }
    transcriber.testCheckMicrophoneInput(at: Date().addingTimeInterval(4))
    #expect(!transcriber.canDismissInputIssue)
    transcriber.dismissInputIssue()
    #expect(transcriber.inputIssue == .noInput)
    #expect(transcriber.state == .running)
  }

  @Test("Cancelling a recording does not report missing microphone input")
  func cancelledStopDoesNotReportInputIssue() async {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.testSetSession(TranscriptSession())
    await transcriber.stop(reason: .cancelled)
    #expect(transcriber.inputIssue == nil)
    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Escape tracks UI dictation through permission, preparation, and recording")
  func escapeTracksUIDictation() async throws {
    for state in [VoiceTranscriber.State.requestingPermission, .preparing, .running] {
      let transcriber = VoiceTranscriber.shared
      let manager = KeyboardShortcutManager.shared
      transcriber.testPrepareForQwen3StreamAssertions()
      let session = TranscriptSession()
      transcriber.testSetSession(session)
      transcriber.testHandleQwen3StreamUpdate("discard this preview")
      transcriber.testSetOverlayLifecycleState(state)
      let escape = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: 53
      ))
      defer {
        manager.unbindShortcuts()
        transcriber.testResetAfterQwen3StreamAssertions()
      }
      #expect(manager.activeMode == nil)
      // No modifier-key session exists: cancellation comes from transcriber state.
      #expect(manager.processSpaceFallback(escape))
      await transcriber.stop(reason: .cancelled)
      #expect(transcriber.state == .idle)
      #expect(!transcriber.isRetranscribing)
      #expect(transcriber.session?.combinedText.isEmpty == true)
      #expect(!TranscriptHistoryStore.shared.recentDictationSessions.contains { $0.id == session.id })
      let delivered = Mirror(reflecting: transcriber).children
        .first { $0.label == "deliveredText" }?.value as? String
      #expect(delivered == "")
      let release = try #require(NSEvent.keyEvent(
        with: .keyUp, location: .zero, modifierFlags: [], timestamp: 2,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: 53
      ))
      #expect(manager.processSpaceFallback(release))
      #expect(!manager.processSpaceFallback(escape))
    }
  }

  @Test("Live input feedback clears when microphone audio arrives")
  func inputFeedbackRecovers() {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.testCheckMicrophoneInput(at: Date().addingTimeInterval(4))
    #expect(transcriber.inputIssue == .noInput)
    transcriber.testHandleMicLevelUpdate(0.4)
    #expect(transcriber.inputIssue == nil)
    transcriber.testResetAfterQwen3StreamAssertions()
  }

  @Test("Normal stop preserves streaming text in history when finalization audio is unavailable")
  func normalStopKeepsStreamingFallback() async throws {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    let previousAutoType = transcriber.autoTypeEnabled
    transcriber.autoTypeEnabled = false
    transcriber.deliverTranscriptsDirectly = true
    let session = TranscriptSession()
    transcriber.testSetSession(session)
    defer {
      TranscriptHistoryStore.shared.remove(id: session.id)
      transcriber.autoTypeEnabled = previousAutoType
      transcriber.testResetAfterQwen3StreamAssertions()
    }
    transcriber.testHandleQwen3StreamUpdate("hello world")
    await transcriber.stop()
    #expect(transcriber.session?.combinedText == "hello world")
    #expect(transcriber.session?.endTime != nil)
    #expect(transcriber.inputIssue == nil)
    #expect(TranscriptHistoryStore.shared.sessions.contains { $0.id == session.id && $0.combinedText == "hello world" })
    let deliveredText = Mirror(reflecting: transcriber).children.first { $0.label == "deliveredText" }?.value as? String
    #expect(deliveredText == "hello world")
  }

  private func voiceTranscriberSource() throws -> String {
    try projectFileSource("Sources/Cliptate/Services/VoiceTranscriber.swift")
  }

  private func projectFileSource(_ relativePath: String) throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
