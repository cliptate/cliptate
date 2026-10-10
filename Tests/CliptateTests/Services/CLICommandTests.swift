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
