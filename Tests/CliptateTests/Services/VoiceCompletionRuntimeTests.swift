import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("Voice completion")
@MainActor
struct VoiceCompletionRuntimeTests {
  @Test("an empty AI answer follows the same fallback policy as a failed request", arguments: [VoiceShortcutMode.dictation, .assistant])
  func emptyAnswer(mode: VoiceShortcutMode) async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(
      deliver: { text, _ in delivered.append(text) }, enhance: { _, _, _ in "  " }
    )
    runtime.begin(mode: mode, settings: .init(apiKey: "key"), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "original words")

    #expect(delivered == (mode == .dictation ? ["original words"] : []))
    #expect(runtime.errorMessage != nil)
  }

  @Test("releasing a shortcut before recording starts leaves no pending completion")
  func tapWithoutRecording() {
    let runtime = VoiceCompletionRuntime(deliver: { _, _ in })
    runtime.begin(mode: .dictation, settings: .init(apiKey: nil), target: 42)
    runtime.requestEnd()

    #expect(!runtime.isActive)
    #expect(!runtime.isProcessing)
    #expect(runtime.sourceText.isEmpty)
  }

  @Test("an empty final transcript finishes without leaving completion active")
  func emptyFinalTranscript() async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(deliver: { text, _ in delivered.append(text) })
    runtime.begin(mode: .dictation, settings: .init(apiKey: nil), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "  ")

    #expect(!runtime.isActive)
    #expect(delivered.isEmpty)
    #expect(runtime.errorMessage == nil)
  }

  @Test("Escape invalidates completion while it is waiting for its final transcript")
  func escapeWhileWaiting() async throws {
    let keyboard = KeyboardShortcutManager()
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(
      deliver: { text, _ in delivered.append(text) },
      onActivityChanged: { keyboard.setVoiceCompletionActive($0) }
    )
    keyboard.bindShortcuts { event in
      if event.phase == .escapePressed { runtime.cancel() }
    }
    defer { keyboard.unbindShortcuts() }
    let id = runtime.begin(mode: .dictation, settings: .init(apiKey: nil), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    keyboard.setDictationActive(false)
    #expect(keyboard.processEscapeKey(isKeyDown: true, isRepeat: false))
    try await Task.sleep(for: .milliseconds(10))
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "late transcript", completionID: id)

    #expect(!runtime.isActive)
    #expect(delivered.isEmpty)
  }

  @Test("completion uses the provider and language captured when its session began")
  func capturedSettings() async {
    let config = AppConfiguration()
    config.aiEnabled = true
    config.selectedAIProvider = .openai
    config.aiProviderKeys[.openai] = "original key"
    config.voiceToTextLanguage = .english
    var requested: [String] = []
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(
      deliver: { text, _ in delivered.append(text) },
      enhance: { _, _, settings in
        requested = [settings.provider.rawValue, settings.apiKey ?? "", settings.language.rawValue]
        return "corrected words"
      }
    )
    runtime.begin(mode: .dictation, settings: .capture(config, mode: .dictation), target: 42)
    _ = runtime.recordingWillStart()
    config.selectedAIProvider = .gemini
    config.voiceToTextLanguage = .chinese
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "original words")

    #expect(requested == ["OpenAI", "original key", Language.english.rawValue])
    #expect(delivered == ["corrected words"])
    #expect(runtime.errorMessage == nil)
  }

  @Test("a final transcript from an older recording cannot complete the replacement session")
  func staleTranscript() async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(deliver: { text, _ in delivered.append(text) })
    let oldID = runtime.begin(mode: .dictation, settings: .init(apiKey: nil, enhancementEnabled: false), target: 42)
    _ = runtime.recordingWillStart()
    runtime.begin(mode: .dictation, settings: .init(apiKey: nil, enhancementEnabled: false), target: 84)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "old transcript", completionID: oldID)

    #expect(delivered.isEmpty)
    #expect(runtime.sourceText.isEmpty)
  }

  @Test("disabled enhancement delivers the original without a missing-key error", arguments: [VoiceShortcutMode.dictation, .assistant])
  func disabledEnhancement(mode: VoiceShortcutMode) async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(deliver: { text, _ in delivered.append(text) })
    runtime.begin(mode: mode, settings: .init(apiKey: nil, enhancementEnabled: false), target: nil)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "original words")

    #expect(delivered == ["original words"])
    #expect(runtime.errorMessage == nil)
  }

  @Test("a new session replaces pending AI work and keeps its own target")
  func replacementSession() async {
    let gate = CompletionResponseGate()
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(
      deliver: { text, target in delivered.append("\(target ?? 0):\(text)") },
      enhance: { text, _, _ in text == "old" ? await gate.response() : "new answer" }
    )
    runtime.begin(mode: .dictation, settings: .init(apiKey: "old key"), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    let old = Task { await runtime.receiveFinalTranscript(sessionID: UUID(), text: "old") }
    await gate.waitUntilRequested()
    runtime.begin(mode: .assistant, settings: .init(apiKey: "new key"), target: 84)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "new")
    gate.resolve("old answer")
    await old.value

    #expect(delivered == ["84:new answer"])
    #expect(runtime.sourceText == "new")
    #expect(runtime.errorMessage == nil)
  }

  @Test("cancelled completion ignores an AI response that arrives afterwards")
  func cancelledResponse() async {
    let gate = CompletionResponseGate()
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(
      deliver: { text, _ in delivered.append(text) },
      enhance: { _, _, _ in await gate.response() }
    )
    runtime.begin(mode: .dictation, settings: .init(apiKey: "key"), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    let completion = Task {
      await runtime.receiveFinalTranscript(sessionID: UUID(), text: "original words")
    }
    await gate.waitUntilRequested()
    runtime.cancel()
    gate.resolve("late response")
    await completion.value

    #expect(delivered.isEmpty)
    #expect(runtime.errorMessage == nil)
    #expect(!runtime.isProcessing)
  }

  @Test("AI request failures follow the session mode's fallback policy", arguments: [VoiceShortcutMode.dictation, .assistant])
  func failedRequest(mode: VoiceShortcutMode) async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(
      deliver: { text, _ in delivered.append(text) },
      enhance: { _, _, _ in
        throw NSError(domain: "AI", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI request failed"])
      }
    )
    runtime.begin(mode: mode, settings: .init(apiKey: "key"), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "original words")

    #expect(delivered == (mode == .dictation ? ["original words"] : []))
    #expect(runtime.errorMessage == "AI request failed")
    #expect(runtime.sourceText == "original words")
  }

  @Test("assistant without an AI key retains the original without delivering it")
  func missingAssistantKey() async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(deliver: { text, _ in delivered.append(text) })
    runtime.begin(mode: .assistant, settings: .init(apiKey: nil), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "rewrite this paragraph")

    #expect(delivered.isEmpty)
    #expect(runtime.errorMessage != nil)
    #expect(runtime.sourceText == "rewrite this paragraph")
  }

  @Test("dictation without an AI key delivers the original and retains an error")
  func missingDictationKey() async {
    var delivered: [String] = []
    let runtime = VoiceCompletionRuntime(deliver: { text, _ in delivered.append(text) })
    runtime.begin(mode: .dictation, settings: .init(apiKey: nil), target: 42)
    _ = runtime.recordingWillStart()
    runtime.requestEnd()
    await runtime.receiveFinalTranscript(sessionID: UUID(), text: "original words")

    #expect(delivered == ["original words"])
    #expect(runtime.errorMessage != nil)
    #expect(runtime.sourceText == "original words")
    #expect(!runtime.isProcessing)
  }
}

@MainActor
private final class CompletionResponseGate {
  private var pending: CheckedContinuation<String, Never>?
  private var requested: CheckedContinuation<Void, Never>?

  func response() async -> String {
    await withCheckedContinuation { continuation in
      pending = continuation
      requested?.resume()
      requested = nil
    }
  }

  func waitUntilRequested() async {
    if pending != nil { return }
    await withCheckedContinuation { requested = $0 }
  }

  func resolve(_ text: String) {
    pending?.resume(returning: text)
    pending = nil
  }
}
