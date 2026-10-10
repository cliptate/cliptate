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
