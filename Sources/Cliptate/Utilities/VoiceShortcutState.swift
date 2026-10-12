import Foundation

public enum VoiceShortcutMode: Sendable {
  case dictation
  case assistant
}

/// Tracks the lifecycle of voice shortcut sessions with mode selection and recording control.
@MainActor
final class VoiceShortcutState: ObservableObject {
  static let shared = VoiceShortcutState()

  enum SessionPhase {
    case idle
    case ready
    case recording
  }

  struct SessionResult {
    let mode: VoiceShortcutMode
    let transcript: String
    let sessionIDs: [UUID]
  }

  @Published private(set) var activeMode: VoiceShortcutMode?
  @Published private(set) var phase: SessionPhase = .idle
  private(set) var accumulatedTranscript: String = ""
  private(set) var pendingResult: SessionResult?
  /// Mode stored by requestEndSession(), awaiting finalizeEndSession() after text is available.
  private(set) var pendingEndMode: VoiceShortcutMode?
  /// Tracks the last transcriber session ID whose text was absorbed, preventing double-append.
  private var lastAbsorbedSessionID: UUID?
  private var absorbedSessionIDs: [UUID] = []

  init() {}

  func activateMode(_ mode: VoiceShortcutMode) {
    accumulatedTranscript = ""
    pendingResult = nil
    pendingEndMode = nil
    lastAbsorbedSessionID = nil
    absorbedSessionIDs = []
    activeMode = mode
    phase = .ready
  }

  func startRecording() {
    guard phase == .ready else { return }
    phase = .recording
  }

  func stopRecording() {
    guard phase == .recording else { return }
    phase = .ready
  }

  func appendSegmentText(_ text: String) {
    accumulatedTranscript += text
  }

  /// Absorb session text exactly once per transcriber session ID.
  /// Safe to call from multiple observers; only the first call per session appends.
  func absorbSessionTextOnce(sessionID: UUID?, text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let sessionID, sessionID != lastAbsorbedSessionID, !absorbedSessionIDs.contains(sessionID) else { return }
    lastAbsorbedSessionID = sessionID
    absorbedSessionIDs.append(sessionID)
    appendSegmentText(trimmed)
  }

  @discardableResult
  func endSession() -> SessionResult? {
    guard let mode = activeMode else { return nil }
    let transcript = accumulatedTranscript
    activeMode = nil
    phase = .idle
    accumulatedTranscript = ""
    pendingEndMode = nil
    let result = SessionResult(mode: mode, transcript: transcript, sessionIDs: absorbedSessionIDs)
    pendingResult = result
    absorbedSessionIDs = []
    return result
  }

  func consumePendingResult() -> SessionResult? {
    defer { pendingResult = nil }
    return pendingResult
  }

  /// Cancels the current session. Resets all state without creating a pending result.
  /// Used for Escape key — history is preserved by the transcriber, but no text is output.
  func cancelSession() {
    activeMode = nil
    phase = .idle
    accumulatedTranscript = ""
    pendingEndMode = nil
    pendingResult = nil
    absorbedSessionIDs = []
  }

  /// Phase 1: Mark the session as ending. Stores the mode but does NOT capture
  /// the transcript yet, allowing text to arrive from the transcriber.
  func requestEndSession() {
    guard let mode = activeMode else { return }
    pendingEndMode = mode
    activeMode = nil
    phase = .idle
  }

  /// Phase 2: Create the pending result with the current accumulated transcript.
  /// Call this after segment text has been appended.
  @discardableResult
  func finalizeEndSession() -> SessionResult? {
    guard let mode = pendingEndMode else { return nil }
    let transcript = accumulatedTranscript
    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    pendingEndMode = nil
    accumulatedTranscript = ""
    let result = SessionResult(mode: mode, transcript: transcript, sessionIDs: absorbedSessionIDs)
    pendingResult = result
    absorbedSessionIDs = []
    return result
  }
}
