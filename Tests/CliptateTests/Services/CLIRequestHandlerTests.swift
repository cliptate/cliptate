import XCTest

@testable import Cliptate

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

final class CLIRequestHandlerTests: XCTestCase {
  @MainActor
  func testDictionaryMutationIsPersistedBeforeReturningAndUsesExistingNormalization() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = AppConfigurationPersistence(
      fileURL: directory.appendingPathComponent("config.json"))
    let config = AppConfiguration()
    persistence.bind(to: config)
    config.replaceDictionaryEntries(with: ["Existing"])
    let handler = CLIRequestHandler(config: config, persist: { try persistence.flush(using: $0) })
    let added = try await handler.execute(
      CLIRequest(
        operation: .dictionaryAdd, entries: ["  Cliptate ", "cliptate", "", "Café", "CAFE"]))
    XCTAssertEqual(added.entries, ["Existing", "Cliptate", "Café"])
    XCTAssertEqual(persistence.loadSnapshot()?.voiceToTextCustomDictionary, added.entries)
    let removed = try await handler.execute(
      CLIRequest(operation: .dictionaryRemove, entries: [" CAFE "]))
    XCTAssertEqual(removed.entries, ["Existing", "Cliptate"])
    XCTAssertEqual(persistence.loadSnapshot()?.voiceToTextCustomDictionary, removed.entries)
    // A previously debounced save must not reintroduce deleted words.
    try await Task.sleep(for: .milliseconds(450))
    XCTAssertEqual(persistence.loadSnapshot()?.voiceToTextCustomDictionary, removed.entries)
  }

  @MainActor
  func testFailedPersistenceRollsBackDictionary() async throws {
    let config = AppConfiguration()
    config.replaceDictionaryEntries(with: ["Existing"])
    let handler = CLIRequestHandler(
      config: config, persist: { _ in throw CocoaError(.fileWriteNoPermission) })
    do {
      _ = try await handler.execute(CLIRequest(operation: .dictionaryAdd, entries: ["New"]))
      XCTFail("Expected persistence failure")
    } catch {}
    XCTAssertEqual(config.voiceToTextCustomDictionary, ["Existing"])
  }

  @MainActor
  func testTranscriptionOverridesDoNotMutateSettingsAndPreserveSpeakerInformation() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("fake audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let bookmark = try url.bookmarkData(
      options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    let config = AppConfiguration()
    config.replaceDictionaryEntries(with: ["Cliptate"])
    let originalModel = config.modelVariant
    let originalLanguage = config.language
    let recorder = CLIRequestRecorder()
    let handler = CLIRequestHandler(
      config: config,
      transcribe: { request, _ in
        await recorder.record(request)
        return BatchTranscriptionOutput(
          result: TranscriptionResult(
            segments: [
              Segment(id: "segment", startTime: 0, endTime: 1, text: "Cliptate", speakerId: 2)
            ], totalDuration: 1, processingTime: 0.1, modelUsed: request.asrModel.rawValue),
          speakerAnnotationApplied: true, sourceURLBookmark: nil)
      }, ensureModel: { _, _, _ in })
    let event = try await handler.execute(
      CLIRequest(
        operation: .transcribe, bookmark: bookmark,
        model: ModelVariant.qwen3ASR.rawValue, language: "zh", useDictionary: false))
    let captured = await recorder.request
    XCTAssertEqual(captured?.asrModel, .qwen3ASR)
    XCTAssertEqual(captured?.transcriberType, .qwen3)
    XCTAssertEqual(captured?.language, .chinese)
    XCTAssertEqual(captured?.dictionaryEntries, [])
    XCTAssertEqual(event.transcript?.segments.first?.speakerId, 2)
    XCTAssertEqual(config.modelVariant, originalModel)
    XCTAssertEqual(config.language, originalLanguage)
    XCTAssertEqual(config.voiceToTextCustomDictionary, ["Cliptate"])
  }

  @MainActor
  func testInvalidModelsAndLanguagesFailBeforeInference() async throws {
    let handler = CLIRequestHandler(
      config: AppConfiguration(),
      transcribe: { _, _ in
        XCTFail("Invalid arguments must not invoke inference")
        throw CancellationError()
      }, ensureModel: { _, _, _ in XCTFail("Invalid arguments must not download") })
    for request in [
      CLIRequest(operation: .transcribe, model: "invalid"),
      CLIRequest(operation: .transcribe, model: ModelVariant.sileroVAD.rawValue),
      CLIRequest(operation: .transcribe, language: "invalid"),
    ] {
      do {
        _ = try await handler.execute(request)
        XCTFail("Expected invalid argument")
      } catch { XCTAssertTrue(error is CLIError) }
    }
  }
}

private actor CLIRequestRecorder {
  private(set) var request: BatchTranscriptionRequest?
  func record(_ request: BatchTranscriptionRequest) { self.request = request }
}

final class CLITTSRequestHandlerTests: XCTestCase {
  @MainActor
  func testSpeechUsesCapturedSettingsAndOverridesWithoutPersistingHistory() async throws {
    let config = AppConfiguration()
    let model = try XCTUnwrap(
      MLXTTSModelDefinition.availableModels.first { $0.family == .customVoice })
    config.ttsMLXModelId = model.huggingFaceRepo
    config.ttsPresetSpeaker = "Ryan"
    config.ttsEmotionPrompt = "cheerful"
    config.ttsLanguage = "en"
    config.ttsVariantPreference = .extended
    let output = try stagingOutput()
    let audio = Data("RIFF0000WAVE".utf8) + Data(repeating: 0, count: 100)
    let recorder = SpeechRecorder()
    let handler = CLIRequestHandler(
      config: config, persist: { _ in XCTFail("TTS must not persist settings") },
      synthesize: { request in
        await recorder.record(request)
        return audio
      },
      ensureModel: { variant, download, _ in
        XCTAssertEqual(variant, model.modelVariant)
        XCTAssertTrue(download)
        await MainActor.run {
          config.ttsLanguage = "ja"
          config.ttsPresetSpeaker = "Sohee"
        }
      })
    let event = try await handler.execute(
      CLIRequest(
        operation: .tts, download: true, tts: CLITTSParameters(text: "  Hello!  "),
        outputBookmark: try bookmark(output.stagingURL)))
    let captured = await recorder.request
    XCTAssertEqual(captured?.text, "Hello!")
    XCTAssertEqual(captured?.voice, "Ryan, cheerful")
    XCTAssertEqual(captured?.language, "english")
    XCTAssertEqual(captured?.variantPreference, .extended)
    XCTAssertEqual(event.audio?.model, model.id)
    XCTAssertEqual(event.audio?.bytes, audio.count)
    XCTAssertEqual(try Data(contentsOf: output.stagingURL), audio)
    XCTAssertEqual(config.ttsMLXModelId, model.huggingFaceRepo)
    XCTAssertEqual(config.ttsLanguage, "ja")

    let override = CLIRequestHandler(
      config: config,
      synthesize: { request in
        XCTAssertEqual(request.voice, "Vivian, calm")
        XCTAssertEqual(request.language, "chinese")
        XCTAssertEqual(request.variantPreference, .short)
        return audio
      }, ensureModel: { _, _, _ in })
    _ = try await override.execute(
      CLIRequest(
        operation: .tts, model: model.id, language: "zh",
        tts: CLITTSParameters(text: "你好", voice: "Vivian", emotion: "calm", variant: "short"),
        outputBookmark: try bookmark(output.stagingURL)))
    XCTAssertEqual(config.ttsPresetSpeaker, "Sohee")
    XCTAssertEqual(config.ttsVariantPreference, .extended)
  }

  @MainActor
  func testVoiceDesignAndBaseDefaultsUseOnlyApplicableSettings() async throws {
    let config = AppConfiguration()
    config.ttsVoiceDescription = "A calm narrator"
    config.ttsPresetSpeaker = "Ryan"
    config.ttsReferenceAudioPath = "/missing/gui-reference.wav"
    config.ttsReferenceText = "GUI reference"
    let output = try stagingOutput()
    let destination = try bookmark(output.stagingURL)
    for family in [TTSModelFamily.base, .voiceDesign] {
      let model = try XCTUnwrap(MLXTTSModelDefinition.availableModels.first { $0.family == family })
      let handler = CLIRequestHandler(
        config: config,
        synthesize: { request in
          XCTAssertEqual(request.voice, family == .voiceDesign ? "A calm narrator" : nil)
          XCTAssertNil(request.referenceAudioURL)
          XCTAssertNil(request.referenceText)
          return Data("audio".utf8)
        }, ensureModel: { _, _, _ in })
      _ = try await handler.execute(
        CLIRequest(
          operation: .tts, model: model.huggingFaceRepo, tts: CLITTSParameters(text: "Hello"),
          outputBookmark: destination))
    }
  }

  @MainActor
  func testCloneTransfersReadableReferenceAndRequiresBaseModel() async throws {
    let config = AppConfiguration()
    let model = try XCTUnwrap(MLXTTSModelDefinition.availableModels.first { $0.family == .base })
    let output = try stagingOutput()
    let reference = output.stagingURL.deletingLastPathComponent().appendingPathComponent("ref.wav")
    try Data("reference".utf8).write(to: reference)
    let handler = CLIRequestHandler(
      config: config,
      synthesize: { request in
        XCTAssertNil(request.voice)
        XCTAssertEqual(
          request.referenceAudioURL?.resolvingSymlinksInPath(), reference.resolvingSymlinksInPath())
        XCTAssertEqual(request.referenceText, "reference transcript")
        return Data("audio".utf8)
      }, ensureModel: { _, _, _ in })
    _ = try await handler.execute(
      CLIRequest(
        operation: .tts, bookmark: try bookmark(reference), model: model.id,
        tts: CLITTSParameters(text: "Hello", referenceText: "reference transcript"),
        outputBookmark: try bookmark(output.stagingURL)))
  }

  @MainActor
  func testInvalidSpeechOptionsFailBeforeDownloadsOrInference() async throws {
    let handler = CLIRequestHandler(
      config: AppConfiguration(),
      synthesize: { _ in
        XCTFail("Invalid options must not synthesize")
        throw CancellationError()
      }, ensureModel: { _, _, _ in XCTFail("Invalid options must not download") })
    let base = try XCTUnwrap(MLXTTSModelDefinition.availableModels.first { $0.family == .base })
    let custom = try XCTUnwrap(
      MLXTTSModelDefinition.availableModels.first { $0.family == .customVoice })
    let design = try XCTUnwrap(
      MLXTTSModelDefinition.availableModels.first { $0.family == .voiceDesign })
    let output = try stagingOutput()
    let destination = try bookmark(output.stagingURL)
    let invalid: [CLIRequest] = [
      CLIRequest(
        operation: .tts, model: "invalid", tts: CLITTSParameters(text: "Hello"),
        outputBookmark: destination),
      CLIRequest(
        operation: .tts, language: "invalid", tts: CLITTSParameters(text: "Hello"),
        outputBookmark: destination),
      CLIRequest(
        operation: .tts, model: base.id, tts: CLITTSParameters(text: "Hello", voice: "Ryan"),
        outputBookmark: destination),
      CLIRequest(
        operation: .tts, model: custom.id, tts: CLITTSParameters(text: "Hello", voice: "Nobody"),
        outputBookmark: destination),
      CLIRequest(
        operation: .tts, model: design.id, tts: CLITTSParameters(text: "Hello", emotion: "calm"),
        outputBookmark: destination),
      CLIRequest(
        operation: .tts, bookmark: destination, model: custom.id,
        tts: CLITTSParameters(text: "Hello", referenceText: "reference"),
        outputBookmark: destination),
      CLIRequest(
        operation: .tts, bookmark: destination, model: base.id,
        tts: CLITTSParameters(text: "Hello"), outputBookmark: destination),
      CLIRequest(operation: .tts, tts: CLITTSParameters(text: " "), outputBookmark: destination),
      CLIRequest(operation: .tts, tts: CLITTSParameters(text: "Hello")),
    ]
    for request in invalid {
      do {
        _ = try await handler.execute(request)
        XCTFail("Expected rejection")
      } catch { XCTAssertTrue(error is CLIError) }
    }
  }

  @MainActor
  func testModelFailureAndCancellationLeaveStagingUnwritten() async throws {
    let output = try stagingOutput()
    let request = CLIRequest(
      operation: .tts, tts: CLITTSParameters(text: "Hello"),
      outputBookmark: try bookmark(output.stagingURL))
    let missing = CLIRequestHandler(
      config: AppConfiguration(),
      synthesize: { _ in
        XCTFail("Missing model must not synthesize")
        return Data()
      }, ensureModel: { _, _, _ in throw CLIError("Model missing") })
    do {
      _ = try await missing.execute(request)
      XCTFail("Expected missing model")
    } catch {}
    let cancelled = CLIRequestHandler(
      config: AppConfiguration(), synthesize: { _ in throw CancellationError() },
      ensureModel: { _, _, _ in })
    do {
      _ = try await cancelled.execute(request)
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(try Data(contentsOf: output.stagingURL), Data())
  }

  private func stagingOutput() throws -> CLITTSOutput {
    try CLITTSOutput(
      destination: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".wav"), inputs: [], overwrite: false)
  }
  private func bookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
  }
}

private actor SpeechRecorder {
  private(set) var request: CLISpeechRequest?
  func record(_ request: CLISpeechRequest) { self.request = request }
}
