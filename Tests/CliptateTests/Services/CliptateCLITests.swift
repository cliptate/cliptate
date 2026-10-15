import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("cliptate-cli")
struct CliptateCLITests {
  @Test("cut uses transcript JSON to write selected output files")
  func cutUsesTranscriptJSONToWriteSelectedOutputs() async throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let videoURL = tempDir.appendingPathComponent("interview.mp4")
    FileManager.default.createFile(atPath: videoURL.path, contents: Data())

    let transcriptURL = tempDir.appendingPathComponent("provided.json")
    try """
      {
        "title": "Launch Notes",
        "subtitle": "Demo",
        "translation": {
          "source_lang": "en",
          "target_lang": "zh"
        },
        "segments": [
          {
            "start": 0.5,
            "end": 2.0,
            "text": "Hello world",
            "translation": "你好世界",
            "words": [
              {"word": "Hello", "start": 0.5, "end": 1.0},
              {"word": "world", "start": 1.0, "end": 2.0}
            ]
          }
        ]
      }
      """.write(to: transcriptURL, atomically: true, encoding: .utf8)

    let outputDir = tempDir.appendingPathComponent("out")
    let dependencies = CliptateCLI.Dependencies(
      transcribe: { _ in
        Issue.record("transcript input should skip ASR")
        return CliptateCLI.CutTranscription(
          segments: [],
          duration: 0,
          modelUsed: "unexpected"
        )
      },
      synthesize: { _ in Data() },
      renderVideo: { _, _, _, _, _, _, _ in
        Issue.record("video rendering should not run unless video format is selected")
      }
    )

    let result = try await CliptateCLI.run(
      arguments: [
        "cut",
        "--transcript", transcriptURL.path,
        "--translate",
        "--margin-left", "0",
        "--margin-right", "0",
        "--format", "json,txt,srt,ass,fcpxml",
        "--output-dir", outputDir.path,
        videoURL.path,
      ],
      dependencies: dependencies
    )

    #expect(result.exitCode == 0)
    #expect(result.outputs.count == 1)
    let outputs = try #require(result.outputs[videoURL.path])
    #expect(outputs["transcript"]?.lastPathComponent == "interview_transcript.json")
    #expect(outputs["txt"]?.lastPathComponent == "interview.txt")
    #expect(outputs["srt"]?.lastPathComponent == "interview_subtitles.srt")
    #expect(outputs["ass"]?.lastPathComponent == "interview_subtitles.ass")
    #expect(outputs["fcpxml"]?.lastPathComponent == "interview.fcpxml")

    for url in outputs.values {
      #expect(FileManager.default.fileExists(atPath: url.path))
    }

    let srt = try String(contentsOf: try #require(outputs["srt"]), encoding: .utf8)
    #expect(srt.contains("00:00:00,500 --> 00:00:02,000"))
    #expect(srt.contains("Hello world"))
    #expect(srt.contains("你好世界"))

    let txt = try String(contentsOf: try #require(outputs["txt"]), encoding: .utf8)
    #expect(txt.contains("[00:00.500 - 00:02.000] Hello world"))
    #expect(txt.contains("你好世界"))

    let copiedJSON = try String(contentsOf: try #require(outputs["transcript"]), encoding: .utf8)
    #expect(copiedJSON.contains(#""segments""#))
    #expect(copiedJSON.contains(#""translation""#))
  }

  @Test("tts writes synthesized audio to requested output")
  func ttsWritesSynthesizedAudioToRequestedOutput() async throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let outputURL = tempDir.appendingPathComponent("speech.wav")
    let expectedAudio = Data([0x52, 0x49, 0x46, 0x46])
    let dependencies = CliptateCLI.Dependencies(
      transcribe: { _ in
        CliptateCLI.CutTranscription(segments: [], duration: 0, modelUsed: "unused")
      },
      synthesize: { request in
        #expect(request.text == "Hello from CLI")
        #expect(request.outputURL == outputURL)
        #expect(request.voice == "Ryan")
        return expectedAudio
      },
      renderVideo: { _, _, _, _, _, _, _ in }
    )

    let result = try await CliptateCLI.run(
      arguments: [
        "tts",
        "--text", "Hello from CLI",
        "--voice", "Ryan",
        "-o", outputURL.path,
      ],
      dependencies: dependencies
    )

    #expect(result.exitCode == 0)
    #expect(result.outputs["tts"]?["audio"] == outputURL)
    #expect(try Data(contentsOf: outputURL) == expectedAudio)
  }

  @Test("format parser rejects unsupported cut formats")
  func rejectsUnsupportedCutFormats() async throws {
    do {
      _ = try await CliptateCLI.run(arguments: ["cut", "--format", "srt,pdf", "video.mp4"])
      Issue.record("unsupported format should fail")
    } catch let error as CliptateCLI.CLIError {
      #expect(error.description.contains("unsupported format 'pdf'"))
    }
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cliptate-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
