import AVFoundation
import CliptateCore
import Foundation
import MLX
import Testing

@testable import Cliptate

@Suite("Video dubbing", .serialized)
@MainActor
struct VideoDubbingRuntimeTests {
  @Test(
    "dubbing supplies the model's language identifiers",
    arguments: [
      ("en", Language.english, "english"), ("zh", .chinese, "chinese"),
      ("ja", .japanese, "japanese"), ("ko", .korean, "korean"),
    ])
  func suppliesModelLanguage(code: String, language: Language, modelLanguage: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, request, _, _ in
      #expect(request.language == modelLanguage)
      return DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: [
        Segment(
          startTime: 0, endTime: 2, text: "你好",
          translation: .init(text: "Hello", language: language))
      ],
      totalDuration: 2, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: code, referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    _ = try await runtime.prepare(request: request)
  }

  @Test("automatic voice reference retains audible speech from compressed source audio")
  func compressedReferenceRetainsSpeech() async throws {
    let source = try #require(
      Bundle.module.url(forResource: "vad_example", withExtension: "wav", subdirectory: "Resources")
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let compressed = directory.appendingPathComponent("source.m4a")
    try await AudioExporter().exportAudio(from: source, to: compressed, format: .m4a)
    let runtime = DubbingRuntime(synthesize: { _, _, referenceURL, _ in
      let url = try #require(referenceURL)
      if let path = ProcessInfo.processInfo.environment["DUBBING_TEST_REFERENCE_CAPTURE_PATH"] {
        try Data(contentsOf: url).write(to: URL(fileURLWithPath: path), options: .atomic)
      }
      let file = try AVAudioFile(forReading: url)
      let buffer = try #require(
        AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
      try file.read(into: buffer)
      let channel = try #require(buffer.floatChannelData)[0]
      let energy = (0..<Int(buffer.frameLength)).reduce(0.0) {
        $0 + Double(channel[$1]) * Double(channel[$1])
      }
      #expect((energy / Double(buffer.frameLength)).squareRoot() > 0.01)
      return DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: compressed,
      segments: [
        Segment(
          startTime: 6.64, endTime: 11.76, text: "听到后面的有专门的活动课，它会大大降低你的试错成本。",
          translation: .init(text: "Hello", language: .english))
      ],
      totalDuration: 12, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", assetDirectory: directory)
    let preparation = try await runtime.prepare(request: request)
    #expect(preparation.issues.isEmpty)
  }

  @Test(
    "decoder priming and release silence do not delay the sentence or make it overlong",
    arguments: [480, 1_920, 2_400])
  func alignsAudibleSpeech(startupSamples: Int) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(
        samples: [Float](repeating: 0.25, count: startupSamples)
          + [Float](repeating: 0, count: 7_200 - startupSamples)
          + [Float](repeating: 0.0022, count: 480)
          + [Float](repeating: 0, count: 40_320)
          + [Float](repeating: 0.2, count: 24_000)
          + [Float](repeating: 0, count: 7_200), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: [
        Segment(
          startTime: 0, endTime: 1.4, text: "你好",
          translation: .init(text: "Hello", language: .english))
      ],
      totalDuration: 1.4, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let preparation = try await runtime.prepare(request: request)
    #expect(preparation.issues.isEmpty)
    let clip = try #require(preparation.clips.first)
    #expect(clip.duration > 1 && clip.duration < 1.3)
    let file = try AVAudioFile(forReading: clip.audioURL)
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let channel = try #require(buffer.floatChannelData)[0]
    #expect(channel[480] > 0.1)
    #expect(channel[24_479] > 0.1)
  }

  @Test(
    "local Qwen3 Base produces audible dubbed audio",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_DUBBING_MODEL_TESTS"] == "1"),
    arguments: [false, true])
  func realModelSmoke(automaticReference: Bool) async throws {
    let environment = ProcessInfo.processInfo.environment
    if let path = environment["DUBBING_TEST_METALLIB_PATH"] {
      GPU.metallib = URL(fileURLWithPath: path)
    }
    MLXRandom.seed(0)
    let source = URL(fileURLWithPath: try #require(environment["DUBBING_TEST_SOURCE_PATH"]))
    let reference = URL(fileURLWithPath: try #require(environment["DUBBING_TEST_REFERENCE_PATH"]))
    let referenceText = try #require(environment["DUBBING_TEST_REFERENCE_TEXT"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = try #require(
      MLXTTSModelDefinition.availableModels.first {
        $0.huggingFaceRepo == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"
      })
    let request = VideoDubbingRequest(
      sourceMediaURL: source,
      segments: [
        Segment(
          startTime: 0, endTime: 10, text: referenceText,
          translation: .init(text: "Trial is simple.", language: .english))
      ],
      totalDuration: 12, filterSilentSegments: false, model: model, language: "en",
      referenceAudioURL: automaticReference ? nil : reference,
      referenceText: automaticReference ? nil : referenceText, assetDirectory: directory,
      referenceSegments: [Segment(startTime: 6.64, endTime: 11.76, text: referenceText)])
    let runtime = DubbingRuntime()
    let preparation = try await runtime.prepare(request: request)
    #expect(preparation.clips.count == 1, "\(preparation.issues.map(\.message))")
    #expect(preparation.issues.isEmpty)
    if preparation.issues.isEmpty {
      var output =
        environment["DUBBING_TEST_OUTPUT_PATH"].map { URL(fileURLWithPath: $0) }
        ?? directory.appendingPathComponent("output.wav")
      if automaticReference {
        output = output.deletingPathExtension().appendingPathExtension("automatic.wav")
      }
      try await runtime.exportAudio(preparation, to: output, format: .wav)
    }
  }

  @Test("a click followed by silence is reported as synthesis failure", arguments: [480, 1920])
  func refusesSilentGeneration(startupSamples: Int) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(
        samples: [Float](repeating: 0.25, count: startupSamples)
          + [Float](repeating: 0, count: 144_000 - startupSamples),
        sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: [
        Segment(
          startTime: 0, endTime: 10, text: "你好",
          translation: .init(text: "Hello", language: .english))
      ],
      totalDuration: 10, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let preparation = try await runtime.prepare(request: request)
    #expect(preparation.clips.isEmpty)
    #expect(preparation.issues.count == 1)
    if let issue = preparation.issues.first {
      if case .failed = issue.kind {
      } else {
        Issue.record("Silent audio must be a synthesis failure")
      }
    }
  }

  @Test("regenerating a repeated line keeps that sentence's new recording")
  func keepsRegeneratedRepeatedLine() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let segments = [
      Segment(
        startTime: 0, endTime: 2, text: "你好", translation: .init(text: "Hello", language: .english)),
      Segment(
        startTime: 2, endTime: 4, text: "你好", translation: .init(text: "Hello", language: .english)),
    ]
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"), segments: segments,
      totalDuration: 4, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let first = try await runtime.prepare(request: request)
    let updated = try await runtime.prepare(
      request: request, cachedClips: first.clips,
      generating: [SegmentIdentifier(segment: segments[1])])
    let restored = try await runtime.prepare(
      request: request, cachedClips: updated.clips, generating: [])
    #expect(restored.clips[1].audioURL == updated.clips[1].audioURL)
    #expect(restored.clips[1].audioURL != first.clips[1].audioURL)
  }

  @Test(
    "empty content and translations in a different language cannot be exported",
    arguments: [false, true])
  func refusesIncompleteContent(wrongLanguage: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: wrongLanguage
        ? [
          Segment(
            startTime: 0, endTime: 1, text: "你好",
            translation: .init(text: "Hello", language: .english))
        ] : [],
      totalDuration: 1, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "zh", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    await #expect(throws: (any Error).self) {
      let preparation = try await runtime.prepare(request: request)
      try await runtime.exportAudio(
        preparation, to: directory.appendingPathComponent("dub.wav"), format: .wav)
    }
  }

  @Test("automatic voice cloning supplies a bounded source speech reference and its transcript")
  func extractsVoiceReference() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.wav")
    try MLXTTSService.createWAVData(
      from: [Float](repeating: 0.2, count: 96_000), sampleRate: 24_000
    ).write(to: source)
    let runtime = DubbingRuntime(synthesize: { _, _, referenceURL, referenceText in
      let file = try AVAudioFile(forReading: #require(referenceURL))
      #expect(abs(Double(file.length) / file.fileFormat.sampleRate - 2) < 0.01)
      #expect(referenceText == "你好")
      return DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: source,
      segments: [
        Segment(
          startTime: 1, endTime: 3, text: "你好",
          translation: .init(text: "Hello", language: .english))
      ],
      totalDuration: 4, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", assetDirectory: directory)
    let preparation = try await runtime.prepare(request: request)
    #expect(preparation.issues.isEmpty)
    #expect(preparation.clips.count == 1)
  }

  @Test("one sentence can be prepared on the edited timeline without generating the others")
  func preparesSingleSentenceOnCompressedTimeline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(samples: [Float](repeating: 0.25, count: 48_000), sampleRate: 48_000)
    })
    let segments = [
      Segment(
        startTime: 0, endTime: 2, text: "你好", translation: .init(text: "Hello", language: .english)),
      Segment(
        startTime: 10, endTime: 12, text: "再见",
        translation: .init(text: "Goodbye", language: .english)),
    ]
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"), segments: segments,
      totalDuration: 12, filterSilentSegments: true,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let preparation = try await runtime.prepare(
      request: request, generating: [SegmentIdentifier(segment: segments[1])])
    #expect(preparation.clips.count == 1)
    #expect(preparation.placements.first?.startTime == 2)
    #expect(preparation.totalDuration == 4)
    #expect(preparation.issues.first?.kind == .notGenerated)
    let complete = try await runtime.prepare(request: request, cachedClips: preparation.clips)
    let output = directory.appendingPathComponent("dubbed.wav")
    try await runtime.exportAudio(complete, to: output, format: .wav)
    let file = try AVAudioFile(forReading: output)
    #expect(file.fileFormat.sampleRate == 48_000)
    #expect(file.length == 192_000)
  }

  @Test("cancellation stops generation and retains completed sentences for resuming")
  func cancellationRetainsCompletedAudio() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { text, _, _, _ in
      if text == "Goodbye" { throw CancellationError() }
      return DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: [
        Segment(
          startTime: 0, endTime: 2, text: "你好",
          translation: .init(text: "Hello", language: .english)),
        Segment(
          startTime: 2, endTime: 4, text: "再见",
          translation: .init(text: "Goodbye", language: .english)),
      ], totalDuration: 4, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    var retained: [DubbedClip] = []
    await #expect(throws: CancellationError.self) {
      _ = try await runtime.prepare(request: request, onClip: { retained.append($0) })
    }
    #expect(retained.count == 1)
    #expect(FileManager.default.fileExists(atPath: try #require(retained.first).audioURL.path))
  }

  @Test("a failed sentence can be retried without discarding completed audio")
  func retriesFailedSentence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var shouldFail = true
    let runtime = DubbingRuntime(synthesize: { text, _, _, _ in
      if text == "Goodbye" && shouldFail { throw CocoaError(.fileReadUnknown) }
      return DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: [
        Segment(
          startTime: 0, endTime: 2, text: "你好",
          translation: .init(text: "Hello", language: .english)),
        Segment(
          startTime: 2, endTime: 4, text: "再见",
          translation: .init(text: "Goodbye", language: .english)),
      ], totalDuration: 4, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let failed = try await runtime.prepare(request: request)
    #expect(failed.clips.count == 1)
    #expect(failed.issues.count == 1)
    shouldFail = false
    let retried = try await runtime.prepare(request: request, cachedClips: failed.clips)
    #expect(retried.issues.isEmpty)
    #expect(retried.clips.count == 2)
    #expect(retried.clips[0].audioURL == failed.clips[0].audioURL)
  }

  @Test("overlong speech remains available for revision and cannot be exported truncated")
  func refusesToTruncateSpeech() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(samples: [Float](repeating: 0.25, count: 96_000), sampleRate: 24_000)
    })
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"),
      segments: [
        Segment(
          startTime: 0, endTime: 1, text: "你好",
          translation: SegmentTranslation(text: "Hello", language: .english))
      ],
      totalDuration: 1, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let preparation = try await runtime.prepare(request: request)
    #expect(preparation.clips.first?.duration == 4)
    #expect(preparation.issues.first?.kind == .overlong)
    let output = directory.appendingPathComponent("existing.wav")
    try Data("keep".utf8).write(to: output)
    await #expect(throws: (any Error).self) {
      try await runtime.exportAudio(preparation, to: output, format: .wav)
    }
    #expect(try Data(contentsOf: output) == Data("keep".utf8))
  }

  @Test("editing one translation retains the other sentence's generated audio")
  func regeneratesOnlyEditedSentence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    var segments = [
      Segment(
        startTime: 0, endTime: 2, text: "你好",
        translation: SegmentTranslation(text: "Hello", language: .english)),
      Segment(
        startTime: 10, endTime: 12, text: "再见",
        translation: SegmentTranslation(text: "Goodbye", language: .english)),
    ]
    func request() throws -> VideoDubbingRequest {
      VideoDubbingRequest(
        sourceMediaURL: directory.appendingPathComponent("source.mov"), segments: segments,
        totalDuration: 12, filterSilentSegments: false,
        model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
        language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
        referenceText: "Reference", assetDirectory: directory)
    }
    let first = try await runtime.prepare(request: request())
    segments[1].translation = SegmentTranslation(text: "See you later", language: .english)
    let updated = try await runtime.prepare(request: request(), cachedClips: first.clips)
    #expect(updated.clips[0].audioURL == first.clips[0].audioURL)
    #expect(updated.clips[1].audioURL != first.clips[1].audioURL)
  }

  @Test("speech after a long pause stays at its original start")
  func preservesSentenceStarts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = DubbingRuntime(synthesize: { _, _, _, _ in
      DubbingAudio(samples: [Float](repeating: 0.25, count: 24_000), sampleRate: 24_000)
    })
    let segments = [
      Segment(
        startTime: 0, endTime: 2, text: "你好",
        translation: SegmentTranslation(text: "Hello", language: .english)),
      Segment(
        startTime: 10, endTime: 12, text: "再见",
        translation: SegmentTranslation(text: "Goodbye", language: .english)),
    ]
    let request = VideoDubbingRequest(
      sourceMediaURL: directory.appendingPathComponent("source.mov"), segments: segments,
      totalDuration: 12, filterSilentSegments: false,
      model: try #require(DubbingModelResolver.resolveVoiceCloneModel(preferredRepo: "")),
      language: "en", referenceAudioURL: directory.appendingPathComponent("reference.wav"),
      referenceText: "Reference", assetDirectory: directory)
    let preparation = try await runtime.prepare(request: request)
    let outputURL = directory.appendingPathComponent("dubbed.wav")
    try await runtime.exportAudio(preparation, to: outputURL, format: .wav)
    let audio = try AVAudioFile(forReading: outputURL)
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
    try audio.read(into: buffer)
    let samples = try #require(buffer.floatChannelData)[0]
    #expect(audio.length == 288_000)
    #expect(samples[120_000] == 0)
    #expect(samples[240_100] > 0.2)
    #expect(samples[263_999] > 0.2)
  }
}
