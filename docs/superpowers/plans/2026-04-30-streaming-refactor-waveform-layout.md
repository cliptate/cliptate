# Streaming Architecture Refactor & Waveform Layout Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract shared mic/VAD/buffer logic into a unified `StreamingAudioCaptureModule`, add FireRed streaming support, and fix the waveform overlay layout spacing.

**Architecture:** A single `StreamingAudioCaptureModule` replaces both `MLXParakeetStreamingModule` and `Qwen3StreamingModule`. ASR models conform to a new `StreamingASREngine` protocol with one method. The MicIndicatorOverlay waveform section switches to compact fixed spacing.

**Tech Stack:** Swift, AVFoundation, SwiftUI, MLXAudioSTT

---

### Task 1: Fix MicIndicatorOverlay Waveform Layout

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift:648-720`

- [ ] **Step 1: Update waveformSection to use compact spacing**

In `MicIndicatorOverlay.swift`, replace the `waveformSection` method body (lines 648-684):

```swift
private func waveformSection(
    visualizerState: VisualizerState
) -> some View {
    HStack(alignment: .center, spacing: 12) {
        if let appIcon = viewModel.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }

        scrollingVisualizer()

        // Duration or spinner when processing
        if let start = viewModel.recordingStartDate {
            if visualizerState == .transcribing || visualizerState == .aiEnhance {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else if !viewModel.hasEnteredProcessing {
                TimelineView(.animation(minimumInterval: 1.0)) { timeline in
                    let elapsed = Int(timeline.date.timeIntervalSince(start))
                    Text(formatDuration(elapsed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Update scrollingVisualizer to use flexible width**

Replace the `scrollingVisualizer(width:)` method signature and body (lines 687-722):

```swift
/// Scrolling waveform: bars represent recent audio levels, flowing right-to-left.
private func scrollingVisualizer() -> some View {
    let spacing: CGFloat = 1.5
    let history = viewModel.levelHistory
    let range = maxHeight - minHeight

    return GeometryReader { geometry in
        let availableWidth = geometry.size.width
        let barWidth = max(2.0, (availableWidth - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))

        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level: CGFloat = {
                    let offset = barCount - history.count
                    let historyIndex = index - offset
                    guard historyIndex >= 0, historyIndex < history.count else {
                        return 0
                    }
                    return history[historyIndex]
                }()
                let barHeight = max(minHeight, minHeight + range * level)
                let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
                let gradient = LinearGradient(
                    colors: [
                        Color(hue: 0.55 - normalizedIndex * 0.08, saturation: 0.8, brightness: 1.0, opacity: 0.7 + Double(level) * 0.3),
                        Color(hue: 0.7 - normalizedIndex * 0.1, saturation: 0.85, brightness: 0.9, opacity: 0.6 + Double(level) * 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RoundedRectangle(cornerRadius: barWidth / 2.5, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.linear(duration: 0.08), value: history.count)
    }
    .frame(height: maxHeight)
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift
git commit -m "fix: compact waveform layout in MicIndicatorOverlay

Replace Spacer-based layout with fixed spacing HStack.
Waveform visualizer now uses flexible width via GeometryReader.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Create StreamingASREngine Protocol

**Files:**
- Create: `Sources/VoiceFlowPro/Services/StreamingASREngine.swift`

- [ ] **Step 1: Create the protocol file**

```swift
import Foundation

/// Minimal protocol for any ASR model that can transcribe a chunk of 16kHz mono audio.
///
/// Conformers provide a synchronous transcription method. The streaming pipeline
/// handles mic capture, buffering, VAD, and resampling — engines only see
/// pre-processed 16kHz speech samples.
@MainActor
protocol StreamingASREngine {
  /// Transcribe a chunk of 16kHz mono audio samples.
  /// - Parameters:
  ///   - samples16k: Pre-resampled 16kHz mono float samples.
  ///   - language: Target language for transcription.
  ///   - dictionaryContext: Optional custom dictionary bias context string.
  /// - Returns: Transcribed text for this chunk (may be empty).
  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String
}
```

- [ ] **Step 2: Add MLXParakeetTranscriber conformance**

In `Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift`, add at the end of the file:

```swift
// MARK: - StreamingASREngine

extension MLXParakeetTranscriber: StreamingASREngine {
  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String {
    guard let parakeetModel else {
      throw NSError(
        domain: "VoiceFlow", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "MLX Parakeet model not initialized. Call warmUpModelWithProgress first."
        ])
    }
    guard !samples16k.isEmpty else { return "" }
    let audioArray = MLXArray(samples16k)
    let params = STTGenerateParameters(
      maxTokens: 448, temperature: 0.0, topP: 0.95, topK: 0, verbose: false)
    let output = parakeetModel.generate(audio: audioArray, generationParameters: params)
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
```

- [ ] **Step 3: Add Qwen3ASRTranscriber conformance**

In `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`, add at the end of the file:

```swift
// MARK: - StreamingASREngine

extension Qwen3ASRTranscriber: StreamingASREngine {}
```

Note: Qwen3 already has `transcribeStreamingChunk(samples16k:language:dictionaryContext:)` with matching signature.

- [ ] **Step 4: Add FireRedASRTranscriber conformance**

In `Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift`, add at the end of the file:

```swift
// MARK: - StreamingASREngine

extension FireRedASRTranscriber: StreamingASREngine {
  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String {
    guard let model = state.currentModel() else {
      throw NSError(
        domain: "FireRedASR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Model not initialized. Warm up the model first."]
      )
    }
    guard !samples16k.isEmpty else { return "" }

    if let generate = testHooks?.generate {
      let request = GenerationRequest(audio: samples16k, language: language.bcp47Code)
      let output = try generate(request)
      return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let request = FireRedASR2Model.GenerateInput(
      audio: samples16k,
      language: language.bcp47Code
    )
    let output = try model.generate(input: request)
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
```

- [ ] **Step 5: Build to verify**

Run: `swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/StreamingASREngine.swift \
        Sources/VoiceFlowPro/Services/MLXParakeetTranscriber.swift \
        Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift \
        Sources/VoiceFlowPro/Services/FireRedASRTranscriber.swift
git commit -m "feat: add StreamingASREngine protocol with conformances

MLXParakeetTranscriber, Qwen3ASRTranscriber, and FireRedASRTranscriber
all conform to the new protocol for unified streaming support.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Create StreamingAudioCaptureModule

**Files:**
- Create: `Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift`

- [ ] **Step 1: Write the test file**

Create `Sources/VoiceFlowProTests/Services/StreamingAudioCaptureModuleTests.swift`:

```swift
import Foundation
import Testing

@testable import VoiceFlowPro

@MainActor
struct StreamingAudioCaptureModuleTests {

  /// Mock ASR engine that records received samples and returns canned text.
  final class MockASREngine: StreamingASREngine {
    var receivedChunks: [[Float]] = []
    var textToReturn: String = "hello"
    var shouldThrow = false

    func transcribeStreamingChunk(
      samples16k: [Float],
      language: Language,
      dictionaryContext: String?
    ) throws -> String {
      if shouldThrow {
        throw NSError(domain: "Test", code: 1, userInfo: nil)
      }
      receivedChunks.append(samples16k)
      return textToReturn
    }
  }

  @Test func moduleInitializesWithConfiguration() {
    let module = StreamingAudioCaptureModule(
      configuration: .init(chunkDuration: 2.0, levelCalculator: { _ in 0.5 }),
      callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
    )
    #expect(module != nil)
  }

  @Test func resetClearsAccumulatedText() async {
    let module = StreamingAudioCaptureModule(
      configuration: .init(chunkDuration: 2.0, levelCalculator: { _ in 0.5 }),
      callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
    )
    module.reset()
    // Should not crash, state is clean
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

Add `"Services/StreamingAudioCaptureModuleTests.swift"` to the test target sources in `Package.swift`.

- [ ] **Step 3: Create StreamingAudioCaptureModule**

Create `Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift`:

```swift
import AVFoundation
import CoreGraphics
import Foundation
import os.log

/// Unified streaming audio capture module that handles mic input, buffering,
/// resampling, VAD, and dispatches speech chunks to any `StreamingASREngine`.
///
/// Flow: mic tap → resample to 16kHz → chunk → VAD → speech window → ASR engine → text callback
@MainActor
final class StreamingAudioCaptureModule {
  struct Configuration {
    let chunkDuration: Double
    let levelCalculator: ([Float]) -> CGFloat
  }

  struct Callbacks {
    let onAudioLevel: (CGFloat) -> Void
    let onInterimText: (String) -> Void
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
  private var speechAccumulator = StreamingSpeechAccumulator(
    maxBufferedSamples: StreamingAudioCaptureModule.maxSpeechWindowSamples
  )

  private var accumulatedText: String = ""
  private var isProcessing = false
  private var isActive = false
  private var streamingVAD: (any StreamingVADProvider)?

  private static let sampleRate: Double = 16000
  private static let maxSpeechWindowDuration: Double = 3.0
  private static let maxSpeechWindowSamples = Int(3.0 * 16000)

  init(
    audioEngine: AVAudioEngine = AVAudioEngine(),
    logger: Logger = Logger(subsystem: "com.voiceflowpro.app", category: "StreamingCapture"),
    configuration: Configuration,
    callbacks: Callbacks
  ) {
    self.audioEngine = audioEngine
    self.logger = logger
    self.configuration = configuration
    self.callbacks = callbacks
  }

  func start(
    engine: any StreamingASREngine,
    language: Language,
    dictionaryContext: String? = nil,
    streamingVAD: (any StreamingVADProvider)? = nil
  ) async throws {
    reset()

    isActive = true
    currentLanguage = language
    self.engine = engine
    self.dictionaryContext = dictionaryContext
    logger.notice("🎤 Streaming capture starting for \(String(describing: type(of: engine)))")

    if let vad = streamingVAD {
      do {
        try await vad.start(model: AppConfiguration.shared.vadModelVariant)
        self.streamingVAD = vad
        logger.notice("🎤 Streaming VAD enabled: \(AppConfiguration.shared.vadModelVariant.displayName)")
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

    if !audioBuffer.isEmpty && engine != nil {
      await processRemainingBuffer()
    }

    await streamingVAD?.stop()

    let finalText = accumulatedText.isEmpty ? nil : collapseWhitespace(accumulatedText)
    logger.notice("🎤 Streaming capture stopped. Final text length: \(finalText?.count ?? 0)")
    reset()
    return finalText
  }

  func reset() {
    isActive = false
    stopAudioCapture()

    audioBuffer.removeAll(keepingCapacity: false)
    audioBufferHead = 0
    samplesPerChunk = 0
    currentFormat = nil
    chunkScratchBuffer.removeAll(keepingCapacity: false)
    speechAccumulator = StreamingSpeechAccumulator(
      maxBufferedSamples: StreamingAudioCaptureModule.maxSpeechWindowSamples
    )
    accumulatedText = ""
    isProcessing = false
    currentLanguage = .auto
    dictionaryContext = nil
    engine = nil
    streamingVAD = nil
  }

  // MARK: - Audio Pipeline

  private func configureAudioPipeline() throws {
    stopAudioCapture()
    audioEngine.reset()

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    currentFormat = format

    let computedSamples = Int(configuration.chunkDuration * format.sampleRate)
    samplesPerChunk = max(1, computedSamples)

    audioBuffer.removeAll(keepingCapacity: true)
    audioBuffer.reserveCapacity(samplesPerChunk * 2)
    audioBufferHead = 0
    chunkScratchBuffer = Array(repeating: 0, count: samplesPerChunk)

    removeInputTapIfNeeded()
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
      guard let self else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.processBuffer(buffer, format: buffer.format)
      }
    }
    isTapInstalled = true

    audioEngine.prepare()
    try audioEngine.start()
    logger.notice("🎤 Audio pipeline started (chunk=\(String(format: "%.1f", self.configuration.chunkDuration))s)")
  }

  private func processBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) async {
    guard isActive else { return }

    if currentFormat?.sampleRate != format.sampleRate {
      currentFormat = format
      let computedSamples = Int(configuration.chunkDuration * format.sampleRate)
      samplesPerChunk = max(1, computedSamples)
      chunkScratchBuffer = Array(repeating: 0, count: samplesPerChunk)
    }

    guard let channelData = buffer.floatChannelData?[0] else { return }
    let frameLength = Int(buffer.frameLength)

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

      if !isProcessing && isActive {
        await processChunk(chunkScratchBuffer)
      }

      await Task.yield()
    }

    if audioBufferHead > 0 {
      audioBuffer.removeFirst(audioBufferHead)
      audioBufferHead = 0
    }
  }

  private func processChunk(_ rawChunk: [Float]) async {
    guard !rawChunk.isEmpty else { return }
    isProcessing = true
    defer { isProcessing = false }

    let samples = preparedSamples(from: rawChunk)
    guard !samples.isEmpty else { return }

    if let vad = streamingVAD {
      do {
        let activity = try await vad.feed(samples: samples)
        if let speechWindow = speechAccumulator.ingest(
          chunk: samples,
          speechSampleRanges: activity.speechSampleRanges
        ) {
          transcribe(samples: speechWindow)
        }
      } catch {
        self.streamingVAD = nil
        logger.error("🎤 VAD chunk failed, switching to fixed chunks: \(error.localizedDescription)")
        transcribe(samples: samples)
      }
      return
    }

    transcribe(samples: samples)
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

    if let vad = streamingVAD {
      do {
        let activity = try await vad.feed(samples: samples)
        if let speechWindow = speechAccumulator.ingest(
          chunk: samples,
          speechSampleRanges: activity.speechSampleRanges
        ) {
          transcribe(samples: speechWindow)
        }
        if let trailingSpeech = speechAccumulator.flush() {
          transcribe(samples: trailingSpeech)
        }
      } catch {
        logger.error("🎤 VAD final chunk failed: \(error.localizedDescription)")
        transcribe(samples: samples)
      }
      return
    }

    transcribe(samples: samples)
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

  // MARK: - Transcription

  private func transcribe(samples: [Float]) {
    guard let engine, !samples.isEmpty else { return }
    do {
      let text = try engine.transcribeStreamingChunk(
        samples16k: samples,
        language: currentLanguage,
        dictionaryContext: dictionaryContext
      )
      guard !text.isEmpty else { return }
      accumulatedText = mergeTranscript(accumulatedText, with: text)
      callbacks.onInterimText(collapseWhitespace(accumulatedText))
    } catch {
      logger.error("🎤 ASR chunk failed: \(error.localizedDescription)")
    }
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
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter StreamingAudioCaptureModuleTests 2>&1 | tail -10`
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift \
        Sources/VoiceFlowProTests/Services/StreamingAudioCaptureModuleTests.swift \
        Package.swift
git commit -m "feat: add StreamingAudioCaptureModule with unified mic/VAD/buffer pipeline

Replaces the duplicated logic in MLXParakeetStreamingModule and
Qwen3StreamingModule with a single generic module that accepts
any StreamingASREngine.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Update StreamingTranscriptionProvider and Factory

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/StreamingTranscriptionProvider.swift`
- Modify: `Sources/VoiceFlowPro/Services/TranscriptionPipelineFactory.swift`

- [ ] **Step 1: Rewrite StreamingTranscriptionProvider.swift**

Replace the entire file content with a single unified provider:

```swift
import Foundation

/// Abstracts a single streaming transcription session (mic-to-text).
///
/// Implementations are created per-session by `TranscriptionPipelineFactory`
/// and wrap a `StreamingAudioCaptureModule` together with an engine.
@MainActor
protocol StreamingTranscriptionProvider: AnyObject {
  func start(language: Language, dictionaryContext: String?) async throws
  func stop() async throws -> String?
  func reset()
}

/// Unified streaming provider backed by StreamingAudioCaptureModule.
@MainActor
final class UnifiedStreamingProvider: StreamingTranscriptionProvider {
  private let module: StreamingAudioCaptureModule
  private let engine: any StreamingASREngine
  private let streamingVAD: (any StreamingVADProvider)?

  init(
    module: StreamingAudioCaptureModule,
    engine: any StreamingASREngine,
    streamingVAD: (any StreamingVADProvider)? = nil
  ) {
    self.module = module
    self.engine = engine
    self.streamingVAD = streamingVAD
  }

  func start(language: Language, dictionaryContext: String?) async throws {
    try await module.start(
      engine: engine,
      language: language,
      dictionaryContext: dictionaryContext,
      streamingVAD: streamingVAD
    )
  }

  func stop() async throws -> String? {
    try await module.stop()
  }

  func reset() {
    module.reset()
  }
}
```

- [ ] **Step 2: Update TranscriptionPipelineFactory**

Replace the streaming section of `TranscriptionPipelineFactory.swift` (the `makeStreamingProvider` method and its signature):

```swift
  // MARK: - Streaming Pipeline

  /// Creates a streaming transcription provider for any supported engine type.
  ///
  /// A fresh `SortformerStreamingVADModule` is created each time and injected
  /// into the provider so the capture module remains decoupled from the concrete
  /// VAD type.
  @MainActor
  static func makeStreamingProvider(
    type: TranscriberType,
    transcriber: any Transcriber,
    streamingModule: StreamingAudioCaptureModule
  ) throws -> any StreamingTranscriptionProvider {
    let vad = SortformerStreamingVADModule(
      logger: .init(subsystem: "com.voiceflowpro.app", category: "StreamingVAD"),
      configuration: .init(sampleRate: 16_000, threshold: 0.5)
    )

    let engine: any StreamingASREngine
    switch type {
    case .parakeet, .whisper:
      guard let parakeet = transcriber as? MLXParakeetTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "MLXParakeetTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = parakeet
    case .qwen3:
      guard let qwen3 = transcriber as? Qwen3ASRTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "Qwen3ASRTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = qwen3
    case .fireRed:
      guard let fireRed = transcriber as? FireRedASRTranscriber else {
        throw TranscriptionPipelineError.transcirberTypeMismatch(
          expected: "FireRedASRTranscriber", actual: String(describing: Swift.type(of: transcriber)))
      }
      engine = fireRed
    }

    return UnifiedStreamingProvider(module: streamingModule, engine: engine, streamingVAD: vad)
  }
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED (may fail — proceed to Task 5 to fix VoiceTranscriber references)

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Services/StreamingTranscriptionProvider.swift \
        Sources/VoiceFlowPro/Services/TranscriptionPipelineFactory.swift
git commit -m "refactor: unify StreamingTranscriptionProvider with single implementation

TranscriptionPipelineFactory now creates UnifiedStreamingProvider for
all engine types including FireRed. Old per-engine providers removed.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Update VoiceTranscriber to Use Unified Module

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`

- [ ] **Step 1: Replace parakeetModule and qwen3Module with unified streamingModule**

Replace lines 76-116 (the two lazy vars) with:

```swift
  private lazy var streamingModule: StreamingAudioCaptureModule = {
    let configuration = StreamingAudioCaptureModule.Configuration(
      chunkDuration: 2.0,
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
```

- [ ] **Step 2: Unify stream update handlers**

Add a single `handleStreamUpdate` method and remove `handleParakeetStreamUpdate` and `handleQwen3StreamUpdate`:

```swift
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
```

- [ ] **Step 3: Update reset calls**

Replace `parakeetModule.reset()` and `qwen3Module.reset()` (line 179-180) with:

```swift
      streamingModule.reset()
```

- [ ] **Step 4: Update configureEngine to pass streamingModule**

In the `configureEngine` method (around line 517-522), replace:

```swift
    activeStreamingProvider = try TranscriptionPipelineFactory.makeStreamingProvider(
      type: type,
      transcriber: transcriber,
      parakeetModule: parakeetModule,
      qwen3Module: qwen3Module
    )
```

with:

```swift
    activeStreamingProvider = try TranscriptionPipelineFactory.makeStreamingProvider(
      type: type,
      transcriber: transcriber,
      streamingModule: streamingModule
    )
```

- [ ] **Step 5: Remove FireRed special-case (streaming now supported)**

Around lines 512-515, remove the early return for FireRed:

```swift
    if type == .fireRed {
      activeStreamingProvider = nil
      return
    }
```

Replace with nothing — let it flow through to the normal `makeStreamingProvider` call.

- [ ] **Step 6: Update test helpers**

Update `testHandleParakeetStreamUpdate` and `testHandleQwen3StreamUpdate` (around line 952-961) to both call `handleStreamUpdate`:

```swift
    func testHandleQwen3StreamUpdate(_ text: String) {
      handleStreamUpdate(text)
    }

    func testHandleParakeetStreamUpdate(_ text: String) {
      handleStreamUpdate(text)
    }
```

- [ ] **Step 7: Build to verify**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Sources/VoiceFlowPro/Services/VoiceTranscriber.swift
git commit -m "refactor: VoiceTranscriber uses unified StreamingAudioCaptureModule

Removes separate parakeetModule/qwen3Module lazy vars. All engines
now share one streamingModule instance. FireRed streaming enabled.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Delete Old Streaming Modules

**Files:**
- Delete: `Sources/VoiceFlowPro/Services/MLXParakeetStreamingModule.swift`
- Delete: `Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift`

- [ ] **Step 1: Delete the files**

```bash
rm Sources/VoiceFlowPro/Services/MLXParakeetStreamingModule.swift
rm Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift
```

- [ ] **Step 2: Search for any remaining references**

```bash
grep -rn "MLXParakeetStreamingModule\|Qwen3StreamingModule" Sources/ --include="*.swift"
```

Fix any remaining references (likely in tests or other files).

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete obsolete MLXParakeetStreamingModule and Qwen3StreamingModule

These are fully replaced by the unified StreamingAudioCaptureModule.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Update TranscriptionPipelineFactoryTests

**Files:**
- Modify: `Sources/VoiceFlowProTests/Services/TranscriptionPipelineFactoryTests.swift`

- [ ] **Step 1: View current tests to understand what needs updating**

Check the current test file for references to the old module parameters and update assertions. The factory now takes `streamingModule` instead of `parakeetModule` + `qwen3Module`.

- [ ] **Step 2: Update test calls**

Replace any `makeStreamingProvider(type:transcriber:parakeetModule:qwen3Module:)` calls with:

```swift
let module = StreamingAudioCaptureModule(
  configuration: .init(chunkDuration: 2.0, levelCalculator: { _ in 0.0 }),
  callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
)
let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
  type: .fireRed,
  transcriber: fireRedTranscriber,
  streamingModule: module
)
```

- [ ] **Step 3: Add FireRed streaming test**

```swift
@Test func makeStreamingProviderFireRedReturnsUnifiedProvider() throws {
  let transcriber = FireRedASRTranscriber(
    model: .fireRedASR2,
    testHooks: .init(generate: { request in
      STTOutput(text: "test", segments: [])
    })
  )
  let module = StreamingAudioCaptureModule(
    configuration: .init(chunkDuration: 2.0, levelCalculator: { _ in 0.0 }),
    callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
  )
  let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
    type: .fireRed,
    transcriber: transcriber,
    streamingModule: module
  )
  #expect(provider is UnifiedStreamingProvider)
}
```

- [ ] **Step 4: Remove the old "streamingNotSupported" test for FireRed**

The factory no longer throws for FireRed — remove or update the test that asserts `.streamingNotSupported`.

- [ ] **Step 5: Run tests**

Run: `swift test --filter TranscriptionPipelineFactoryTests 2>&1 | tail -10`
Expected: All tests passed

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowProTests/Services/TranscriptionPipelineFactoryTests.swift
git commit -m "test: update pipeline factory tests for unified streaming

FireRed now returns a provider instead of throwing. All factory tests
use the new streamingModule parameter.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Run Full Test Suite and Fix Remaining Issues

**Files:**
- Various test files as needed

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests passed

- [ ] **Step 2: Fix any compilation or test failures**

Address any remaining references to deleted types or changed APIs.

- [ ] **Step 3: Run xcodebuild to verify app target compiles**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve remaining compilation issues from streaming refactor

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
