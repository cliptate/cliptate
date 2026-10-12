import AVFoundation
import AppKit
import CoreAudio
import CoreGraphics
import Foundation

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif
import os.log

#if canImport(os.signpost)
  import os.signpost
#endif

#if DEBUG
  @MainActor fileprivate var voiceTranscriberTestDisablesMicIndicator = false
#endif

@MainActor
public final class VoiceTranscriber: ObservableObject {
  public static let shared = VoiceTranscriber()

  public enum State: Equatable {
    case idle
    case requestingPermission
    case preparing
    case running
    case stopping
    case error(message: String)
  }

  /// Reason the recording was stopped.
  public enum StopReason: Equatable, Sendable {
    /// Normal stop — re-transcribe the full audio for accuracy, then deliver.
    case normal
    /// Cancelled (e.g. Esc) — no re-transcription, no output, and no deferred recording persistence.
    case cancelled
  }

  public enum MicrophoneStatus: Equatable {
    case unknown
    case restricted
    case denied
    case granted
  }

  @Published public private(set) var state: State = .idle {
    didSet { updateMicIndicator(for: state) }
  }
  @Published public private(set) var session: TranscriptSession?
  @Published public private(set) var liveText: String = ""
  @Published public private(set) var statusMessage: String = ""
  @Published public private(set) var microphoneStatus: MicrophoneStatus = .unknown
  @Published public var autoTypeEnabled: Bool = true
  @Published public private(set) var isModelWarming: Bool = false
  /// Whether a batch re-transcription of the finalized dictation capture is in progress.
  @Published public private(set) var isRetranscribing: Bool = false
  /// Status message shown during re-transcription (e.g. "Transcribing…").
  @Published public private(set) var retranscriptionStatus: String?
  /// Default for the next recording. An active session retains its own choice
  /// while view lifecycle and finish observers restore defaults for future runs.
  public var deliverTranscriptsDirectly: Bool = true
  @Published private(set) var inputIssue: VoiceInputIssue?
  @Published private(set) var inputDeviceName: String?
  private var inputMonitor = MicrophoneInputMonitor()

  private let audioEngine = AVAudioEngine()
  private var activeStreamingProvider: (any StreamingTranscriptionProvider)?
  private var sessionStartDate: Date?
  private var lastSpeechDetection: Date?
  private var silenceMonitorTimer: Timer?
  private var isStopInProgress = false
  private let logger = Logger(subsystem: "com.Cliptate", category: "VoiceTranscriber")
  private var currentType: TranscriberType = .parakeet
  private var currentModel: ModelVariant = .parakeetV3
  private var currentLanguage: Language = .english
  private var currentVADModel: ModelVariant = .sileroVAD
  private var currentDictionaryEntries: [String] = []
  private var sessionAllowsRawDelivery: Bool?
  private var activeASRLease: ASRModelLease?
  private var deliveredText: String = ""
  private var lastTranscriptText: String = ""
  private let micIndicator = MicIndicatorOverlay()
  private var lastExternalFrontmostApp: NSRunningApplication?
  private var currentRecordingURL: URL?
  private let batchTranscriptionRuntime = BatchTranscriptionRuntime.shared
  private let historyRuntime = HistoryRuntime.shared

  private lazy var streamingModule: StreamingAudioCaptureModule = {
    let configuration = StreamingAudioCaptureModule.Configuration(
      chunkDuration: 0.5,
      maxSpeechWindowDuration: 2.5,
      requiredConsecutiveSilentChunks: 3,
      levelCalculator: micRMSLevel
    )
    let callbacks = StreamingAudioCaptureModule.Callbacks(
      onAudioLevel: { [weak self] level in
        self?.handleMicLevelUpdate(level)
      },
      onInterimText: { [weak self] text in
        self?.handleStreamUpdate(text)
      }
    )
    return StreamingAudioCaptureModule(
      audioEngine: audioEngine,
      logger: logger,
      configuration: configuration,
      callbacks: callbacks
    )
  }()

  private init() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleApplicationDidResignActive),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleApplicationDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  #if canImport(os.signpost)
    private let signposter = OSSignposter(
      logger: Logger(subsystem: "com.Cliptate", category: "Performance")
    )
    private var transcriptionInterval: OSSignpostIntervalState?
  #endif

  // MARK: - Lifecycle

  /// Requests microphone permission if needed and starts streaming audio to the selected engine.
  public func start(
    type: TranscriberType,
    model: ModelVariant,
    language: Language
  ) async {
    logger.notice("🎙️ Requested start for engine: \(type.rawValue) model: \(model.rawValue)")

    await waitForStopCompletionIfNeeded()
    if Task.isCancelled { return }

    guard state != .running && state != .preparing else {
      logger.debug("Ignoring start request while already running")
      return
    }

    captureTranscriptDeliveryForSession()
    inputIssue = nil
    inputDeviceName = Self.defaultInputDeviceName()
    micIndicator.updateInputWarning(nil)
    state = .requestingPermission
    statusMessage = "Checking microphone permissions..."

    guard await ensureMicrophoneAccess() else {
      state = .error(message: "Microphone access denied. Please enable it in System Settings.")
      return
    }

    state = .preparing
    statusMessage = "Preparing transcription session..."

    do {
      currentType = type
      currentModel = model
      currentLanguage = language
      currentVADModel = AppConfiguration.shared.vadModelVariant
      currentDictionaryEntries = AppConfiguration.shared.voiceToTextCustomDictionary
      lastTranscriptText = ""
      streamingModule.reset()
      recordExternalFrontmostApplicationSnapshot()
      currentRecordingURL = nil

      try await prepareAudioSession()
      try await startRecordingSession()
      try throwIfStartupNoLongerPreparing()

      _ = await applyWarmupWaitingStateIfNeeded(type: type, model: model)

      try await configureEngine(type: type, model: model, language: language)
      try throwIfStartupNoLongerPreparing()

      sessionStartDate = Date()
      inputMonitor.start(at: sessionStartDate ?? Date())
      let startDate = sessionStartDate ?? Date()
      session = TranscriptSession(
        startTime: startDate,
        recordingURL: currentRecordingURL,
        transcriberType: type,
        modelVariant: model,
        language: language
      )
      liveText = ""
      deliveredText = ""
      micIndicator.updateTranscript(nil)

      state = .running
      statusMessage = "Listening..."
      lastSpeechDetection = Date()
      logger.notice("🎙️ Live transcription starting")
      #if canImport(os.signpost)
        transcriptionInterval = signposter.beginInterval("LiveTranscription")
      #endif

      try await startTranscriptionPipeline(type: type, model: model, language: language)
      inputMonitor.start(at: Date())
      startSilenceMonitor()

      logger.notice("🎙️ Live transcription pipeline active")

    } catch is CancellationError {
      await stop(reason: .cancelled)
      logger.notice("🎙️ Startup cancelled before transcription became active")
    } catch {
      await stop(resetState: false)
      state = .error(message: error.localizedDescription)
      statusMessage = "Failed to start transcription"
      logger.error("🎙️ Failed to start transcription: \(error.localizedDescription)")
    }
  }

  private func captureTranscriptDeliveryForSession() {
    sessionAllowsRawDelivery = deliverTranscriptsDirectly
  }

  private var shouldDeliverRawTranscript: Bool {
    sessionAllowsRawDelivery ?? deliverTranscriptsDirectly
  }

  /// Stops streaming audio and finalizes the session if one is active.
  public func stop(reason: StopReason = .normal, resetState: Bool = true) async {
    if isStopInProgress {
      logger.debug("🎙️ Stop already in progress, awaiting completion")
      repeat {
        try? await Task.sleep(nanoseconds: 50_000_000)
        if Task.isCancelled { return }
      } while isStopInProgress
      if resetState {
        state = .idle
        statusMessage = inputIssue?.message ?? String(localized: "Ready")
      }
      return
    }

    guard state == .running || state == .preparing else {
      if let activeASRLease {
        await ModelCacheManager.shared.releaseASRLease(activeASRLease)
        self.activeASRLease = nil
      }
      if resetState {
        state = .idle
        statusMessage = inputIssue?.message ?? String(localized: "Ready")
      }
      return
    }

    isStopInProgress = true
    defer { isStopInProgress = false }

    inputIssue = nil
    micIndicator.updateInputWarning(nil)
    state = .stopping
    statusMessage = "Stopping transcription..."
    stopSilenceMonitor()

    // Streaming results are display-only; never auto-deliver on stop.
    // For .normal, a batch re-transcription will deliver the final result.
    // For .cancelled, no output is delivered at all.
    do {
      if let finalText = try await activeStreamingProvider?.stop() {
        let collapsed = collapseWhitespace(finalText)
        logger.debug("🎙️ Streaming final text received from \(self.currentType.rawValue)")
        handleTranscriptionUpdate(
          collapsed,
          isFinal: true,
          allowAutoDelivery: false,
          updateSession: false
        )
      }
    } catch {
      logger.error("🎙️ Failed to finalize streaming: \(error.localizedDescription)")
    }

    let finalizedCapture = streamingModule.takeFinalizedDictationCapture()

    finalizeTranscriptAfterStopIfNeeded(suppressDelivery: true)

    await stopRecordingSession(shouldKeep: currentRecordingURL != nil)

    if var currentSession = session {
      currentSession.recordingURL = currentRecordingURL
      currentSession.finish()
      session = currentSession
    }

    #if canImport(os.signpost)
      if let interval = transcriptionInterval {
        signposter.endInterval("LiveTranscription", interval)
        transcriptionInterval = nil
      }
    #endif

    // Streaming results are display-only — do NOT save to history here.
    // For .normal, batch finalization will save the accurate result.
    // For .cancelled, no history entry is created.

    let recordingURLForRetranscription = session?.recordingURL

    currentRecordingURL = nil
    if let activeASRLease {
      await ModelCacheManager.shared.releaseASRLease(activeASRLease)
      self.activeASRLease = nil
    }

    // For normal stop, trigger batch re-transcription for higher accuracy.
    // For cancelled (Esc), no output is delivered — done.
    if resetState, reason == .normal {
      if let finalizedCapture, let sessionID = session?.id {
        await retranscribeCapturedAudio(finalizedCapture, sessionID: sessionID)
      } else if let audioURL = recordingURLForRetranscription {
        await retranscribeRecordedAudio(at: audioURL)
      } else if !finalizeStreamingFallback() {
        inputIssue = .noInput
      }
    }

    if resetState {
      await MainActor.run {
        state = .idle
        statusMessage = inputIssue?.message ?? String(localized: "Ready")
      }
    }
  }

  /// Convenience helper to toggle start/stop behaviour.
  public func toggle(
    type: TranscriberType,
    model: ModelVariant,
    language: Language
  ) async {
    switch state {
    case .running, .preparing:
      await stop()
    case .idle, .error, .requestingPermission:
      await start(type: type, model: model, language: language)
    case .stopping:
      break
    }
  }

  // MARK: - Batch Re-transcription

  private func retranscribeCapturedAudio(
    _ capture: StreamingAudioCaptureModule.FinalizedDictationCapture,
    sessionID: UUID
  ) async {
    isRetranscribing = true
    retranscriptionStatus = String(localized: "Transcribing…", comment: "Voice re-transcription: in progress")
    statusMessage = String(localized: "Transcribing for accuracy…", comment: "Voice re-transcription: status message")
    micIndicator.updateStatus(.transcribing)

    do {
      let output = try await batchTranscriptionRuntime.transcribe(
        request: BatchTranscriptionSamplesRequest(
          audioSamples: capture.samples,
          totalDuration: capture.duration,
          workflow: .dictationFinalization,
          transcriberType: currentType,
          asrModel: currentModel,
          vadModel: currentVADModel,
          alignModel: AppConfiguration.shared.alignModelVariant,
          language: currentLanguage,
          dictionaryEntries: currentDictionaryEntries
        ),
        modelProgressHandler: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.retranscriptionStatus = progress.currentStep
          }
        },
        progressHandler: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.retranscriptionStatus = progress.statusMessage
          }
        }
      )

      if let finalizedSessionID = applyDictationBatchOutput(output, recordingURL: nil) {
        persistDeferredRecording(capture, for: finalizedSessionID)
      } else if finalizeStreamingFallback() {
        if let sessionID = session?.id { persistDeferredRecording(capture, for: sessionID) }
      } else {
        inputIssue = inputMonitor.lastAudibleAt == nil ? .quietInput : .noSpeechRecognized
      }
    } catch {
      logger.error("🎙️ Re-transcription failed: \(error.localizedDescription)")
      if finalizeStreamingFallback(), let sessionID = session?.id {
        persistDeferredRecording(capture, for: sessionID)
      }
      inputIssue = .transcriptionFailed
    }

    isRetranscribing = false
    retranscriptionStatus = nil
    statusMessage = "Ready"
  }

  /// Re-transcribes the recorded audio file using the batch API for higher accuracy.
  /// Updates the session, saves to history, and delivers the result to the input field.
  private func retranscribeRecordedAudio(at audioURL: URL) async {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      logger.warning("🎙️ Recording file not found for re-transcription: \(audioURL.path)")
      _ = finalizeStreamingFallback()
      inputIssue = .transcriptionFailed
      return
    }

    isRetranscribing = true
    retranscriptionStatus = String(localized: "Transcribing…", comment: "Voice re-transcription: in progress")
    statusMessage = String(localized: "Transcribing for accuracy…", comment: "Voice re-transcription: status message")
    micIndicator.updateStatus(.transcribing)

    do {
      let output = try await batchTranscriptionRuntime.transcribe(
        request: BatchTranscriptionRequest(
          sourceURL: audioURL,
          workflow: .dictationFinalization,
          transcriberType: currentType,
          asrModel: currentModel,
          vadModel: currentVADModel,
          alignModel: AppConfiguration.shared.alignModelVariant,
          language: currentLanguage,
          dictionaryEntries: currentDictionaryEntries
        ),
        modelProgressHandler: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.retranscriptionStatus = progress.currentStep
          }
        },
        progressHandler: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.retranscriptionStatus = progress.statusMessage
          }
        }
      )

      if applyDictationBatchOutput(output, recordingURL: audioURL) == nil,
        !finalizeStreamingFallback(recordingURL: audioURL)
      {
        inputIssue = inputMonitor.lastAudibleAt == nil ? .quietInput : .noSpeechRecognized
      }
    } catch {
      logger.error("🎙️ Re-transcription failed: \(error.localizedDescription)")
      _ = finalizeStreamingFallback(recordingURL: audioURL)
      inputIssue = .transcriptionFailed
    }

    isRetranscribing = false
    retranscriptionStatus = nil
    statusMessage = "Ready"
  }

  @discardableResult
  private func applyDictationBatchOutput(
    _ output: BatchTranscriptionOutput,
    recordingURL: URL?
  ) -> UUID? {
    let newLines: [TranscriptLine] = output.result.segments.compactMap { segment in
      let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return TranscriptLine(timestamp: max(0, segment.startTime), text: trimmed, speakerId: segment.speakerId)
    }

    guard !newLines.isEmpty, var updatedSession = session else { return nil }
    updatedSession.replaceLines(with: newLines)
    if let recordingURL {
      updatedSession.recordingURL = recordingURL
    }
    session = updatedSession

    let combinedText = updatedSession.combinedText
    liveText = combinedText

    if shouldDeliverRawTranscript {
      deliverTranscriptionOutput(collapseWhitespace(combinedText))
    }

    var historySession = updatedSession
    historySession.source = .voiceDictation
    historyRuntime.add(historySession)

    logger.notice("🎙️ Re-transcription complete, \(newLines.count) lines")
    return updatedSession.id
  }

  @discardableResult
  private func finalizeStreamingFallback(recordingURL: URL? = nil) -> Bool {
    guard var currentSession = session else { return false }
    let text = collapseWhitespace(currentSession.combinedText.isEmpty ? liveText : currentSession.combinedText)
    guard !text.isEmpty else { return false }
    if currentSession.lines.isEmpty {
      currentSession.replaceLines(with: [TranscriptLine(timestamp: 0, text: text)])
    }
    if let recordingURL { currentSession.recordingURL = recordingURL }
    if currentSession.endTime == nil { currentSession.finish() }
    currentSession.source = .voiceDictation
    session = currentSession
    historyRuntime.add(currentSession)
    deliverFinalSessionOutput()
    return true
  }

  /// Clears the current session content but keeps the voice transcriber idle.
  public func clearSession() {
    guard state != .running else { return }
    inputIssue = nil
    micIndicator.updateInputWarning(nil)
    session = TranscriptSession()
    liveText = ""
    statusMessage = "Ready"
    lastTranscriptText = ""
    deliveredText = ""
    sessionAllowsRawDelivery = nil
    currentRecordingURL = nil
    isRetranscribing = false
    retranscriptionStatus = nil
    micIndicator.updateTranscript(nil)
  }

  /// Refreshes the microphone authorization state without prompting.
  public func refreshMicrophoneStatus() async {
    let status = await resolveMicrophoneStatus()
    await MainActor.run {
      microphoneStatus = status
    }
  }

  // MARK: - Private Helpers

  private func waitForStopCompletionIfNeeded() async {
    guard isStopInProgress else { return }
    logger.debug("🎙️ Waiting for previous stop to finish before starting")
    var didUpdateStatus = false
    repeat {
      if !didUpdateStatus {
        statusMessage = "Finishing previous session..."
        didUpdateStatus = true
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
      if Task.isCancelled { return }
    } while isStopInProgress
  }

  private func prepareAudioSession() async throws {
    #if !os(macOS)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, options: [.mixWithOthers, .allowBluetooth])
      try session.setMode(.measurement)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    #endif
  }

  private func configureEngine(
    type: TranscriberType,
    model: ModelVariant,
    language: Language
  ) async throws {
    if let activeASRLease {
      await ModelCacheManager.shared.releaseASRLease(activeASRLease)
      self.activeASRLease = nil
    }

    let (transcriber, lease) = try await ModelCacheManager.shared.acquireASRTranscriber(
      type: type,
      model: model,
      progress: { _ in }
    )
    activeASRLease = lease

    activeStreamingProvider = try TranscriptionPipelineFactory.makeStreamingProvider(
      type: type,
      transcriber: transcriber,
      streamingModule: streamingModule,
      vadModel: currentVADModel
    )
  }

  private func throwIfStartupNoLongerPreparing() throws {
    guard state == .preparing else {
      throw CancellationError()
    }
  }

  @discardableResult
  private func applyWarmupWaitingStateIfNeeded(
    type: TranscriberType,
    model: ModelVariant,
    isModelLoadingOverride: Bool? = nil
  ) async -> Bool {
    let isModelLoading: Bool
    if let isModelLoadingOverride {
      isModelLoading = isModelLoadingOverride
    } else {
      isModelLoading = await ModelCacheManager.shared.isModelLoading(type: type, model: model)
    }

    guard isModelLoading else { return false }

    state = .preparing
    statusMessage = String(
      format: String(
        localized: "%@ model is warming up. Starting transcription as soon as it's ready...",
        comment:
          "Voice transcription startup status while waiting for the selected model to finish warming"
      ),
      type.displayName
    )
    return true
  }

  private func startTranscriptionPipeline(
    type: TranscriberType,
    model: ModelVariant,
    language: Language
  ) async throws {
    if let provider = activeStreamingProvider {
      let dictionaryContext = ASRDictionaryBiasService.dictionaryContext(
        from: currentDictionaryEntries
      )
      try await provider.start(language: language, dictionaryContext: dictionaryContext)
      return
    }
  }

  private static func defaultInputDeviceName() -> String? {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
      device != kAudioObjectUnknown else { return nil }
    var name: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    address.mSelector = kAudioObjectPropertyName
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
    return name?.takeRetainedValue() as String?
  }

  private func checkMicrophoneInput(at date: Date) {
    guard state == .running else { return }
    let previousIssue = inputIssue
    inputIssue = inputMonitor.issue(at: date)
    micIndicator.updateInputWarning(inputIssue?.title)
    if previousIssue != inputIssue, inputIssue != nil {
      inputDeviceName = Self.defaultInputDeviceName()
    }
    if let inputIssue {
      statusMessage = inputIssue.message
    } else if previousIssue != nil {
      statusMessage = String(localized: "Listening...")
    }
  }

  private func handleMicLevelUpdate(_ level: CGFloat) {
    guard state == .running else { return }
    inputMonitor.receive(level: level, at: Date())
    checkMicrophoneInput(at: Date())
    micIndicator.updateLevel(level)
  }

  private func updateMicIndicator(for state: State) {
#if DEBUG
    guard !voiceTranscriberTestDisablesMicIndicator else { return }
#endif
    switch state {
    case .requestingPermission, .preparing:
      micIndicator.startTracking()
    case .running:
      micIndicator.startTracking()
      micIndicator.updateStatus(.listening)
    case .stopping:
      micIndicator.startTracking()
      micIndicator.updateStatus(.transcribing)
    case .idle, .error:
      if let inputIssue {
        micIndicator.showInputWarning(inputIssue.title)
      } else {
        micIndicator.forceFinishAndDismiss()
      }
    }
  }

  // MARK: - Overlay Lifecycle

  /// Update the floating overlay status (e.g., during post-processing).
  func updateOverlayStatus(_ status: OverlayStatus) {
    micIndicator.updateStatus(status)
  }

  /// Restore the overlay into AI Enhance state when a follow-up post-processing
  /// phase takes over after the transcription pipeline has already gone idle.
  func beginAIEnhanceOverlay() {
    micIndicator.startTracking()
    micIndicator.updateStatus(.aiEnhance)
  }

  /// Dismiss the overlay after a brief delay.
  /// Uses force-dismiss so it works even when AI enhance has entered processing state.
  func dismissOverlay() {
    guard inputIssue == nil else { return }
    micIndicator.forceFinishAndDismiss()
  }

  private func handleStreamUpdate(_ text: String) {
    guard state == .running else { return }
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let biased = ASRDictionaryBiasService.apply(
      to: normalized,
      dictionaryEntries: AppConfiguration.shared.voiceToTextCustomDictionary
    )
    guard !biased.isEmpty, biased != lastTranscriptText else { return }
    lastTranscriptText = biased
    liveText = biased
    recordSpeechActivity()
    deliverTranscript(biased, isFinal: false, updateSession: false)
  }

  private func recordSpeechActivity() {
    lastSpeechDetection = Date()
    statusMessage = "Recognizing..."
  }

  private func deliverTranscript(_ text: String, isFinal: Bool, updateSession: Bool = true) {
    micIndicator.updateTranscript(text)
    handleTranscriptionUpdate(
      text,
      isFinal: isFinal,
      allowAutoDelivery: isFinal,
      updateSession: updateSession
    )
  }

  private func collapseWhitespace(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return trimmed.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    )
  }

  private func finalizeTranscriptAfterStopIfNeeded(suppressDelivery: Bool = false) {
    let sessionText = session?.combinedText ?? ""
    let fallbackSource = sessionText.isEmpty ? liveText : sessionText
    let finalCandidate = collapseWhitespace(fallbackSource)
    guard !finalCandidate.isEmpty else { return }

    // Streaming results are display-only; never populate session.lines here.
    handleTranscriptionUpdate(
      finalCandidate,
      isFinal: true,
      allowAutoDelivery: !suppressDelivery,
      updateSession: false
    )
  }

  private func startSilenceMonitor() {
    stopSilenceMonitor()
    silenceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.checkMicrophoneInput(at: Date())
        guard self.inputIssue == nil else { return }
        guard let last = self.lastSpeechDetection else { return }
        let silenceDuration = Date().timeIntervalSince(last)
        if silenceDuration > 5 {
          self.statusMessage = String(localized: "No speech detected")
        }
      }
    }
    if let timer = silenceMonitorTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func stopSilenceMonitor() {
    silenceMonitorTimer?.invalidate()
    silenceMonitorTimer = nil
  }

  private func startRecordingSession() async throws {
    currentRecordingURL = nil
  }

  private func stopRecordingSession(shouldKeep keep: Bool) async {
    guard let url = currentRecordingURL else { return }
    guard FileManager.default.fileExists(atPath: url.path) else {
      currentRecordingURL = nil
      return
    }
    guard !keep else { return }

    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      logger.error("Failed to discard recording: \(error.localizedDescription)")
    }
    currentRecordingURL = nil
  }

  private nonisolated static func recordingsDirectoryURL() throws -> URL {
    let manager = FileManager.default
    let directory = AppIdentity.current.applicationSupportDirectory(fileManager: manager)
      .appendingPathComponent("Recordings", isDirectory: true)
    if !manager.fileExists(atPath: directory.path) {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
  }

  private nonisolated static func makeRecordingFilename() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "voice-session-\(formatter.string(from: Date()))"
  }

  private func persistDeferredRecording(
    _ capture: StreamingAudioCaptureModule.FinalizedDictationCapture,
    for sessionID: UUID
  ) {
    Task.detached(priority: .utility) { [weak self, capture] in
      let url: URL
      do {
        let directory = try Self.recordingsDirectoryURL()
        let filename = Self.makeRecordingFilename().appending(".wav")
        url = directory.appendingPathComponent(filename)
        try AudioProcessor.save(audioSamples: capture.samples, to: url)
      } catch {
        await MainActor.run { [weak self] in
          self?.logger.error("Failed to persist deferred dictation recording: \(error.localizedDescription)")
        }
        return
      }

      await MainActor.run { [weak self] in
        guard let self else {
          try? FileManager.default.removeItem(at: url)
          return
        }

        let historyContainsSession = self.historyRuntime.sessions.contains { $0.id == sessionID }
        let isActiveSession = self.session?.id == sessionID
        guard historyContainsSession || isActiveSession else {
          try? FileManager.default.removeItem(at: url)
          return
        }

        self.backfillDeferredRecording(url: url, for: sessionID)
      }
    }
  }

  private func backfillDeferredRecording(url: URL, for sessionID: UUID) {
    if var currentSession = session, currentSession.id == sessionID {
      currentSession.recordingURL = url
      session = currentSession
    }

    guard let existingSession = historyRuntime.sessions.first(where: { $0.id == sessionID }) else {
      return
    }

    var updatedSession = existingSession
    updatedSession.recordingURL = url
    historyRuntime.replace(updatedSession)
  }

  private func ensureMicrophoneAccess() async -> Bool {
    let status = await resolveMicrophoneStatus()
    await MainActor.run {
      microphoneStatus = status
    }

    switch status {
    case .granted:
      return true
    case .denied, .restricted:
      return false
    case .unknown:
      let granted = await requestPermission()
      await MainActor.run {
        microphoneStatus = granted ? .granted : .denied
      }
      return granted
    }
  }

  private func requestPermission() async -> Bool {
    return await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  private func resolveMicrophoneStatus() async -> MicrophoneStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return .granted
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .notDetermined:
      return .unknown
    @unknown default:
      return .unknown
    }
  }
}

@MainActor
extension VoiceTranscriber {
  private func handleTranscriptionUpdate(
    _ rawText: String,
    isFinal: Bool,
    allowAutoDelivery: Bool,
    updateSession: Bool = true
  ) {
    let normalized = collapseWhitespace(rawText)
    let biased = ASRDictionaryBiasService.apply(
      to: normalized,
      dictionaryEntries: AppConfiguration.shared.voiceToTextCustomDictionary
    )
    guard !biased.isEmpty else { return }

    liveText = biased

    let hasChanged = biased != lastTranscriptText
    if !hasChanged && !isFinal {
      return
    }

    if updateSession, var currentSession = session {
      let offset = Date().timeIntervalSince(currentSession.startTime)
      // Final events should still hydrate an empty session even when text hasn't changed.
      if hasChanged || currentSession.lines.isEmpty {
        currentSession.applyStreamingSnapshot(biased, at: offset)
      }
      if isFinal {
        currentSession.finish()
      }
      currentSession.recordingURL = currentRecordingURL
      session = currentSession

      let combined = currentSession.lines
        .map { line in
          line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      if !combined.isEmpty {
        micIndicator.updateTranscript(combined)
      } else {
        micIndicator.updateTranscript(biased)
      }
    } else {
      micIndicator.updateTranscript(biased)
    }

    if hasChanged {
      lastTranscriptText = biased
    }

    if allowAutoDelivery && shouldDeliverRawTranscript {
      deliverTranscriptionOutput(biased)
    }
  }

  fileprivate func deliverTranscriptionOutput(_ text: String) {
    let trimmedTarget = collapseWhitespace(text)

    guard !trimmedTarget.isEmpty else { return }

    if trimmedTarget == deliveredText { return }

    logger.info("🚀 Delivering transcription output: \(trimmedTarget)")

    deliveredText = trimmedTarget

    guard autoTypeEnabled else { return }

    guard AccessibilityGate.canInjectText else {
      copyTextToClipboard(trimmedTarget)
      micIndicator.flashCopiedToClipboard()
      logger.info("📋 Text copied to clipboard (manual paste required)")
      lastExternalFrontmostApp = nil
      return
    }

    if let targetApp = lastExternalFrontmostApp,
      targetApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
    {
      // Attempt activation regardless of return value; on modern macOS the return
      // value is unreliable but the app still comes to the foreground.
      targetApp.activate(options: [])
      lastExternalFrontmostApp = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          let typed = self.pasteIntoFocusedField(trimmedTarget)
          if !typed {
            self.logger.warning("⚠️ Failed to paste transcription output for external app")
          }
        }
      }
      return
    }

    let typed = pasteIntoFocusedField(trimmedTarget)
    if !typed {
      logger.warning("⚠️ Failed to paste transcription output for frontmost app")
    }
    lastExternalFrontmostApp = nil
  }

  /// Captures the current frontmost application as the target for dictation output.
  ///
  /// Call this **before** navigating Cliptate to the foreground so the
  /// correct external app is recorded for `deliverTranscriptionOutput`.
  public func captureExternalApp() {
    recordExternalFrontmostApplicationSnapshot()
    micIndicator.setAppIcon(lastExternalFrontmostApp?.icon)
  }

  private func recordExternalFrontmostApplicationSnapshot() {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
    let currentPid = ProcessInfo.processInfo.processIdentifier
    guard frontmost.processIdentifier != currentPid else { return }
    lastExternalFrontmostApp = frontmost
  }

  fileprivate func deliverFinalSessionOutput() {
    guard let combined = session?.combinedText else { return }
    let finalText = collapseWhitespace(combined)
    guard !finalText.isEmpty else { return }
    guard shouldDeliverRawTranscript else { return }
    deliverTranscriptionOutput(finalText)
  }

  public func deliverAssistantOutput(_ text: String) {
    deliverTranscriptionOutput(text)
  }

  @discardableResult
  fileprivate func pasteIntoFocusedField(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }

    guard AccessibilityGate.injectText(text) else {
      copyTextToClipboard(text)
      micIndicator.flashCopiedToClipboard()
      logger.info("📋 Text copied to clipboard (manual paste required)")
      return true
    }

    logger.info("⌨️ Text typed directly into focused field")
    return true
  }

  private func copyTextToClipboard(_ text: String) {
    Task.detached(priority: .userInitiated) {
      let copied = await ClipboardWriter.write(text)
      if !copied {
        Logger(subsystem: "com.Cliptate", category: "VoiceTranscriber")
          .warning("⚠️ Failed to copy dictation output to clipboard")
      }
    }
  }

  @objc private func handleApplicationDidResignActive(_: Notification) {
    recordExternalFrontmostApplicationSnapshot()
  }

  @objc private func handleApplicationDidBecomeActive(_: Notification) {}
}

#if DEBUG
  @MainActor
  extension VoiceTranscriber {
    func testPrepareForQwen3StreamAssertions() {
      voiceTranscriberTestDisablesMicIndicator = true
      inputIssue = nil
      inputMonitor.start(at: Date())
      activeStreamingProvider = nil
      streamingModule.reset()
      _ = streamingModule.takeFinalizedDictationCapture()
      state = .running
      session = nil
      liveText = ""
      statusMessage = ""
      deliveredText = ""
      sessionAllowsRawDelivery = nil
      lastTranscriptText = ""
      lastSpeechDetection = nil
    }

    func testHandleQwen3StreamUpdate(_ text: String) {
      handleStreamUpdate(text)
    }

    func testHandleMicLevelUpdate(_ level: CGFloat) {
      handleMicLevelUpdate(level)
    }

    func testCheckMicrophoneInput(at date: Date) {
      checkMicrophoneInput(at: date)
    }

    func testSetSession(_ newSession: TranscriptSession) {
      session = newSession
    }

    func testHandleParakeetStreamUpdate(_ text: String) {
      handleStreamUpdate(text)
    }

    func testDeliverFinalSessionOutput() {
      deliverFinalSessionOutput()
    }

    func testCaptureTranscriptDeliveryForSession() {
      captureTranscriptDeliveryForSession()
    }

    func testApplyDictationBatchOutput(_ output: BatchTranscriptionOutput) {
      _ = applyDictationBatchOutput(output, recordingURL: nil)
    }

    var testStreamingChunkDuration: Double {
      streamingModule.testChunkDuration
    }

    var testStreamingSpeechWindowDuration: Double {
      streamingModule.testMaxSpeechWindowDuration
    }

    var testStreamingRequiredSilentChunks: Int {
      streamingModule.testRequiredConsecutiveSilentChunks
    }

    func testPrepareForOverlayStateAssertions() {
      voiceTranscriberTestDisablesMicIndicator = false
      micIndicator.stopTracking()
      state = .idle
      statusMessage = ""
      isRetranscribing = false
      retranscriptionStatus = nil
    }

    func testSetOverlayLifecycleState(_ newState: State) {
      state = newState
    }

    var testOverlayIsActive: Bool {
      micIndicator.testIsActive
    }

    var testOverlayStatus: OverlayStatus {
      micIndicator.testOverlayStatus
    }

    func testCompletePendingOverlayDismiss() {
      micIndicator.testCompletePendingDismiss()
    }

    func testApplyWarmupWaitingStateIfNeeded(
      type: TranscriberType,
      model: ModelVariant,
      isModelLoadingOverride: Bool
    ) async -> Bool {
      await applyWarmupWaitingStateIfNeeded(
        type: type,
        model: model,
        isModelLoadingOverride: isModelLoadingOverride
      )
    }

    func testThrowIfStartupNoLongerPreparing() throws {
      try throwIfStartupNoLongerPreparing()
    }

    func testBeginAIEnhanceOverlay() {
      beginAIEnhanceOverlay()
    }

    func testResetAfterOverlayStateAssertions() {
      micIndicator.stopTracking()
      state = .idle
      statusMessage = ""
      isRetranscribing = false
      retranscriptionStatus = nil
      voiceTranscriberTestDisablesMicIndicator = false
    }

    func testResetAfterQwen3StreamAssertions() {
      stopSilenceMonitor()
      inputIssue = nil
      session = nil
      liveText = ""
      statusMessage = ""
      deliveredText = ""
      sessionAllowsRawDelivery = nil
      lastTranscriptText = ""
      lastSpeechDetection = nil
      state = .idle
      voiceTranscriberTestDisablesMicIndicator = false
    }

    func testBackfillDeferredRecording(url: URL, for sessionID: UUID) {
      backfillDeferredRecording(url: url, for: sessionID)
    }
  }
#endif

private func micRMSLevel(from samples: [Float]) -> CGFloat {
  guard !samples.isEmpty else { return 0 }

  let sumSquares = samples.reduce(Double.zero) { $0 + Double($1 * $1) }
  let mean = sumSquares / Double(samples.count)
  let rms = sqrt(max(mean, 0))
  let peak = samples.reduce(Double.zero) { max($0, Double(abs($1))) }
  let blended = max(0.000_01, 0.65 * rms + 0.35 * peak)

  let decibels = 20.0 * log10(blended)
  let normalized = (decibels + 55.0) / 55.0
  return CGFloat(min(max(normalized, 0), 1))
}

private func micEnergyLevel(from energy: [Float]) -> CGFloat {
  guard !energy.isEmpty else { return 0 }

  // 取最近的能量值（更实时）
  let recentCount = min(10, energy.count)
  let recentEnergy = energy.suffix(recentCount)

  // 使用平均值和峰值的混合，增强动态效果
  let avgEnergy = recentEnergy.reduce(0, +) / Float(recentEnergy.count)
  let maxEnergy = recentEnergy.max() ?? 0

  // 混合平均值和峰值，让跳动更明显
  let blended = 0.5 * avgEnergy + 0.5 * maxEnergy

  guard blended > 0 else { return 0 }

  // 使用更激进的缩放，增强视觉效果
  let scaled = log1p(Double(blended) * 60.0) / log1p(60.0)
  return CGFloat(min(max(scaled, 0), 1))
}


enum VoiceInputIssue: Equatable {
  case noInput
  case quietInput
  case noSpeechRecognized
  case transcriptionFailed

  var title: String {
    switch self {
    case .noInput: String(localized: "No microphone input")
    case .quietInput: String(localized: "No sound detected")
    case .noSpeechRecognized: String(localized: "No text recognized")
    case .transcriptionFailed: String(localized: "Transcription failed")
    }
  }

  var message: String {
    switch self {
    case .noInput:
      String(localized: "No audio is reaching Cliptate. Check your input device in Sound settings, reconnect it if needed, then try again.")
    case .quietInput:
      String(localized: "Your microphone is connected, but no sound was detected. Check that it isn't muted and speak closer to it.")
    case .noSpeechRecognized:
      String(localized: "Audio was received, but no text was recognized. Check the dictation language and try again.")
    case .transcriptionFailed:
      String(localized: "Final transcription failed. Any available live transcript was saved in history. Please try again.")
    }
  }
}

struct MicrophoneInputMonitor {
  private(set) var startedAt: Date = Date()
  private(set) var lastBufferAt: Date?
  private(set) var lastAudibleAt: Date?

  mutating func start(at date: Date) {
    startedAt = date
    lastBufferAt = nil
    lastAudibleAt = nil
  }

  mutating func receive(level: CGFloat, at date: Date) {
    lastBufferAt = date
    if level > 0.05 { lastAudibleAt = date }
  }

  func issue(at date: Date) -> VoiceInputIssue? {
    guard date.timeIntervalSince(startedAt) >= 3 else { return nil }
    guard let lastBufferAt, date.timeIntervalSince(lastBufferAt) < 3 else { return .noInput }
    return lastAudibleAt == nil ? .quietInput : nil
  }
}
