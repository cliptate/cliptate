import AVFoundation
import Foundation
import Testing

@testable import Cliptate

// MARK: - Mock ASR Engine

/// A mock ASR engine that records calls and can simulate slow inference.
/// Not @MainActor since StreamingASREngine is Sendable and called from background threads.
final class MockStreamingASREngine: StreamingASREngine, @unchecked Sendable {
  private let lock = NSLock()
  private var _transcribeCalls: [[Float]] = []
  private var _transcribedOnMainThread: [Bool] = []
  private var _resultIndex = 0
  var transcribeResults: [String] = []
  /// Simulated inference delay in seconds (0 = instant).
  var inferenceDelay: TimeInterval = 0

  var transcribeCalls: [[Float]] {
    lock.lock()
    defer { lock.unlock() }
    return _transcribeCalls
  }

  var transcribedOnMainThread: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return _transcribedOnMainThread
  }

  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String {
    lock.lock()
    _transcribedOnMainThread.append(Thread.isMainThread)
    _transcribeCalls.append(samples16k)
    let index = _resultIndex
    _resultIndex += 1
    lock.unlock()

    if inferenceDelay > 0 {
      Thread.sleep(forTimeInterval: inferenceDelay)
    }
    if index < transcribeResults.count {
      return transcribeResults[index]
    }
    return "chunk\(index)"
  }
}

// MARK: - Tests

@Suite("StreamingAudioCaptureModule async transcription")
@MainActor
struct StreamingAudioCaptureModuleAsyncTests {

  /// Helper to create a module with test callbacks.
  private func makeModule(
    chunkDuration: Double = 0.5,
    maxSpeechWindowDuration: Double = 3.0,
    requiredConsecutiveSilentChunks: Int = 1,
    onAudioLevel: @MainActor @Sendable @escaping (CGFloat) -> Void = { _ in },
    onInterimText: @MainActor @Sendable @escaping (String) -> Void = { _ in }
  ) -> StreamingAudioCaptureModule {
    let config = StreamingAudioCaptureModule.Configuration(
      chunkDuration: chunkDuration,
      maxSpeechWindowDuration: maxSpeechWindowDuration,
      requiredConsecutiveSilentChunks: requiredConsecutiveSilentChunks,
      levelCalculator: { samples in
        let sum = samples.reduce(0) { $0 + abs($1) }
        return CGFloat(sum / max(Float(samples.count), 1))
      }
    )
    let callbacks = StreamingAudioCaptureModule.Callbacks(
      onAudioLevel: onAudioLevel,
      onInterimText: onInterimText
    )
    return StreamingAudioCaptureModule(configuration: config, callbacks: callbacks)
  }

  // MARK: - Async Transcription Tests

  @Test("ASR inference does not block main thread during transcription")
  func asrInferenceRunsOffMainThread() async throws {
    let engine = MockStreamingASREngine()
    engine.inferenceDelay = 0.1
    engine.transcribeResults = ["hello"]

    var interimTexts: [String] = []
    let module = makeModule(
      onInterimText: { text in interimTexts.append(text) }
    )

    // Configure without starting audio hardware
    module.testConfigure(engine: engine, language: .auto)

    // Feed a speech chunk via the testable API
    await module.testTranscribeAsync(samples: Array(repeating: 0.5, count: 8000))

    // Wait for async result delivery
    await module.testDrainPendingWork()

    // ASR should have run off the main thread
    #expect(engine.transcribedOnMainThread.count >= 1)
    #expect(engine.transcribedOnMainThread.allSatisfy { !$0 },
            "ASR inference should NOT run on main thread")

    // Result should have been delivered
    #expect(!interimTexts.isEmpty, "Interim text should have been delivered")
  }

  @Test("Audio level callbacks continue during ASR inference")
  func audioLevelNotBlockedDuringASR() async throws {
    let engine = MockStreamingASREngine()
    engine.inferenceDelay = 0.2
    engine.transcribeResults = ["hello"]

    var levelUpdates: [CGFloat] = []
    let module = makeModule(
      onAudioLevel: { level in levelUpdates.append(level) }
    )

    module.testConfigure(engine: engine, language: .auto)

    // Start async transcription (non-blocking)
    await module.testTranscribeAsync(samples: Array(repeating: 0.5, count: 8000))

    // Immediately call audio level update — should not be blocked
    module.testUpdateAudioLevel(samples: Array(repeating: 0.3, count: 1024))

    #expect(!levelUpdates.isEmpty, "Audio level should update even during ASR inference")

    await module.testDrainPendingWork()
  }

  // MARK: - Chunk Queuing Tests

  @Test("Chunks queued during ASR are processed after inference completes")
  func chunksQueuedNotDropped() async throws {
    let engine = MockStreamingASREngine()
    engine.inferenceDelay = 0.15
    engine.transcribeResults = ["first", "second"]

    var interimTexts: [String] = []
    let module = makeModule(
      onInterimText: { text in interimTexts.append(text) }
    )

    module.testConfigure(engine: engine, language: .auto)

    // Feed first chunk — starts ASR
    await module.testTranscribeAsync(samples: Array(repeating: 0.5, count: 8000))

    // Feed second chunk while first is still processing — should queue
    await module.testTranscribeAsync(samples: Array(repeating: 0.3, count: 8000))

    // Wait for both to complete
    await module.testDrainPendingWork()

    // Both chunks should have been transcribed
    #expect(engine.transcribeCalls.count == 2, "Both chunks should be transcribed, got \(engine.transcribeCalls.count)")
    #expect(interimTexts.count >= 2, "Should have received interim text for both chunks")
  }

  @Test("Multiple queued chunks are all processed in order while ASR is busy")
  func multipleQueuedChunksAreNotOverwritten() async throws {
    let engine = MockStreamingASREngine()
    engine.inferenceDelay = 0.2
    engine.transcribeResults = ["first", "second", "third"]

    var interimTexts: [String] = []
    let module = makeModule(
      onInterimText: { text in interimTexts.append(text) }
    )

    module.testConfigure(engine: engine, language: .auto)

    await module.testTranscribeAsync(samples: Array(repeating: 0.5, count: 8000))
    await module.testTranscribeAsync(samples: Array(repeating: 0.3, count: 8000))
    await module.testTranscribeAsync(samples: Array(repeating: 0.1, count: 8000))

    await module.testDrainPendingWork()

    #expect(
      engine.transcribeCalls.count == 3,
      "All queued chunks should be transcribed in order, got \(engine.transcribeCalls.count)"
    )
    #expect(
      interimTexts.last?.contains("third") == true,
      "Merged interim transcript should include the final queued chunk"
    )
  }

  @Test("stop() drains pending ASR work before returning final text")
  func stopDrainsPendingWork() async throws {
    let engine = MockStreamingASREngine()
    engine.inferenceDelay = 0.1
    engine.transcribeResults = ["hello", "world"]

    var interimTexts: [String] = []
    let module = makeModule(
      onInterimText: { text in interimTexts.append(text) }
    )

    module.testConfigure(engine: engine, language: .auto)

    // Feed chunks
    await module.testTranscribeAsync(samples: Array(repeating: 0.5, count: 8000))
    await module.testTranscribeAsync(samples: Array(repeating: 0.3, count: 8000))

    // Stop should wait for pending work
    let finalText = try await module.stop()

    // Final text should include results from all chunks
    #expect(finalText != nil, "Final text should not be nil")
    #expect(finalText?.contains("hello") == true, "Final text should contain first chunk result")
    #expect(finalText?.contains("world") == true, "Final text should contain second chunk result")
  }

  @Test("Session token prevents stale completions from contaminating new session")
  func sessionTokenPreventsStaleResults() async throws {
    let engine = MockStreamingASREngine()
    engine.inferenceDelay = 0.2
    engine.transcribeResults = ["stale", "fresh"]

    var interimTexts: [String] = []
    let module = makeModule(
      onInterimText: { text in interimTexts.append(text) }
    )

    // Session 1: configure, feed, then reset quickly (before ASR completes)
    module.testConfigure(engine: engine, language: .auto)
    await module.testTranscribeAsync(samples: Array(repeating: 0.5, count: 8000))
    // Reset immediately without waiting — simulates rapid session switch
    module.reset()

    interimTexts.removeAll()

    // Session 2: start fresh
    module.testConfigure(engine: engine, language: .auto)
    await module.testTranscribeAsync(samples: Array(repeating: 0.3, count: 8000))

    await module.testDrainPendingWork()

    // Should only have fresh results, no stale from session 1
    let hasFreshOnly = interimTexts.allSatisfy { !$0.contains("stale") }
    #expect(hasFreshOnly, "No stale results from previous session should appear")
  }

  @Test("Configured speech window duration sets the accumulator cap")
  func configuredSpeechWindowDurationSetsAccumulatorCap() {
    let module = makeModule(maxSpeechWindowDuration: 0.25)

    #expect(
      module.testMaxSpeechWindowSamples == 4_000,
      "A 0.25s speech window at 16kHz should cap buffered speech at 4000 samples"
    )
  }

  @Test("Configured silent chunk threshold is exposed for streaming endpointing")
  func configuredSilentChunkThresholdIsExposed() {
    let module = makeModule(requiredConsecutiveSilentChunks: 3)

    #expect(module.testRequiredConsecutiveSilentChunks == 3)
  }

  @Test("Streaming audio file recorder writes captured buffers to a readable WAV file")
  func streamingAudioFileRecorderWritesReadableWaveFile() async throws {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("wav")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let recorder = StreamingAudioFileRecorder(outputURL: outputURL)

    let firstBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    firstBuffer.frameLength = 1024
    let secondBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
    secondBuffer.frameLength = 512

    if let firstChannel = firstBuffer.floatChannelData?[0] {
      for index in 0..<Int(firstBuffer.frameLength) {
        firstChannel[index] = Float(index) / Float(firstBuffer.frameLength)
      }
    }

    if let secondChannel = secondBuffer.floatChannelData?[0] {
      for index in 0..<Int(secondBuffer.frameLength) {
        secondChannel[index] = -Float(index) / Float(secondBuffer.frameLength)
      }
    }

    try await recorder.append(buffer: firstBuffer)
    try await recorder.append(buffer: secondBuffer)
    try await recorder.finish()

    let file = try AVAudioFile(forReading: outputURL)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(file.length == 1_536)
    #expect(file.fileFormat.sampleRate == 48_000)
    #expect(file.fileFormat.channelCount == 1)
  }

  @Test("Prepared dictation recording survives streaming startup reset")
  func preparedRecordingSurvivesStreamingStartupReset() {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("wav")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let module = makeModule()
    module.beginRecording(to: outputURL)

    #expect(module.testHasRecordingSink)

    module.testPrepareForSessionStart()

    #expect(
      module.testHasRecordingSink,
      "Streaming startup should not discard a prepared dictation recording sink before audio capture begins"
    )
  }

  @Test("Tap format prefers hardware input format when engine output format is incompatible")
  func tapFormatPrefersHardwareInputFormatWhenNeeded() throws {
    let preferredOutput = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let hardwareInput = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))

    let resolved = StreamingAudioCaptureModule.testResolvedTapFormat(
      preferredOutputFormat: preferredOutput,
      hardwareInputFormat: hardwareInput
    )

    #expect(resolved.sampleRate == 48_000)
    #expect(resolved.channelCount == 1)
  }

  @Test("Tap format keeps preferred output format when it already matches hardware")
  func tapFormatKeepsPreferredOutputFormatWhenCompatible() throws {
    let preferredOutput = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let hardwareInput = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))

    let resolved = StreamingAudioCaptureModule.testResolvedTapFormat(
      preferredOutputFormat: preferredOutput,
      hardwareInputFormat: hardwareInput
    )

    #expect(resolved.sampleRate == 48_000)
    #expect(resolved.channelCount == 1)
  }

  @Test("Audio pipeline installs input tap before starting engine")
  func audioPipelineInstallsTapBeforeStartingEngine() throws {
    let source = try streamingAudioCaptureModuleSource()
    let preferredOutputIndex = try #require(source.range(of: "let preferredOutputFormat = inputNode.outputFormat(forBus: 0)"))
    let resolvedFormatIndex = try #require(source.range(of: "Self.resolvedTapFormat"))
    let installTapIndex = try #require(source.range(of: "inputNode.installTap"))
    let startIndex = try #require(source.range(of: "try audioEngine.start()"))

    #expect(preferredOutputIndex.lowerBound < resolvedFormatIndex.lowerBound)
    #expect(resolvedFormatIndex.lowerBound < installTapIndex.lowerBound)
    #expect(
      installTapIndex.lowerBound < startIndex.lowerBound,
      "Input tap must be installed before AVAudioEngine starts so microphone buffers are delivered"
    )
  }

  @Test("stop exposes finalized in-memory dictation capture payload")
  func stopExposesFinalizedInMemoryDictationCapture() async throws {
    let engine = MockStreamingASREngine()
    engine.transcribeResults = ["hello"]

    let module = makeModule()
    module.testConfigure(engine: engine, language: .auto)
    module.testInjectNormalizedCaptureSamples([0.1, 0.2, 0.3, 0.4])

    _ = try await module.stop()
    let capture = try #require(module.testTakeFinalizedDictationCapture())

    #expect(capture.samples == [0.1, 0.2, 0.3, 0.4])
    #expect(capture.duration == Double(capture.samples.count) / 16_000.0)
  }

  @Test("Silent chunk threshold controls when speech windows are emitted")
  func silentChunkThresholdControlsEmissionBehavior() {
    let module = makeModule(requiredConsecutiveSilentChunks: 3)

    // Feed a chunk with speech content (8000 samples = 0.5s at 16kHz)
    let speechChunk = Array(repeating: Float(0.5), count: 8000)
    let speechRange = 0..<8000

    // Initial speech chunk - accumulates but doesn't emit yet
    var emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [speechRange])
    #expect(emission == nil, "Should not emit after initial speech chunk")

    // First silent chunk - should NOT emit (need 3 consecutive)
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [])
    #expect(emission == nil, "Should not emit after 1 silent chunk (threshold is 3)")

    // Second silent chunk - should NOT emit (need 3 consecutive)
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [])
    #expect(emission == nil, "Should not emit after 2 silent chunks (threshold is 3)")

    // Third silent chunk - NOW it should emit
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [])
    #expect(emission != nil, "Should emit after 3rd consecutive silent chunk")
    #expect(emission?.isEmpty == false, "Emitted speech window should contain samples")

    // Verify behavior persists after reset
    module.reset()

    // Feed speech again after reset
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [speechRange])
    #expect(emission == nil, "After reset: should not emit after initial speech chunk")

    // First silent chunk after reset - should NOT emit
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [])
    #expect(emission == nil, "After reset: should not emit after 1 silent chunk")

    // Second silent chunk after reset - should NOT emit
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [])
    #expect(emission == nil, "After reset: should not emit after 2 silent chunks")

    // Third silent chunk after reset - should emit
    emission = module.testIngestWithVAD(chunk: speechChunk, speechSampleRanges: [])
    #expect(emission != nil, "After reset: should still emit on 3rd consecutive silent chunk")
  }

  private func streamingAudioCaptureModuleSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent("Sources/Cliptate/Services/StreamingAudioCaptureModule.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}

// MARK: - Waveform Centering Tests

@Suite("MicIndicatorOverlay waveform centering")
@MainActor
struct MicIndicatorWaveformCenteringTests {

  @Test("Level history bars are vertically centered in the visualizer")
  func levelHistoryBarsCentered() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // Feed some level data
    overlay.updateLevel(0.5)
    overlay.updateLevel(0.8)
    overlay.updateLevel(0.2)

    // The test accessor should confirm level history exists
    #expect(overlay.testLevelHistory.count == 3)

    // Verify the visualizer uses center alignment (testable property)
    #expect(overlay.testVisualizerUsesCenterAlignment == true,
            "Waveform bars should be vertically centered")

    overlay.stopTracking()
  }
}
