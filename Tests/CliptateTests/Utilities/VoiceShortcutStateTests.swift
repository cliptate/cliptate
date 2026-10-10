import Foundation
import Testing

@testable import Cliptate

@Suite("VoiceShortcutState")
@MainActor
struct VoiceShortcutStateTests {

  @Test("starts idle")
  func startsIdle() {
    let state = VoiceShortcutState()
    #expect(state.phase == .idle)
    #expect(state.activeMode == nil)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("activateMode sets ready phase")
  func activateSetsReady() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    #expect(state.phase == .ready)
    #expect(state.activeMode == .dictation)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("startRecording transitions from ready to recording")
  func startRecording() {
    let state = VoiceShortcutState()
    state.activateMode(.assistant)
    state.startRecording()
    #expect(state.phase == .recording)
    #expect(state.activeMode == .assistant)
  }

  @Test("stopRecording transitions from recording to ready")
  func stopRecording() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.stopRecording()
    #expect(state.phase == .ready)
  }

  @Test("appendSegmentText accumulates text")
  func appendSegmentText() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.appendSegmentText("Hello ")
    state.appendSegmentText("World")
    #expect(state.accumulatedTranscript == "Hello World")
  }

  @Test("endSession returns mode and transcript, resets to idle")
  func endSession() {
    let state = VoiceShortcutState()
    state.activateMode(.assistant)
    state.startRecording()
    state.appendSegmentText("Test transcript")
    state.stopRecording()
    let result = state.endSession()
    #expect(result?.mode == .assistant)
    #expect(result?.transcript == "Test transcript")
    #expect(state.phase == .idle)
    #expect(state.activeMode == nil)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("endSession returns nil when idle")
  func endSessionWhenIdle() {
    let state = VoiceShortcutState()
    #expect(state.endSession() == nil)
  }

  @Test("activateMode while in another mode cancels previous")
  func switchModeCancels() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.appendSegmentText("partial")
    state.activateMode(.assistant)
    #expect(state.activeMode == .assistant)
    #expect(state.phase == .ready)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("startRecording ignored when idle")
  func startRecordingWhenIdle() {
    let state = VoiceShortcutState()
    state.startRecording()
    #expect(state.phase == .idle)
  }

  @Test("stopRecording ignored when not recording")
  func stopRecordingWhenReady() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.stopRecording()
    #expect(state.phase == .ready)
  }

  @Test("pendingResult set by endSession, consumed by consumePendingResult")
  func pendingResultLifecycle() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.appendSegmentText("hello")
    let result = state.endSession()
    #expect(result?.mode == .dictation)
    #expect(result?.transcript == "hello")

    let pending = state.consumePendingResult()
    #expect(pending?.mode == .dictation)
    #expect(pending?.transcript == "hello")

    // Second consume returns nil
    #expect(state.consumePendingResult() == nil)
  }

  @Test("consumePendingResult returns nil when no session ended")
  func consumeWithoutEnd() {
    let state = VoiceShortcutState()
    #expect(state.consumePendingResult() == nil)
  }

  // MARK: - Two-phase session end (requestEndSession + finalizeEndSession)

  @Test("requestEndSession stores mode and clears activeMode without capturing transcript")
  func requestEndSessionStoresMode() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.appendSegmentText("partial")
    state.requestEndSession()

    // activeMode should be nil so processShortcut... can proceed
    #expect(state.activeMode == nil)
    #expect(state.phase == .idle)
    // pendingEndMode should remember the mode
    #expect(state.pendingEndMode == .dictation)
    // accumulatedTranscript should NOT be cleared yet
    #expect(state.accumulatedTranscript == "partial")
    // No pendingResult yet
    #expect(state.consumePendingResult() == nil)
  }

  @Test("finalizeEndSession creates result with current accumulated transcript")
  func finalizeEndSessionCreatesResult() {
    let state = VoiceShortcutState()
    state.activateMode(.assistant)
    state.startRecording()
    // Simulate: endSession called before transcriber delivers text
    state.requestEndSession()
    // Now text arrives (simulating processShortcut... appending)
    state.appendSegmentText("Hello world")
    // Finalize should create result with accumulated text
    state.finalizeEndSession()

    let pending = state.consumePendingResult()
    #expect(pending?.mode == .assistant)
    #expect(pending?.transcript == "Hello world")
    // Should be cleaned up
    #expect(state.pendingEndMode == nil)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("hold-to-record race: text arrives after requestEndSession")
  func holdToRecordRace() {
    let state = VoiceShortcutState()
    // 1. Mode activated, recording started
    state.activateMode(.dictation)
    state.startRecording()
    // 2. User releases key — requestEndSession called, transcriber still running
    state.stopRecording()
    state.requestEndSession()
    #expect(state.activeMode == nil)
    #expect(state.pendingEndMode == .dictation)
    #expect(state.accumulatedTranscript == "")
    // 3. Transcriber finishes — text arrives
    state.appendSegmentText("Transcribed speech")
    // 4. finalizeEndSession creates result with the text
    state.finalizeEndSession()

    let pending = state.consumePendingResult()
    #expect(pending?.mode == .dictation)
    #expect(pending?.transcript == "Transcribed speech")
  }

  @Test("multi-segment then requestEndSession preserves all segments")
  func multiSegmentRequestEnd() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    // Segment 1
    state.startRecording()
    state.appendSegmentText("Segment one. ")
    state.stopRecording()
    // Segment 2 starts, user deactivates while recording
    state.startRecording()
    state.requestEndSession()
    // Last segment text arrives after requestEndSession
    state.appendSegmentText("Segment two.")
    state.finalizeEndSession()

    let pending = state.consumePendingResult()
    #expect(pending?.mode == .dictation)
    #expect(pending?.transcript == "Segment one. Segment two.")
  }

  @Test("empty absorb does not block later retranscription text for same session")
  func emptyAbsorbDoesNotBlockLaterRetranscriptionText() {
    let state = VoiceShortcutState()
    let sessionID = UUID()

    state.activateMode(.dictation)
    state.requestEndSession()

    state.absorbSessionTextOnce(sessionID: sessionID, text: "")
    state.absorbSessionTextOnce(sessionID: sessionID, text: "Retranscribed text")
    state.finalizeEndSession()

    let pending = state.consumePendingResult()
    #expect(pending?.mode == .dictation)
    #expect(pending?.transcript == "Retranscribed text")
  }

  @Test("finalizeEndSession returns nil when no requestEndSession pending")
  func finalizeWithoutRequest() {
    let state = VoiceShortcutState()
    state.finalizeEndSession()
    #expect(state.consumePendingResult() == nil)
  }

  @Test("finalizeEndSession keeps pending mode when transcript is still empty")
  func finalizeWithoutTranscriptKeepsPendingMode() {
    let state = VoiceShortcutState()
    state.activateMode(.assistant)
    state.requestEndSession()

    let result = state.finalizeEndSession()

    #expect(result == nil)
    #expect(state.pendingEndMode == .assistant)
    #expect(state.consumePendingResult() == nil)
  }

  @Test("requestEndSession returns nil when idle")
  func requestEndSessionWhenIdle() {
    let state = VoiceShortcutState()
    state.requestEndSession()
    #expect(state.pendingEndMode == nil)
  }

  @Test("activateMode clears stale pendingEndMode")
  func activateModeClearsPendingEnd() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.requestEndSession()
    #expect(state.pendingEndMode == .dictation)
    // Re-activate should clear the stale pending end
    state.activateMode(.assistant)
    #expect(state.pendingEndMode == nil)
    #expect(state.activeMode == .assistant)
  }

  @Test("endSession clears pendingEndMode if present")
  func endSessionClearsPendingEnd() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.requestEndSession()
    #expect(state.pendingEndMode == .dictation)
    // A new session starts and ends with old API
    state.activateMode(.assistant)
    state.appendSegmentText("text")
    let result = state.endSession()
    #expect(result?.mode == .assistant)
    #expect(state.pendingEndMode == nil)
  }

  // MARK: - Cancel session (Escape)

  @Test("cancelSession resets to idle with no pending result and clears transcript")
  func cancelSessionClearsAll() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.appendSegmentText("Some partial text")
    state.stopRecording()
    state.cancelSession()

    #expect(state.activeMode == nil)
    #expect(state.phase == .idle)
    #expect(state.accumulatedTranscript == "")
    #expect(state.pendingEndMode == nil)
    #expect(state.pendingResult == nil)
    #expect(state.consumePendingResult() == nil)
  }

  @Test("cancelSession when idle does nothing")
  func cancelSessionWhenIdle() {
    let state = VoiceShortcutState()
    state.cancelSession()
    #expect(state.phase == .idle)
    #expect(state.consumePendingResult() == nil)
  }

  @Test("after cancelSession, processShortcutPostProcessing finds no text to deliver")
  func cancelSessionPreventsOutput() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.appendSegmentText("Hello world")
    state.cancelSession()

    // Simulate processShortcutPostProcessingIfNeeded flow:
    // activeMode is nil, pendingEndMode is nil → no finalizeEndSession
    #expect(state.pendingEndMode == nil)
    state.finalizeEndSession()
    // No pending result should exist
    #expect(state.consumePendingResult() == nil)
  }

  // MARK: - absorbSessionTextOnce dedup

  @Test("absorbSessionTextOnce deduplicates by session ID")
  func absorbSessionTextOnceDedup() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    let sessionID = UUID()

    state.absorbSessionTextOnce(sessionID: sessionID, text: "Hello")
    #expect(state.accumulatedTranscript == "Hello")

    // Second call with same session ID should not append
    state.absorbSessionTextOnce(sessionID: sessionID, text: "World")
    #expect(state.accumulatedTranscript == "Hello")
  }

  @Test("absorbSessionTextOnce skips whitespace-only text")
  func absorbSessionTextOnceWhitespace() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.absorbSessionTextOnce(sessionID: UUID(), text: "  \n  ")
    #expect(state.accumulatedTranscript == "")
  }

  @Test("absorbSessionTextOnce resets after activateMode")
  func absorbSessionTextOnceResetsOnActivate() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    let sessionID = UUID()
    state.absorbSessionTextOnce(sessionID: sessionID, text: "First")
    #expect(state.accumulatedTranscript == "First")

    // New session resets dedup
    state.activateMode(.assistant)
    state.absorbSessionTextOnce(sessionID: sessionID, text: "Second")
    #expect(state.accumulatedTranscript == "Second")
  }
}
