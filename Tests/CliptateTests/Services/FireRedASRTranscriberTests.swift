import CliptateCore
import Foundation
import MLXAudioSTT
import Testing

@testable import Cliptate

private final class FireRedProgressCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var updates: [ModelDownloadProgress] = []

  func record(_ progress: ModelDownloadProgress) {
    lock.lock()
    updates.append(progress)
    lock.unlock()
  }

  func snapshot() -> [ModelDownloadProgress] {
    lock.lock()
    defer { lock.unlock() }
    return updates
  }
}

private final class FireRedGenerateCapture: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var lastRequest: FireRedASRTranscriber.GenerationRequest?
  var output = STTOutput(
    text: " fire red ",
    segments: [["text": " fire red ", "confidence": 0.97]],
    language: "English"
  )

  func record(_ request: FireRedASRTranscriber.GenerationRequest) -> STTOutput {
    lock.lock()
    lastRequest = request
    let output = self.output
    lock.unlock()
    return output
  }

  func snapshot() -> FireRedASRTranscriber.GenerationRequest? {
    lock.lock()
    defer { lock.unlock() }
    return lastRequest
  }
}

private func fireRedFixtureAudioPath() throws -> String {
  guard let url = Bundle.module.url(
    forResource: "vad_example", withExtension: "wav", subdirectory: "Resources"
  ) ?? Bundle.module.url(forResource: "vad_example", withExtension: "wav") else {
    throw NSError(
      domain: "FireRedASRTranscriberTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Missing vad_example.wav test resource."]
    )
  }
  return url.path
}

@Suite("FireRedASRTranscriber")
struct FireRedASRTranscriberTests {
  @Test("FireRed engine creates a FireRed transcriber")
  func fireRedCreateTranscriber() {
    let transcriber = TranscriberType.fireRed.createTranscriber(model: .fireRedASR2)

    #expect(transcriber is FireRedASRTranscriber)
  }

  @Test("FireRed engine falls back to FireRed models")
  func fireRedEngineFallsBackToFireRedModel() {
    let transcriber = TranscriberType.fireRed.createTranscriber(model: .qwen3ASR)

    let fireRed = transcriber as? FireRedASRTranscriber
    #expect(fireRed != nil)
    #expect(fireRed?.model == .fireRedASR2)
  }

  @Test("FireRed warm up loads the FireRed repository and reports readiness")
  func fireRedWarmUpLoadsExpectedRepository() async throws {
    let capture = FireRedASRTranscriber.TestHooks.LoadCapture()
    let progressCapture = FireRedProgressCapture()
    let transcriber = FireRedASRTranscriber(
      model: .fireRedASR2,
      testHooks: .init(loadModel: capture.recordLoad)
    )

    try await transcriber.warmUpModelWithProgress { progress in
      progressCapture.record(progress)
    }

    let progressUpdates = progressCapture.snapshot()
    #expect(await capture.snapshot() == [ModelVariant.fireRedASR2.huggingFaceRepoId])
    #expect(progressUpdates.first?.currentStep == "Loading FireRed ASR 2...")
    #expect(progressUpdates.last?.currentStep == "FireRed ASR 2 ready")
  }

  @Test("FireRed transcription maps output into a result segment")
  func fireRedTranscriptionMapsOutput() async throws {
    let capture = FireRedGenerateCapture()
    let transcriber = FireRedASRTranscriber(
      model: .fireRedASR2,
      testHooks: .init(
        loadAudioSamples: { _ in [0.1, -0.1, 0.2, -0.2] },
        readAudioDuration: { _ in 1.5 },
        loadModel: { _ in },
        generate: capture.record
      )
    )

    let result = try await transcriber.transcribeWithProgress(
      audioPath: try fireRedFixtureAudioPath(),
      language: Language.english
    ) { _ in }

    #expect(capture.snapshot()?.language == "English")
    #expect(result.modelUsed == ModelVariant.fireRedASR2.rawValue)
    #expect(result.totalDuration == 1.5)
    #expect(result.segments.count == 1)
    #expect(result.segments.first?.text == "fire red")
    #expect(result.segments.first?.startTime == 0)
    #expect(result.segments.first?.endTime == 1.5)
  }

  @Test("FireRed rejects unsupported languages")
  func fireRedRejectsUnsupportedLanguage() async throws {
    let transcriber = FireRedASRTranscriber(
      model: .fireRedASR2,
      testHooks: .init(
        loadAudioSamples: { _ in [0.1, -0.1] },
        readAudioDuration: { _ in 0.5 },
        loadModel: { _ in }
      )
    )

    do {
      _ = try await transcriber.transcribeWithProgress(
        audioPath: try fireRedFixtureAudioPath(),
        language: .japanese
      ) { _ in }
      Issue.record("Expected FireRed to reject unsupported languages.")
    } catch {
      #expect(error.localizedDescription.contains("does not support"))
      #expect(error.localizedDescription.contains(Language.japanese.displayName))
    }
  }
}
