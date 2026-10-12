import XCTest

@testable import Cliptate

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

final class CLICommandTests: XCTestCase {
  func testOptionsAndDashPrefixedPaths() throws {
    let command = try CLICommand.parse([
      "transcribe", "a.mp3", "--format", "json", "--language", "zh", "--no-dictionary", "--",
      "-b.wav",
    ])
    guard case .transcribe(let options) = command else { return XCTFail("Expected transcription") }
    XCTAssertEqual(options.files, ["a.mp3", "-b.wav"])
    XCTAssertEqual(options.format, .json)
    XCTAssertEqual(options.language, "zh")
    XCTAssertFalse(options.useDictionary)
  }

  func testRejectsAmbiguousSubtitleAndOutputArguments() {
    for arguments in [
      ["transcribe", "a.wav", "b.wav", "-f", "srt"],
      ["transcribe", "a.wav", "b.wav", "--output", "out.txt"],
      ["transcribe", "a.wav", "--output", "a.txt", "--output-dir", "."],
      ["transcribe", "a.wav", "--language"],
      ["transcribe", "a.wav", "--language", "--format", "json"],
      ["dictionary", "add"],
      ["dictionary", "list", "unexpected"],
      ["transcribe", "a.wav", "--speakers"],
    ] {
      XCTAssertThrowsError(try CLICommand.parse(arguments), "\(arguments)")
    }
  }

  func testDictionaryImportIsStrictUTF8AndJSON() throws {
    XCTAssertEqual(
      try CLICommand.importEntries(Data("\u{FEFF}Alpha\r\nBeta\n".utf8)), ["Alpha", "Beta", ""])
    XCTAssertEqual(
      try CLICommand.importEntries(Data("[\"Alpha\",\"Beta\"]".utf8)), ["Alpha", "Beta"])
    XCTAssertThrowsError(try CLICommand.importEntries(Data("[123]".utf8)))
    XCTAssertThrowsError(try CLICommand.importEntries(Data("{}".utf8), json: true))
    XCTAssertThrowsError(try CLICommand.importEntries(Data([0xff])))
  }

  func testSubtitleTimestampCarryAndVTTHeader() throws {
    let file = CLIFileResult(
      file: "a.wav", model: "test", duration: 2,
      segments: [
        CLISegment(id: "1", text: "你好", start: 59.9996, end: 61, speakerId: 2)
      ])
    let srt = try CLIOutput.render(file, format: .srt)
    XCTAssertTrue(srt.contains("00:01:00,000 --> 00:01:01,000"))
    XCTAssertTrue(srt.contains("你好"))
    let vtt = try CLIOutput.render(file, format: .vtt)
    XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n"))
    XCTAssertTrue(vtt.contains("00:01:00.000"))
    XCTAssertEqual(try CLIOutput.render(file, format: .text), "你好\n")
  }

  func testJSONIncludesFailuresAndSpeakerIDs() throws {
    let files = [
      CLIFileResult(
        file: "a.wav", model: "test", duration: 2,
        segments: [
          CLISegment(id: "1", text: "Hello", start: 0, end: 2, speakerId: 1)
        ]), CLIFileResult(file: "missing.wav", error: "missing"),
    ]
    let data = try CLIOutput.json(files)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let decoded = try XCTUnwrap(object["files"] as? [[String: Any]])
    XCTAssertEqual(decoded.count, 2)
    XCTAssertEqual(decoded[1]["error"] as? String, "missing")
    let segments = try XCTUnwrap(decoded[0]["segments"] as? [[String: Any]])
    XCTAssertEqual(segments[0]["speakerId"] as? Int, 1)
  }
}

final class CLITTSCommandTests: XCTestCase {
  func testParsesAllTTSOverridesAndStdin() throws {
    guard
      case .tts(let options) = try CLICommand.parse([
        "tts", "--text-file", "-", "-o", "out.wav", "--tts-model", "model",
        "--language", "zh", "--voice", "Ryan", "--emotion", "cheerful",
        "--variant", "extended", "--format", "json", "--download", "--overwrite",
      ])
    else { return XCTFail("Expected TTS") }
    XCTAssertEqual(options.textFile, "-")
    XCTAssertEqual(options.model, "model")
    XCTAssertEqual(options.voice, "Ryan")
    XCTAssertEqual(options.emotion, "cheerful")
    XCTAssertEqual(options.variant, "extended")
    XCTAssertTrue(options.json && options.download && options.overwrite)
  }

  func testRejectsInvalidOrAmbiguousTTSArguments() {
    for tail in [
      [], ["--text", "hello"], ["-o", "out.wav"],
      ["--text", "hello", "--text-file", "a.txt", "-o", "out.wav"],
      ["--text", " \n", "-o", "out.wav"],
      ["--text", "hello", "-o", "out.mp3"],
      ["--text", "hello", "-o", "-"],
      ["--text", "hello", "-o", "out.wav", "--variant", "fast"],
      ["--text", "hello", "-o", "out.wav", "--format", "text"],
      ["--text", "hello", "-o", "out.wav", "--output", "other.wav"],
      ["--text", "hello", "-o", "out.wav", "--reference-audio", "ref.wav"],
      ["--text", "hello", "-o", "out.wav", "--reference-text", "reference"],
      [
        "--text", "hello", "-o", "out.wav", "--reference-audio", "ref.wav", "--reference-text", " ",
      ],
      [
        "--text", "hello", "-o", "out.wav", "--reference-audio", "ref.wav", "--reference-text",
        "reference", "--voice", "Ryan",
      ],
    ] { XCTAssertThrowsError(try CLICommand.parse(["tts"] + tail), "\(tail)") }
    XCTAssertNoThrow(try CLICommand.parse(["tts", "--help"]))
  }

  func testTextIsStrictUTF8NonemptyAndBounded() throws {
    XCTAssertEqual(try CLITTSOptions.validatedText(Data("\u{FEFF}  你好\n世界\n".utf8)), "你好\n世界")
    XCTAssertThrowsError(try CLITTSOptions.validatedText(Data([0xff])))
    XCTAssertThrowsError(try CLITTSOptions.validatedText(Data("\n \t".utf8)))
    XCTAssertThrowsError(try CLITTSOptions.validatedText(Data(repeating: 65, count: 1_048_577)))
  }

  func testPublishesLargeAudioWithoutFramingItAndCleansStagingDirectory() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let destination = dir.appendingPathComponent("out.wav")
    let staging: URL
    do {
      let output = try CLITTSOutput(destination: destination, inputs: [], overwrite: false)
      staging = output.stagingURL
      var audio = Data("RIFF0000WAVE".utf8)
      audio.append(Data(repeating: 0, count: 17 * 1_048_576))
      try audio.write(to: staging)
      try output.publish(expectedBytes: audio.count)
      XCTAssertEqual(try Data(contentsOf: destination), audio)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: staging.deletingLastPathComponent().path))
  }

  func testOutputProtectsInputsExistingFilesAndCreationRaces() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let dest = dir.appendingPathComponent("out.wav")
    let original = Data("original".utf8)
    try original.write(to: dest)
    XCTAssertThrowsError(try CLITTSOutput(destination: dest, inputs: [dest], overwrite: true))
    let alias = dir.appendingPathComponent("alias.wav")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dest)
    XCTAssertThrowsError(try CLITTSOutput(destination: alias, inputs: [dest], overwrite: true))
    XCTAssertThrowsError(try CLITTSOutput(destination: dest, inputs: [], overwrite: false))
    do {
      let output = try CLITTSOutput(destination: dest, inputs: [], overwrite: true)
      try Data("invalid".utf8).write(to: output.stagingURL)
      XCTAssertThrowsError(try output.publish(expectedBytes: 7))
    }
    XCTAssertEqual(try Data(contentsOf: dest), original)
    try FileManager.default.removeItem(at: dest)
    let output = try CLITTSOutput(destination: dest, inputs: [], overwrite: false)
    let audio = Data("RIFF0000WAVE".utf8) + Data(repeating: 0, count: 100)
    try audio.write(to: output.stagingURL)
    try original.write(to: dest)
    XCTAssertThrowsError(try output.publish(expectedBytes: audio.count))
    XCTAssertEqual(try Data(contentsOf: dest), original)
    let replacing = try CLITTSOutput(destination: dest, inputs: [], overwrite: true)
    try audio.write(to: replacing.stagingURL)
    try replacing.publish(expectedBytes: audio.count)
    XCTAssertEqual(try Data(contentsOf: dest), audio)
  }

  func testOldRequestsRemainDecodableAndTTSRoundTrips() throws {
    let old = Data(
      #"{"operation":"dictionaryList","useDictionary":true,"download":false,"entries":[]}"#.utf8)
    XCTAssertNil(try JSONDecoder().decode(CLIRequest.self, from: old).tts)
    XCTAssertNil(try JSONDecoder().decode(CLIRequest.self, from: old).history)
    let request = CLIRequest(
      operation: .tts, tts: CLITTSParameters(text: "你好", voice: "Ryan"),
      outputBookmark: Data([1, 2]))
    let decoded = try JSONDecoder().decode(CLIRequest.self, from: CLIOutput.encode(request))
    XCTAssertEqual(decoded.tts?.text, "你好")
    XCTAssertEqual(decoded.outputBookmark, Data([1, 2]))
  }
}
