import CliptateCore
import Foundation

@MainActor
final class VoiceCompletionRuntime: ObservableObject {
  struct Settings {
    var apiKey: String?
    var enhancementEnabled = true
    var provider: AIProvider = .gemini
    var language: Language = .english
    var model = ""
    var endpoint: String?
    var dictionaryContext: String?
    var includeClipboard = false
    var includeWindow = false

    @MainActor static func capture(_ config: AppConfiguration, mode: VoiceShortcutMode) -> Self {
      let isDictation = mode == .dictation
      let modeEnabled = isDictation
        ? config.voiceToTextDictationAIEnhanceEnabled : config.voiceToTextAssistantAIEnhanceEnabled
      return Self(
        apiKey: config.aiProviderKeys[config.selectedAIProvider],
        enhancementEnabled: config.aiEnabled && modeEnabled,
        provider: config.selectedAIProvider,
        language: config.voiceToTextLanguage,
        model: config.aiModel(for: config.selectedAIProvider),
        endpoint: config.aiOpenAIEndpoint,
        dictionaryContext: config.dictionaryContextText,
        includeClipboard: isDictation ? config.aiIncludeClipboardContext : config.voiceToTextAssistantIncludeClipboardContext,
        includeWindow: isDictation ? config.aiIncludeWindowContext : config.voiceToTextAssistantIncludeWindowContext
      )
    }
  }

  static let shared = VoiceCompletionRuntime(
    shortcuts: .shared,
    deliver: { text, target in
      try await VoiceTranscriber.shared.deliverCompletionOutput(text, to: target)
    },
    onActivityChanged: { active in
      KeyboardShortcutManager.shared.setVoiceCompletionActive(active)
      VoiceTranscriber.shared.deliverTranscriptsDirectly = !active
      if !active {
        VoiceTranscriber.shared.cancelPendingDelivery()
        VoiceTranscriber.shared.dismissOverlay()
      }
    },
    history: .shared
  )

  @Published private(set) var isProcessing = false
  @Published private(set) var isActive = false {
    didSet { onActivityChanged(isActive) }
  }
  @Published private(set) var errorMessage: String?
  @Published private(set) var statusMessage: String?
  @Published private(set) var sourceText = ""
  @Published private(set) var mode: VoiceShortcutMode?

  var currentID: UUID? { isActive ? generation : nil }

  private let shortcuts: VoiceShortcutState
  private let deliver: (String, Int32?) async throws -> Void
  private let enhance: (String, VoiceShortcutMode, Settings) async throws -> String
  private let onActivityChanged: (Bool) -> Void
  private let history: HistoryRuntime?
  private var settings = Settings()
  private var target: Int32?
  private var generation = UUID()
  private var task: Task<Void, Never>?
  private var hasStartedRecording = false

  init(
    shortcuts: VoiceShortcutState? = nil,
    deliver: @escaping (String, Int32?) async throws -> Void,
    enhance: @escaping (String, VoiceShortcutMode, Settings) async throws -> String = VoiceCompletionRuntime.enhanceTranscript,
    onActivityChanged: @escaping (Bool) -> Void = { _ in },
    history: HistoryRuntime? = nil
  ) {
    self.shortcuts = shortcuts ?? VoiceShortcutState()
    self.deliver = deliver
    self.enhance = enhance
    self.onActivityChanged = onActivityChanged
    self.history = history
  }

  @discardableResult
  func begin(mode: VoiceShortcutMode, settings: Settings, target: Int32?) -> UUID {
    cancel()
    shortcuts.activateMode(mode)
    self.mode = mode
    self.settings = settings
    self.target = target
    sourceText = ""
    isActive = true
    return generation
  }

  func cancel(completionID: UUID? = nil) {
    guard completionID == nil || completionID == generation else { return }
    generation = UUID()
    task?.cancel()
    task = nil
    hasStartedRecording = false
    shortcuts.cancelSession()
    isProcessing = false
    errorMessage = nil
    statusMessage = nil
    isActive = false
  }

  /// Called before recording captures its delivery policy.
  func recordingWillStart() -> UUID? {
    guard isActive, shortcuts.activeMode != nil else {
      cancel()
      sourceText = ""
      mode = nil
      return nil
    }
    hasStartedRecording = true
    return generation
  }

  func requestEnd() {
    shortcuts.requestEndSession()
    guard isActive else { return }
    guard hasStartedRecording else {
      cancel()
      return
    }
    let id = generation
    Task {
      guard isActive, id == generation else { return }
      await completeIfReady()
    }
  }

  func receiveFinalTranscript(sessionID: UUID, text: String, completionID: UUID? = nil) async {
    guard isActive, completionID == nil || completionID == generation else { return }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      cancel()
      return
    }
    shortcuts.absorbSessionTextOnce(sessionID: sessionID, text: text)
    await completeIfReady()
  }

  private func completeIfReady() async {
    guard !isProcessing, shortcuts.activeMode == nil else { return }
    shortcuts.finalizeEndSession()
    guard let result = shortcuts.consumePendingResult() else { return }
    sourceText = result.transcript
    let generation = generation
    let settings = settings
    let target = target
    isProcessing = true
    if settings.enhancementEnabled {
      statusMessage = result.mode == .dictation
        ? String(localized: "Cleaning transcript with AI (\(result.transcript.count) characters)…")
        : String(localized: "Sending assistant request (\(result.transcript.count) characters + context)…")
    }
    let task = Task {
      await process(result, settings: settings, target: target, generation: generation)
    }
    self.task = task
    await task.value
  }

  private func process(
    _ result: VoiceShortcutState.SessionResult, settings: Settings, target: Int32?, generation: UUID
  ) async {
    defer {
      if generation == self.generation {
        isProcessing = false
        task = nil
        isActive = false
      }
    }
    var output: String?
    var enhanced = false
    if !settings.enhancementEnabled {
      output = result.transcript
    } else if let key = settings.apiKey, !key.isEmpty {
      do {
        output = try await enhance(result.transcript, result.mode, settings)
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw AICorrector.AIError.invalidResponse
        }
        enhanced = true
      } catch {
        guard generation == self.generation, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
        output = result.mode == .dictation ? result.transcript : nil
      }
    } else {
      errorMessage = String(localized: "No API key available for \(settings.provider.displayName).")
      output = result.mode == .dictation ? result.transcript : nil
    }
    guard generation == self.generation, !Task.isCancelled else { return }
    statusMessage = nil
    guard let output else { return }
    do {
      try await deliver(output, target)
      guard generation == self.generation, !Task.isCancelled else { return }
      if enhanced {
        statusMessage = result.mode == .dictation
          ? String(localized: "Transcript corrected and delivered via AI.")
          : String(localized: "Assistant response is ready.")
        if result.mode == .dictation {
          do {
            try history?.recordDictationCorrection(
              sessionIDs: result.sessionIDs, original: result.transcript, corrected: output,
              provider: settings.provider.rawValue, model: settings.model, language: settings.language.rawValue
            )
          } catch {
            errorMessage = String(format: String(localized:
              "AI text was applied, but correction history could not be saved: %@."), error.localizedDescription)
          }
        }
      }
    } catch {
      guard generation == self.generation, !Task.isCancelled else { return }
      errorMessage = error.localizedDescription
    }
  }

  private static func enhanceTranscript(
    _ transcript: String, mode: VoiceShortcutMode, settings: Settings
  ) async throws -> String {
    VoiceTranscriber.shared.beginAIEnhanceOverlay()
    let context: AssistantContextSnapshot
    if settings.includeClipboard || settings.includeWindow {
      context = await AssistantContextCollector.shared.collectContext()
    } else {
      context = AssistantContextSnapshot(clipboardText: nil, screenText: nil)
    }
    try Task.checkCancellation()
    let clipboard = settings.includeClipboard ? context.clipboardText : nil
    let window = settings.includeWindow ? context.screenText : nil
    let userPrompt: String
    let systemPrompt: String
    switch mode {
    case .dictation:
      userPrompt = AIPrompts.makeDictationUserPrompt(
        transcript: transcript, clipboardContext: clipboard, windowContext: window,
        dictionaryContext: settings.dictionaryContext
      )
      systemPrompt = String(format: AIPrompts.dictationSystemPrompt, AIPrompts.languageOutputRule(for: settings.language))
    case .assistant:
      userPrompt = AIPrompts.makeAssistantUserPrompt(
        transcript: transcript, clipboardContext: clipboard, windowContext: window,
        dictionaryContext: settings.dictionaryContext
      )
      systemPrompt = AIPrompts.assistantMode + "\n\n" + AIPrompts.assistantLanguageOutputRule(for: settings.language)
    }
    return try await AICorrector.askAssistant(
      prompt: userPrompt, provider: settings.provider, model: settings.model,
      systemPrompt: systemPrompt, apiKey: settings.apiKey ?? "", openAIBaseURL: settings.endpoint
    )
  }
}
