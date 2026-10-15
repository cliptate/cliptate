import CliptateCore
import Foundation
import MLX
import Testing

@testable import Cliptate

private final class WhisperCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [(Int, String)] = []

  func generate(_ samples: [Float], _ language: String) -> String {
    lock.withLock {
      requests.append((samples.count, language))
      return " window \(requests.count) "
    }
  }

  var sampleCounts: [Int] { lock.withLock { requests.map { $0.0 } } }
  var languages: [String] { lock.withLock { requests.map { $0.1 } } }
}

@Suite("MLX Whisper integration")
struct MLXWhisperTranscriberTests {
  @Test("Whisper Tiny transcribes a real local audio fixture",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_WHISPER_MODEL_TESTS"] == "1"))
  func realModelSmoke() async throws {
    // SwiftPM's test helper may not discover the Metal resource bundle. The
    // packaged app locates it normally; allow an explicit path for this test.
    if let path = ProcessInfo.processInfo.environment["WHISPER_TEST_METALLIB_PATH"] {
      GPU.metallib = URL(fileURLWithPath: path)
    }
    let path = try #require(ProcessInfo.processInfo.environment["WHISPER_TEST_AUDIO_PATH"])
    let transcriber = MLXWhisperTranscriber(model: .whisperTiny)
    defer { transcriber.unload() }
    let result = try await transcriber.transcribeWithProgress(audioPath: path, language: .english) { _ in }
    let text = result.segments.map(\.text).joined(separator: " ").lowercased()
    #expect(text.contains("quick brown fox"))
    #expect(text.contains("lazy dog"))
    #expect(result.totalDuration > 0)
  }

  @MainActor
  @Test("Whisper catalog, repositories, and default point at real Whisper models")
  func catalog() throws {
    let models = TranscriberType.whisper.supportedModels
    #expect(models.count == 6)
    #expect(models.first == .whisperLargeV3Turbo)
    #expect(ModelsView.asrModels(for: .whisper) == models)
    #expect(Set(models).isSubset(of: Set(ModelsView.asrModels(for: .all))))
    for model in models {
      #expect(model.provider == .whisper)
      #expect(model.downloadBackend == .whisperASR)
      #expect(model.huggingFaceRepoId == "openai/" + model.rawValue)
      #expect(!model.supportedLanguages.contains(.auto))
      #expect(!model.supportedLanguages.contains(.yoruba))
      #expect(model.supportedLanguages.contains(.chinese))
      #expect(try JSONDecoder().decode(ModelVariant.self, from: JSONEncoder().encode(model)) == model)
      #expect((TranscriberType.whisper.createTranscriber(model: model) as? MLXWhisperTranscriber)?.model == model)
    }
    let fallback = try #require(TranscriberType.whisper.createTranscriber(model: .parakeetV3) as? MLXWhisperTranscriber)
    #expect(fallback.model == .whisperLargeV3Turbo)
    #expect(ModelDownloadManager.whisperDownloadPatterns == ["model.safetensors", "*.json", "*.txt"])
  }

  @Test("Long files preserve window offsets and never invent word timing")
  func fileWindows() async throws {
    let capture = WhisperCapture()
    let transcriber = MLXWhisperTranscriber(testHooks: .init(
      loadModel: { repo in #expect(repo == "openai/whisper-large-v3-turbo") },
      loadAudio: { _ in [Float](repeating: 0.1, count: 65 * 16_000) },
      generate: capture.generate
    ))
    let result = try await transcriber.transcribeWithProgress(
      audioPath: "/unused.wav", language: .chinese
    ) { _ in }
    #expect(capture.sampleCounts == [480_000, 480_000, 80_000])
    #expect(capture.languages == ["zh", "zh", "zh"])
    #expect(result.segments.map(\.text) == ["window 1", "window 2", "window 3"])
    #expect(result.segments.map(\.startTime) == [0, 30, 60])
    #expect(result.segments.map(\.endTime) == [30, 60, 65])
    #expect(result.segments.allSatisfy { $0.words == nil })
    #expect(result.totalDuration == 65)
    #expect(result.modelUsed == ModelVariant.whisperLargeV3Turbo.rawValue)
  }

  @Test("Prepared batch chunks and dictation both use direct sample inference")
  func chunkAndStreaming() async throws {
    let capture = WhisperCapture()
    let transcriber = MLXWhisperTranscriber(testHooks: .init(loadModel: { _ in }, generate: capture.generate))
    try await transcriber.warmUpModelWithProgress { _ in }
    let provider = TranscriptionPipelineFactory.makeASRChunkProvider(transcriber: transcriber)
    #expect(try await provider.transcribe(samples: [0.1], language: .japanese) == "window 1")
    #expect(try transcriber.transcribeStreamingChunk(samples16k: [0.2], language: .english, dictionaryContext: "term") == "window 2")
    #expect(try await transcriber.transcribeChunk(samples: [], language: .english) == "")
    #expect(capture.languages == ["ja", "en"])
    transcriber.unload()
    await #expect(throws: (any Error).self) {
      try await transcriber.transcribeChunk(samples: [0.1], language: .english)
    }
    try await transcriber.warmUpModelWithProgress { _ in }
    #expect(try await transcriber.transcribeChunk(samples: [0.1], language: .english) == "window 3")
  }

  @Test("Whisper rejects implicit language detection before loading a model")
  func explicitLanguage() async throws {
    let transcriber = MLXWhisperTranscriber(testHooks: .init(loadModel: { _ in Issue.record("Must not load") }))
    await #expect(throws: (any Error).self) {
      try await transcriber.transcribeWithProgress(audioPath: "/unused.wav", language: .auto) { _ in }
    }
  }

  @Test("Cancellation between windows stops inference without returning a partial result")
  func cancellation() async throws {
    let capture = WhisperCapture()
    let transcriber = MLXWhisperTranscriber(testHooks: .init(loadModel: { _ in }, generate: { samples, language in
      let text = capture.generate(samples, language)
      withUnsafeCurrentTask { $0?.cancel() }
      return text
    }))
    try await transcriber.warmUpModelWithProgress { _ in }
    let task = Task {
      try await transcriber.transcribeChunk(samples: [Float](repeating: 0.1, count: 65 * 16_000), language: .english)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(capture.sampleCounts == [480_000])
  }

  @MainActor
  @Test("Whisper creates a unified live transcription provider")
  func liveProvider() throws {
    let module = StreamingAudioCaptureModule(
      configuration: .init(chunkDuration: 2.0, levelCalculator: { _ in 0 }),
      callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
    )
    let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
      type: .whisper, transcriber: MLXWhisperTranscriber(), streamingModule: module, vadModel: .sileroVAD
    )
    #expect(provider is UnifiedStreamingProvider)
    #expect(throws: TranscriptionPipelineError.self) {
      try TranscriptionPipelineFactory.makeStreamingProvider(
        type: .whisper, transcriber: MLXParakeetTranscriber(), streamingModule: module, vadModel: .sileroVAD
      )
    }
  }

  @Test("Download readiness requires the local Whisper tokenizer and generation configuration")
  func cacheReadiness() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = ModelDownloadManager(cacheRootProvider: { root }, legacyMLXAudioBaseProvider: { nil })
    let directory = root.appendingPathComponent("models--openai--whisper-tiny/snapshots/revision")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
    try Data("weights".utf8).write(to: directory.appendingPathComponent("model.safetensors"))
    #expect(await manager.hasLocalArtifacts(for: .whisperTiny) == false)
    for name in ["tokenizer.json", "tokenizer_config.json", "generation_config.json"] {
      try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
    }
    #expect(await manager.hasLocalArtifacts(for: .whisperTiny))
    #expect(await manager.getModelDirectory(for: .whisperTiny)?.standardizedFileURL.path == directory.standardizedFileURL.path)
    try Data().write(to: directory.appendingPathComponent("tokenizer.json"))
    #expect(await manager.hasLocalArtifacts(for: .whisperTiny) == false)
    try await manager.delete(model: .whisperTiny)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }
}
