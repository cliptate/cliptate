import AVFoundation
import CoreGraphics
import Foundation
import os.log

/// Unified streaming audio capture module that handles mic input, buffering,
/// resampling, VAD, and dispatches speech chunks to any `StreamingASREngine`.
///
/// Architecture: 2-stage pipeline
/// - **Stage 1 (main thread)**: mic tap → resample → chunk → VAD → speech window accumulation + audio level callbacks
/// - **Stage 2 (background)**: speech windows queued → ASR inference off main thread → results delivered back to main
///
/// This ensures audio level updates and waveform rendering are never blocked by ASR inference.
@MainActor
final class StreamingAudioCaptureModule {
  struct FinalizedDictationCapture: Sendable {
    let samples: [Float]
    let duration: TimeInterval
  }

  struct Configuration {
    let chunkDuration: Double
    let maxSpeechWindowDuration: Double
    let requiredConsecutiveSilentChunks: Int
    let levelCalculator: ([Float]) -> CGFloat

    init(
      chunkDuration: Double,
      maxSpeechWindowDuration: Double = 2.0,
      requiredConsecutiveSilentChunks: Int = 1,
      levelCalculator: @escaping ([Float]) -> CGFloat
    ) {
      self.chunkDuration = chunkDuration
      self.maxSpeechWindowDuration = maxSpeechWindowDuration
      self.requiredConsecutiveSilentChunks = max(1, requiredConsecutiveSilentChunks)
      self.levelCalculator = levelCalculator
    }
  }

  struct Callbacks: Sendable {
    let onAudioLevel: @MainActor @Sendable (CGFloat) -> Void
    let onInterimText: @MainActor @Sendable (String) -> Void
  }

  private let audioEngine: AVAudioEngine
  private let logger: Logger
  private let configuration: Configuration
  private let callbacks: Callbacks

  private var engine: (any StreamingASREngine)?
  private var currentLanguage: Language = .auto
  private var dictionaryContext: String?

  private var audioBuffer: [Float] = []
  private var audioBufferHead: Int = 0
  private var samplesPerChunk: Int = 0
  private var currentFormat: AVAudioFormat?
  private var isTapInstalled = false
  private var chunkScratchBuffer: [Float] = []
  private var speechAccumulator: StreamingSpeechAccumulator

  private var accumulatedText: String = ""
  /// True while a background ASR task is in flight.
  private var isProcessing = false
  private var isActive = false
  private var streamingVAD: (any StreamingVADProvider)?
  private var recordingSink: StreamingAudioFileRecorder?
  private var sessionCaptureSamples: [Float] = []
  private var latestFinalizedDictationCapture: FinalizedDictationCapture?

  /// Queued speech windows to process after current ASR inference completes.
  /// Preserve FIFO order so continuous dictation doesn't silently drop windows.
  private var pendingSpeechWindows: [[Float]] = []

  /// Session token to prevent stale completions from a previous session.
  private var sessionToken: UInt64 = 0

  /// Continuation used by `stop()` to wait for in-flight ASR work to drain.
  private var drainContinuation: CheckedContinuation<Void, Never>?

  private static let sampleRate: Double = 16000
  init(
    audioEngine: AVAudioEngine = AVAudioEngine(),
    logger: Logger = Logger(subsystem: "com.cliptate.app", category: "StreamingCapture"),
    configuration: Configuration,
    callbacks: Callbacks
  ) {
    self.audioEngine = audioEngine
    self.logger = logger
    self.configuration = configuration
    self.callbacks = callbacks
    self.speechAccumulator = StreamingSpeechAccumulator(
      maxBufferedSamples: Self.maxSpeechWindowSamples(for: configuration),
      requiredConsecutiveSilentChunks: configuration.requiredConsecutiveSilentChunks
    )
  }

  func start(
    engine: any StreamingASREngine,
    language: Language,
    dictionaryContext: String? = nil,
    streamingVAD: (any StreamingVADProvider)? = nil,
    vadModel: ModelVariant? = nil
  ) async throws {
    latestFinalizedDictationCapture = nil
    resetState(preservingRecordingSink: true)

    sessionToken &+= 1
    isActive = true
    currentLanguage = language
    self.engine = engine
    self.dictionaryContext = dictionaryContext
    logger.notice("🎤 Streaming capture starting for \(String(describing: type(of: engine)))")

    if let vad = streamingVAD, let vadModel {
      do {
        try await vad.start(model: vadModel)
        self.streamingVAD = vad
        logger.notice("🎤 Streaming VAD enabled: \(vadModel.displayName)")
      } catch {
        self.streamingVAD = nil
        logger.error("🎤 VAD unavailable, falling back to fixed chunks: \(error.localizedDescription)")
      }
    }

    try configureAudioPipeline()
  }

  func stop() async throws -> String? {
    isActive = false
    stopAudioCapture()

    if engine != nil {
      await processRemainingBuffer()
      if let trailingSpeech = speechAccumulator.flush() {
        enqueueForTranscription(trailingSpeech)
      }
    }

    // Drain in-flight ASR work before returning final text
    if isProcessing || !pendingSpeechWindows.isEmpty {
      await withCheckedContinuation { continuation in
        drainContinuation = continuation
      }
    }

    await streamingVAD?.stop()
    try await finishRecording()

    if !sessionCaptureSamples.isEmpty {
      latestFinalizedDictationCapture = FinalizedDictationCapture(
        samples: sessionCaptureSamples,
        duration: Double(sessionCaptureSamples.count) / Self.sampleRate
      )
    } else {
      latestFinalizedDictationCapture = nil
    }

    let finalText = accumulatedText.isEmpty ? nil : collapseWhitespace(accumulatedText)
    logger.notice("🎤 Streaming capture stopped. Final text length: \(finalText?.count ?? 0)")
    reset()
    return finalText
  }

  func beginRecording(to outputURL: URL) {
    recordingSink = StreamingAudioFileRecorder(outputURL: outputURL)
  }

  func finishRecording() async throws {
    guard let recordingSink else { return }
    self.recordingSink = nil
    try await recordingSink.finish()
  }

  func takeFinalizedDictationCapture() -> FinalizedDictationCapture? {
    defer { latestFinalizedDictationCapture = nil }
    return latestFinalizedDictationCapture
  }

  func reset() {
    resetState()
  }

  private func resetState(preservingRecordingSink: Bool = false) {
    isActive = false
    stopAudioCapture()

    audioBuffer.removeAll(keepingCapacity: false)
    audioBufferHead = 0
    samplesPerChunk = 0
    currentFormat = nil
    chunkScratchBuffer.removeAll(keepingCapacity: false)
    speechAccumulator = StreamingSpeechAccumulator(
      maxBufferedSamples: Self.maxSpeechWindowSamples(for: configuration),
      requiredConsecutiveSilentChunks: configuration.requiredConsecutiveSilentChunks
    )
    sessionCaptureSamples.removeAll(keepingCapacity: false)
    accumulatedText = ""
    isProcessing = false
    pendingSpeechWindows.removeAll(keepingCapacity: false)
    currentLanguage = .auto
    dictionaryContext = nil
    engine = nil
    streamingVAD = nil
    if !preservingRecordingSink {
      recordingSink = nil
    }
    // Resume any waiting drain continuation
    drainContinuation?.resume()
    drainContinuation = nil
  }

  // MARK: - Audio Pipeline

  private func configureAudioPipeline() throws {
    stopAudioCapture()
    audioEngine.reset()

    let inputNode = audioEngine.inputNode
    let preferredOutputFormat = inputNode.outputFormat(forBus: 0)
    let hardwareInputFormat = inputNode.inputFormat(forBus: 0)
    let tapFormat = Self.resolvedTapFormat(
      preferredOutputFormat: preferredOutputFormat,
      hardwareInputFormat: hardwareInputFormat
    )
    currentFormat = tapFormat

    let computedSamples = Int(configuration.chunkDuration * tapFormat.sampleRate)
    samplesPerChunk = max(1, computedSamples)

    audioBuffer.removeAll(keepingCapacity: true)
    audioBuffer.reserveCapacity(samplesPerChunk * 2)
    audioBufferHead = 0
    chunkScratchBuffer = Array(repeating: 0, count: samplesPerChunk)

    removeInputTapIfNeeded()
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
      // The audio thread reuses tap buffers; own the samples before handing them to an async task.
      guard let buffer = Self.copyPCMBuffer(buffer) else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.processBuffer(buffer, format: buffer.format)
      }
    }
    isTapInstalled = true

    audioEngine.prepare()
    try audioEngine.start()
    if tapFormat.sampleRate != preferredOutputFormat.sampleRate || tapFormat.channelCount != preferredOutputFormat.channelCount {
      logger.notice(
        "🎤 Using hardware-compatible tap format (\(tapFormat.sampleRate, format: .fixed(precision: 0)) Hz, \(tapFormat.channelCount) ch) instead of preferred output format (\(preferredOutputFormat.sampleRate, format: .fixed(precision: 0)) Hz, \(preferredOutputFormat.channelCount) ch)"
      )
    }
    logger.notice("🎤 Audio pipeline started (chunk=\(String(format: "%.1f", self.configuration.chunkDuration))s)")
  }

  private func processBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) async {
    guard isActive else { return }

    if let recordingSink {
      if let recordingBuffer = Self.copyPCMBuffer(buffer) {
        do {
          try await recordingSink.append(buffer: recordingBuffer)
        } catch {
          logger.error("🎤 Failed to write dictation recording: \(error.localizedDescription)")
          self.recordingSink = nil
        }
      } else {
        logger.error("🎤 Failed to copy captured audio for dictation recording")
        self.recordingSink = nil
      }
    }

    if currentFormat?.sampleRate != format.sampleRate {
      currentFormat = format
      let computedSamples = Int(configuration.chunkDuration * format.sampleRate)
      samplesPerChunk = max(1, computedSamples)
      chunkScratchBuffer = Array(repeating: 0, count: samplesPerChunk)
    }

    guard let channelData = buffer.floatChannelData?[0] else { return }
    let frameLength = Int(buffer.frameLength)

    // Stage 1: Audio level callbacks — always immediate, never blocked by ASR
    if frameLength > 0 {
      let bufferSamples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
      let level = configuration.levelCalculator(bufferSamples)
      callbacks.onAudioLevel(level)
    }

    for index in 0..<frameLength {
      audioBuffer.append(channelData[index])
    }

    while isActive && (audioBuffer.count - audioBufferHead) >= samplesPerChunk {
      let start = audioBufferHead
      let end = start + samplesPerChunk

      guard loadScratchBuffer(from: start) else {
        audioBufferHead = end
        continue
      }
      audioBufferHead = end

      // Stage 1: Always process VAD/resampling (fast, stays on main thread)
      await processChunk(chunkScratchBuffer)

      await Task.yield()
    }

    if audioBufferHead > 0 {
      audioBuffer.removeFirst(audioBufferHead)
      audioBufferHead = 0
    }
  }

  private func processChunk(_ rawChunk: [Float]) async {
    guard !rawChunk.isEmpty else { return }

    let samples = preparedSamples(from: rawChunk)
    guard !samples.isEmpty else { return }
    sessionCaptureSamples.append(contentsOf: samples)

    if let vad = streamingVAD {
      do {
        let activity = try await vad.feed(samples: samples)
        if let speechWindow = speechAccumulator.ingest(
          chunk: samples,
          speechSampleRanges: activity.speechSampleRanges
        ) {
          // Stage 2: Dispatch speech window to background ASR
          enqueueForTranscription(speechWindow)
        }
      } catch {
        self.streamingVAD = nil
        logger.error("🎤 VAD chunk failed, switching to fixed chunks: \(error.localizedDescription)")
        enqueueForTranscription(samples)
      }
      return
    }

    enqueueForTranscription(samples)
  }

  private func processRemainingBuffer() async {
    let remainingSamples = Array(audioBuffer.dropFirst(audioBufferHead))
    guard !remainingSamples.isEmpty else { return }

    audioBuffer.removeAll()
    audioBufferHead = 0

    let level = configuration.levelCalculator(remainingSamples)
    callbacks.onAudioLevel(level)

    let samples = preparedSamples(from: remainingSamples)
    guard !samples.isEmpty else { return }
    sessionCaptureSamples.append(contentsOf: samples)

    if let vad = streamingVAD {
      do {
        let activity = try await vad.feed(samples: samples)
        if let speechWindow = speechAccumulator.ingest(
          chunk: samples,
          speechSampleRanges: activity.speechSampleRanges
        ) {
          enqueueForTranscription(speechWindow)
        }
        if let trailingSpeech = speechAccumulator.flush() {
          enqueueForTranscription(trailingSpeech)
        }
      } catch {
        logger.error("🎤 VAD final chunk failed: \(error.localizedDescription)")
        enqueueForTranscription(samples)
      }
      return
    }

    enqueueForTranscription(samples)
  }

  // MARK: - Stage 2: Async ASR Dispatch

  /// Enqueue a speech window for background ASR. If ASR is already in flight,
  /// the window is queued and processed after the current inference completes.
  private func enqueueForTranscription(_ samples: [Float]) {
    guard !samples.isEmpty else { return }

    if isProcessing {
      pendingSpeechWindows.append(samples)
      return
    }

    transcribeAsync(samples: samples)
  }

  /// Run ASR inference on a background thread, deliver results back to main.
  private func transcribeAsync(samples: [Float]) {
    guard let engine else { return }
    isProcessing = true
    let capturedToken = sessionToken
    let lang = currentLanguage
    let dict = dictionaryContext

    Task.detached { [weak self] in
      let text: String?
      do {
        let result = try engine.transcribeStreamingChunk(
          samples16k: samples,
          language: lang,
          dictionaryContext: dict
        )
        text = result.isEmpty ? nil : result
      } catch {
        text = nil
      }
      await self?.handleTranscriptionResult(text: text, sessionToken: capturedToken)
    }
  }

  /// Called on main thread when background ASR completes.
  private func handleTranscriptionResult(text: String?, sessionToken token: UInt64) {
    // Ignore results from a stale session
    guard token == sessionToken else { return }

    isProcessing = false

    if let text {
      accumulatedText = mergeTranscript(accumulatedText, with: text)
      callbacks.onInterimText(collapseWhitespace(accumulatedText))
    }

    // Process queued speech window if any
    if !pendingSpeechWindows.isEmpty {
      let queued = pendingSpeechWindows.removeFirst()
      transcribeAsync(samples: queued)
    } else if drainContinuation != nil {
      // No more work — resume drain
      drainContinuation?.resume()
      drainContinuation = nil
    }
  }

  // MARK: - Audio Capture Control

  private func stopAudioCapture() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    removeInputTapIfNeeded()
  }

  private func removeInputTapIfNeeded() {
    guard isTapInstalled else { return }
    audioEngine.inputNode.removeTap(onBus: 0)
    isTapInstalled = false
  }

  // MARK: - Buffer Helpers

  private func loadScratchBuffer(from startIndex: Int) -> Bool {
    guard samplesPerChunk > 0 else { return false }
    if chunkScratchBuffer.count != samplesPerChunk {
      chunkScratchBuffer = Array(repeating: 0, count: samplesPerChunk)
    }
    return audioBuffer.withUnsafeBufferPointer { sourcePointer in
      chunkScratchBuffer.withUnsafeMutableBufferPointer { destinationPointer in
        guard let srcBase = sourcePointer.baseAddress,
              let destBase = destinationPointer.baseAddress else { return false }
        destBase.update(from: srcBase.advanced(by: startIndex), count: samplesPerChunk)
        return true
      }
    }
  }

  private nonisolated static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard
      let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
    else {
      return nil
    }

    copy.frameLength = buffer.frameLength
    let channelCount = Int(buffer.format.channelCount)

    switch buffer.format.commonFormat {
    case .pcmFormatFloat32:
      guard let source = buffer.floatChannelData, let destination = copy.floatChannelData else {
        return nil
      }
      for channel in 0..<channelCount {
        destination[channel].update(from: source[channel], count: Int(buffer.frameLength))
      }
    case .pcmFormatInt16:
      guard let source = buffer.int16ChannelData, let destination = copy.int16ChannelData else {
        return nil
      }
      for channel in 0..<channelCount {
        destination[channel].update(from: source[channel], count: Int(buffer.frameLength))
      }
    case .pcmFormatInt32:
      guard let source = buffer.int32ChannelData, let destination = copy.int32ChannelData else {
        return nil
      }
      for channel in 0..<channelCount {
        destination[channel].update(from: source[channel], count: Int(buffer.frameLength))
      }
    default:
      return nil
    }

    return copy
  }

  // MARK: - Resampling

  private func preparedSamples(from samples: [Float]) -> [Float] {
    if let format = currentFormat, format.sampleRate != Self.sampleRate {
      return resampleTo16kHz(samples, fromRate: format.sampleRate)
    }
    return samples
  }

  private func resampleTo16kHz(_ samples: [Float], fromRate: Double) -> [Float] {
    guard fromRate != Self.sampleRate else { return samples }
    let ratio = Self.sampleRate / fromRate
    let newLength = Int(Double(samples.count) * ratio)
    guard newLength > 0 else { return [] }
    var resampled = [Float](repeating: 0, count: newLength)
    for i in 0..<newLength {
      let srcIndex = Double(i) / ratio
      let srcIndexInt = Int(srcIndex)
      let frac = Float(srcIndex - Double(srcIndexInt))
      if srcIndexInt + 1 < samples.count {
        resampled[i] = samples[srcIndexInt] * (1 - frac) + samples[srcIndexInt + 1] * frac
      } else if srcIndexInt < samples.count {
        resampled[i] = samples[srcIndexInt]
      }
    }
    return resampled
  }

  // MARK: - Text Helpers

  private func collapseWhitespace(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }

  private func mergeTranscript(_ base: String, with addition: String) -> String {
    guard !addition.isEmpty else { return base }
    guard !base.isEmpty else { return addition }
    if addition == base { return base }
    if base.contains(addition) { return base }
    if addition.contains(base) { return addition }
    let overlap = longestOverlap(between: base, and: addition)
    let suffixStart = addition.index(addition.startIndex, offsetBy: overlap)
    let additionSuffix = String(addition[suffixStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !additionSuffix.isEmpty else { return base }
    return base + (base.hasSuffix(" ") ? "" : " ") + additionSuffix
  }

  private func longestOverlap(between base: String, and addition: String) -> Int {
    let maxOverlap = min(base.count, addition.count)
    guard maxOverlap > 0 else { return 0 }
    for overlap in stride(from: maxOverlap, through: 1, by: -1) {
      if base.suffix(overlap) == addition.prefix(overlap) { return overlap }
    }
    return 0
  }

  private static func maxSpeechWindowSamples(for configuration: Configuration) -> Int {
    Int(max(0.05, configuration.maxSpeechWindowDuration) * Self.sampleRate)
  }

  private static func resolvedTapFormat(
    preferredOutputFormat: AVAudioFormat,
    hardwareInputFormat: AVAudioFormat
  ) -> AVAudioFormat {
    guard
      preferredOutputFormat.sampleRate != hardwareInputFormat.sampleRate
        || preferredOutputFormat.channelCount != hardwareInputFormat.channelCount
        || preferredOutputFormat.commonFormat != .pcmFormatFloat32
        || preferredOutputFormat.isInterleaved
    else {
      return preferredOutputFormat
    }

    return AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: hardwareInputFormat.sampleRate,
      channels: hardwareInputFormat.channelCount,
      interleaved: false
    ) ?? hardwareInputFormat
  }

  // MARK: - Test Hooks

  #if DEBUG
  /// Feed samples directly into the async transcription pipeline for testing.
  func testTranscribeAsync(samples: [Float]) async {
    enqueueForTranscription(samples)
  }

  /// Trigger an audio level callback for testing.
  func testUpdateAudioLevel(samples: [Float]) {
    let level = configuration.levelCalculator(samples)
    callbacks.onAudioLevel(level)
  }

  /// Configure the module for testing without starting the audio pipeline.
  func testConfigure(
    engine: any StreamingASREngine,
    language: Language,
    dictionaryContext: String? = nil,
    streamingVAD: (any StreamingVADProvider)? = nil
  ) {
    sessionToken &+= 1
    isActive = true
    currentLanguage = language
    self.engine = engine
    self.dictionaryContext = dictionaryContext
    self.streamingVAD = streamingVAD
  }

  func testProcessBuffer(_ buffer: AVAudioPCMBuffer) async {
    currentFormat = buffer.format
    samplesPerChunk = max(1, Int(configuration.chunkDuration * buffer.format.sampleRate))
    await processBuffer(buffer, format: buffer.format)
  }

  /// Wait for all in-flight and pending ASR work to complete.
  func testDrainPendingWork() async {
    if isProcessing || !pendingSpeechWindows.isEmpty {
      await withCheckedContinuation { continuation in
        drainContinuation = continuation
      }
    }
  }

  /// Test accessor for isProcessing state.
  var testIsProcessingASR: Bool { isProcessing }

  /// Test accessor for configured live chunk duration.
  var testChunkDuration: Double { configuration.chunkDuration }

  /// Test accessor for configured speech-window duration.
  var testMaxSpeechWindowDuration: Double { configuration.maxSpeechWindowDuration }

  /// Test accessor for configured speech-window sample cap.
  var testMaxSpeechWindowSamples: Int {
    Self.maxSpeechWindowSamples(for: configuration)
  }

  /// Test accessor for configured silent chunk threshold.
  var testRequiredConsecutiveSilentChunks: Int {
    configuration.requiredConsecutiveSilentChunks
  }

  /// Feed a chunk with VAD activity directly to the accumulator for behavioral testing.
  /// Returns the emitted speech window if the accumulator threshold is reached, nil otherwise.
  func testIngestWithVAD(chunk: [Float], speechSampleRanges: [Range<Int>]) -> [Float]? {
    speechAccumulator.ingest(chunk: chunk, speechSampleRanges: speechSampleRanges)
  }

  func testPrepareForSessionStart() {
    resetState(preservingRecordingSink: true)
  }

  static func testResolvedTapFormat(
    preferredOutputFormat: AVAudioFormat,
    hardwareInputFormat: AVAudioFormat
  ) -> AVAudioFormat {
    resolvedTapFormat(
      preferredOutputFormat: preferredOutputFormat,
      hardwareInputFormat: hardwareInputFormat
    )
  }

  var testHasRecordingSink: Bool {
    recordingSink != nil
  }

  func testInjectNormalizedCaptureSamples(_ samples: [Float]) {
    sessionCaptureSamples.append(contentsOf: samples)
  }

  func testTakeFinalizedDictationCapture() -> FinalizedDictationCapture? {
    takeFinalizedDictationCapture()
  }
  #endif
}
