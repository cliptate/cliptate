import Foundation
import MLX
import MLXAudioSTT
import Testing

@testable import Cliptate

private actor NemotronLoadCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

@Suite("Nemotron ASR integration")
struct NemotronASRTranscriberTests {
  @MainActor
  @Test("Catalog exposes all supported checkpoints with 3.5 8-bit recommended")
  func catalog() throws {
    let models = TranscriberType.nemotron.supportedModels
    #expect(models == [.nemotronASR358bit, .nemotronASR35bf16, .nemotronASREnglish8bit])
    #expect(ModelsView.asrModels(for: .nemotron) == models)
    #expect(Set(models).isSubset(of: Set(ModelsView.asrModels(for: .all))))
    #expect(models.map(\.huggingFaceRepoId) == [
      "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
      "mlx-community/nemotron-3.5-asr-streaming-0.6b",
      "animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit",
    ])
    for model in models {
      #expect(model.provider == .nemotron)
      #expect(model.downloadBackend == .nemotronASR)
      #expect(!model.requiresProSubscription)
      #expect(try JSONDecoder().decode(ModelVariant.self, from: JSONEncoder().encode(model)) == model)
      #expect((TranscriberType.nemotron.createTranscriber(model: model) as? NemotronASRTranscriber)?.model == model)
    }
    let fallback = try #require(TranscriberType.nemotron.createTranscriber(model: .parakeetV3) as? NemotronASRTranscriber)
    #expect(fallback.model == .nemotronASR358bit)
    #expect(ModelVariant.nemotronASREnglish8bit.supportedLanguages == [.english])
    #expect(ModelVariant.nemotronASR358bit.supportedLanguages.count == 29)
    #expect(!ModelVariant.nemotronASR358bit.supportedLanguages.contains(.thai))
    #expect(!ModelVariant.nemotronASR358bit.supportedLanguages.contains(.greek))
  }

  @Test("Language prompts use checkpoint locale identifiers")
  func languagePrompts() async throws {
    let transcriber = NemotronASRTranscriber(testHooks: .init(loadModel: { _ in }, generate: { _, prompt in
      #expect(["zh-CN", "ja-JP", "nb-NO", "auto"].contains(prompt))
      return STTOutput(text: prompt)
    }))
    try await transcriber.warmUpModelWithProgress { _ in }
    for (language, code) in [(Language.chinese, "zh-CN"), (.japanese, "ja-JP"), (.norwegian, "nb-NO"), (.auto, "auto")] {
      #expect(try await transcriber.transcribeChunk(samples: [0.1], language: language) == code)
    }
  }

  @Test("Silence returns no segments and absent timing falls back to the audio window")
  func silenceAndTimingFallback() async throws {
    for text in ["", " hello "] {
      let transcriber = NemotronASRTranscriber(testHooks: .init(
        loadModel: { _ in }, loadAudio: { _ in [Float](repeating: 0, count: 16_000) },
        generate: { _, _ in STTOutput(text: text) }
      ))
      let result = try await transcriber.transcribeWithProgress(audioPath: "/unused.wav", language: .auto) { _ in }
      #expect(result.segments.count == (text.isEmpty ? 0 : 1))
      if let segment = result.segments.first {
        #expect(segment.startTime == 0)
        #expect(segment.endTime == 1)
        #expect(segment.words == nil)
      }
    }
  }

  @Test("Long files preserve native segment timing and window offsets")
  func fileWindows() async throws {
    let transcriber = NemotronASRTranscriber(testHooks: .init(
      loadModel: { repo in #expect(repo == ModelVariant.nemotronASR358bit.huggingFaceRepoId) },
      loadAudio: { _ in [Float](repeating: 0.1, count: 65 * 16_000) },
      generate: { samples, language in
        #expect(samples.count <= 30 * 16_000)
        #expect(language == "en-US")
        return STTOutput(text: " hello ", segments: [["text": " hello ", "start": 0.25, "end": 1.5]])
      }
    ))
    let result = try await transcriber.transcribeWithProgress(audioPath: "/unused.wav", language: .english) { _ in }
    #expect(result.segments.map(\.text) == ["hello", "hello", "hello"])
    #expect(result.segments.map(\.startTime) == [0.25, 30.25, 60.25])
    #expect(result.segments.map(\.endTime) == [1.5, 31.5, 61.5])
    #expect(result.segments.allSatisfy { $0.words == nil })
    #expect(result.totalDuration == 65)
  }

  @Test("Batch chunks and dictation use samples directly and can reload after eviction")
  func chunkAndStreaming() async throws {
    let transcriber = NemotronASRTranscriber(testHooks: .init(
      loadModel: { _ in }, generate: { _, language in
        #expect(language == "auto")
        return STTOutput(text: " hello ")
      }
    ))
    try await transcriber.warmUpModelWithProgress { _ in }
    let plan = TranscriptionPipelineFactory.makeBatchPlan(transcriber: transcriber, vadModel: .sileroVAD)
    #expect(plan.align == nil)
    #expect(try await plan.asr.transcribe(samples: [0.1], language: .auto) == "hello")
    #expect(try transcriber.transcribeStreamingChunk(samples16k: [0.1], language: .auto, dictionaryContext: "term") == "hello")
    #expect(try await transcriber.transcribeChunk(samples: [], language: .auto) == "")
    transcriber.unload()
    await #expect(throws: (any Error).self) {
      try await transcriber.transcribeChunk(samples: [0.1], language: .auto)
    }
    try await transcriber.warmUpModelWithProgress { _ in }
    #expect(try await transcriber.transcribeChunk(samples: [0.1], language: .auto) == "hello")
  }

  @Test("Concurrent preparation shares one load and failures can be retried")
  func preparation() async throws {
    let counter = NemotronLoadCounter()
    let transcriber = NemotronASRTranscriber(testHooks: .init(loadModel: { _ in
      await counter.increment()
      if await counter.count == 1 { throw CocoaError(.fileReadCorruptFile) }
      try await Task.sleep(for: .milliseconds(50))
    }))
    await #expect(throws: CocoaError.self) { try await transcriber.warmUpModelWithProgress { _ in } }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<2 {
        group.addTask { try await transcriber.warmUpModelWithProgress { _ in } }
      }
      try await group.waitForAll()
    }
    #expect(await counter.count == 2)
  }

  @Test("English-only checkpoint rejects unsupported languages before loading")
  func languageValidation() async throws {
    let transcriber = NemotronASRTranscriber(model: .nemotronASREnglish8bit, testHooks: .init(
      loadModel: { _ in Issue.record("Must not load an unsupported selection") }
    ))
    for language in [Language.auto, .chinese, .japanese] {
      await #expect(throws: (any Error).self) {
        try await transcriber.transcribeWithProgress(audioPath: "/unused.wav", language: language) { _ in }
      }
    }
  }

  @Test("Cancellation stops inference without returning a partial transcript")
  func cancellation() async throws {
    let transcriber = NemotronASRTranscriber(testHooks: .init(loadModel: { _ in }, generate: { _, _ in
      withUnsafeCurrentTask { $0?.cancel() }
      return STTOutput(text: "partial")
    }))
    try await transcriber.warmUpModelWithProgress { _ in }
    let task = Task {
      try await transcriber.transcribeChunk(samples: [Float](repeating: 0.1, count: 65 * 16_000), language: .english)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @MainActor
  @Test("Nemotron creates a unified live provider and rejects mismatched engines")
  func liveProvider() throws {
    let module = StreamingAudioCaptureModule(
      configuration: .init(chunkDuration: 2, levelCalculator: { _ in 0 }),
      callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
    )
    let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
      type: .nemotron, transcriber: NemotronASRTranscriber(), streamingModule: module, vadModel: .sileroVAD
    )
    #expect(provider is UnifiedStreamingProvider)
    #expect(throws: TranscriptionPipelineError.self) {
      try TranscriptionPipelineFactory.makeStreamingProvider(
        type: .nemotron, transcriber: MLXParakeetTranscriber(), streamingModule: module, vadModel: .sileroVAD
      )
    }
  }

  @Test("Cache readiness requires embedded vocabulary and accepts NeMo non-finite config values")
  func cacheReadiness() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = ModelDownloadManager(cacheRootProvider: { root }, legacyMLXAudioBaseProvider: { nil })
    let directory = root.appendingPathComponent("models--mlx-community--nemotron-3.5-asr-streaming-0.6b-8bit/snapshots/revision")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("weights".utf8).write(to: directory.appendingPathComponent("model.safetensors"))
    try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
    #expect(await manager.hasLocalArtifacts(for: .nemotronASR358bit) == false)
    try Data(#"{"joint":{"vocabulary":["hello"]},"value":-Infinity}"#.utf8)
      .write(to: directory.appendingPathComponent("config.json"))
    #expect(await manager.hasLocalArtifacts(for: .nemotronASR358bit))
    #expect(await manager.getModelDirectory(for: .nemotronASR358bit)?.standardizedFileURL.path == directory.standardizedFileURL.path)
    try await manager.delete(model: .nemotronASR358bit)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test("Real Nemotron 3.5 checkpoint transcribes local speech",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_NEMOTRON_MODEL_TESTS"] == "1"))
  func realModelSmoke() async throws {
    if let path = ProcessInfo.processInfo.environment["NEMOTRON_TEST_METALLIB_PATH"] {
      GPU.metallib = URL(fileURLWithPath: path)
    }
    let path = try #require(ProcessInfo.processInfo.environment["NEMOTRON_TEST_AUDIO_PATH"])
    let transcriber = NemotronASRTranscriber()
    defer { transcriber.unload() }
    for language in [Language.english, .auto] {
      let result = try await transcriber.transcribeWithProgress(audioPath: path, language: language) { _ in }
      let text = result.segments.map(\.text).joined(separator: " ").lowercased()
      #expect(text.contains("quick brown fox"))
      #expect(text.contains("lazy dog"))
      #expect(result.totalDuration > 0)
      #expect(!result.segments.isEmpty)
      #expect(result.segments.allSatisfy {
        $0.startTime.isFinite && $0.endTime.isFinite && $0.startTime >= 0
          && $0.endTime >= $0.startTime && $0.endTime <= result.totalDuration
      })
    }
  }
}
