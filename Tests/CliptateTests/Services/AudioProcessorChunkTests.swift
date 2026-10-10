import Foundation
import Testing

@testable import Cliptate

@Suite("AudioProcessor chunk helpers")
struct AudioProcessorChunkTests {
  @Test("extractSamples returns exact window at 16kHz")
  func extractSamplesWindow() {
    let samples = Array(0..<32_000).map(Float.init)
    let chunk = AudioProcessor.extractSamples(
      samples: samples,
      startTime: 0.5,
      endTime: 1.0,
      sampleRate: 16_000
    )

    #expect(chunk.count == 8_000)
    #expect(chunk.first == samples[8_000])
  }

  @Test("loadAndConvertAudio returns non-empty float samples for WAV")
  func loadAndConvertAudioReturnsFloatSamples() async throws {
    guard let url = Bundle.module.url(forResource: "Resources/vad_example", withExtension: "wav")
      ?? Bundle.module.resourceURL?.appendingPathComponent("Resources/vad_example.wav"),
      FileManager.default.fileExists(atPath: url.path) else {
      Issue.record("vad_example.wav not found in test resources")
      return
    }
    let samples = try await AudioProcessor.loadAndConvertAudio(url: url)
    #expect(!samples.isEmpty)
    #expect(samples.count > 1_000)
  }

  @Test("ASS exports include a UTF-8 BOM so external readers preserve CJK text")
  func assExportIncludesUTF8BOM() throws {
    let segment = Segment(startTime: 1.0, endTime: 3.5, text: "你好，世界")
    let media = MediaFile(
      url: URL(fileURLWithPath: "/tmp/My Audio.m4a"),
      segments: [segment],
      duration: 4,
      effects: [:],
      translationPlacement: .below,
      styleConfiguration: defaultSubtitleStyles
    )

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString
    )
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try SubtitleFileExporter.export(
      mediaFiles: [media],
      formats: [.ass],
      directory: tempDirectory,
      filterSilentSegments: false
    )

    let assURL = tempDirectory.appendingPathComponent("My_Audio").appendingPathExtension("ass")
    let data = try Data(contentsOf: assURL)

    #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))

    let decoded = String(data: data.dropFirst(3), encoding: .utf8)
    #expect(decoded?.contains("你好，世界") == true)
  }
}
