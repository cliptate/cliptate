import Foundation
import Testing

@testable import Cliptate

@Suite("VoiceTranscriber stop reason and retranscription state", .serialized)
@MainActor
struct VoiceTranscriberStopReasonTests {

  @Test("dictation delivery routes injection through AccessibilityGate with clipboard fallback")
  func accessibilityEnabledDeliveryAvoidsClipboardSourcePath() throws {
    let source = try voiceTranscriberSource()

    // Injection goes through the gate; clipboard + hint is the fallback path.
    #expect(source.contains("AccessibilityGate.injectText(text)"))
    #expect(source.contains("copyTextToClipboard(text)"))
    #expect(source.contains("micIndicator.flashCopiedToClipboard()"))
    // The raw keystroke synthesis must not live in the transcriber anymore.
    #expect(source.contains("keyboardSetUnicodeString") == false)

    // And the real typing implementation lives behind the gate.
    let gate = try accessibilityGateSource()
    #expect(gate.contains("keyboardSetUnicodeString"))
  }

  @Test("clipboard fallback avoids app activation and main-thread pasteboard writes")
  func clipboardFallbackAvoidsActivationAndMainThreadPasteboardWrites() throws {
    let source = try voiceTranscriberSource()

    let fallbackCheck = try #require(source.range(of: "AccessibilityGate.canInjectText")?.lowerBound)
    let appActivation = try #require(source.range(of: "targetApp.activate(options: [])")?.lowerBound)
    #expect(
      fallbackCheck < appActivation,
      "Clipboard fallback should be decided before activating the previous target app"
    )

    #expect(source.contains("Task.detached"))
    #expect(source.contains("await ClipboardWriter.write(text)"))
  }

  @Test("clipboard fallback logs avoid accessibility rejection wording")
  func clipboardFallbackLogsAvoidAccessibilityRejectionWording() throws {
    let source = try voiceTranscriberSource()

    #expect(source.contains("Accessibility unavailable") == false)
    #expect(source.contains("direct text injection failed") == false)
    #expect(source.contains("manual paste required"))
  }

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

  @Test("Cancelling a recording does not report missing microphone input")
  func cancelledStopDoesNotReportInputIssue() async {
    let transcriber = VoiceTranscriber.shared
    transcriber.testPrepareForQwen3StreamAssertions()
    transcriber.testSetSession(TranscriptSession())
    await transcriber.stop(reason: .cancelled)
    #expect(transcriber.inputIssue == nil)
    transcriber.testResetAfterQwen3StreamAssertions()
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

  private func accessibilityGateSource() throws -> String {
    try projectFileSource("Sources/Cliptate/Utilities/AccessibilityGate.swift")
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
