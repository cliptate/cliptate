//
//  CliptateTests.swift
//  CliptateTests
//
//  Created by 大可 on 2025/8/9.
//

import CoreGraphics
import Foundation
import Testing

@testable import Cliptate

struct CliptateTests {
  @Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
  }
}

struct FCPXMLExporterOrientationTests {
  @Test
  func portraitUsesCompactFontAndRaisedPosition() async throws {
    let segment = Segment(startTime: 0, endTime: 2, text: "Portrait line")
    let portraitMedia = MediaFile(
      url: URL(fileURLWithPath: "/tmp/portrait.mov"),
      segments: [segment],
      duration: 2,
      presentationSize: CGSize(width: 1080, height: 1920)
    )

    let xml = FCPXMLExporter.exportFCPXML(
      mediaFiles: [portraitMedia],
      settings: FCPXMLExportSettings()
    )

    #expect(xml.contains("fontSize=\"48\""))
    #expect(xml.contains("position=\"0 -22\""))
  }

  @Test
  func landscapeKeepsDefaultFontAndPosition() async throws {
    let segment = Segment(startTime: 0, endTime: 2, text: "Landscape line")
    let landscapeMedia = MediaFile(
      url: URL(fileURLWithPath: "/tmp/landscape.mov"),
      segments: [segment],
      duration: 2,
      presentationSize: CGSize(width: 1920, height: 1080)
    )

    let xml = FCPXMLExporter.exportFCPXML(
      mediaFiles: [landscapeMedia],
      settings: FCPXMLExportSettings()
    )

    #expect(xml.contains("fontSize=\"55\""))
    #expect(xml.contains("position=\"0 -33\""))
  }

}

struct SubtitleStylePresetTests {
  @Test
  func defaultStylesMapToPresets() async throws {
    let defaults = defaultSubtitleStyles.landscape
    #expect(defaults.primary.matchedPreset() == .whiteOnBlackOutline)
    #expect(defaults.translation.matchedPreset() == .orangeOnBlackOutline)
    #expect(defaults.highlight.matchedPreset() == .yellowOnBlackOutline)
  }
}

struct VideoOrientationLayoutTests {
  @Test
  func portraitVideoCropsWhenForcingLandscape() async throws {
    let layout = VideoOrientationLayout.layout(
      for: CGSize(width: 1080, height: 1920),
      targetOrientation: .landscape
    )

    let epsilon: CGFloat = 0.0001

    #expect(layout.canvasSize.width > layout.canvasSize.height)
    #expect(layout.scale < 1)
    #expect(abs(layout.scale - 0.5625) < epsilon)
    #expect(abs(layout.scaledVideoSize.height - layout.canvasSize.height) < epsilon)
    #expect(layout.scaledVideoSize.width < layout.canvasSize.width)
    #expect(layout.offset.x > 0)
    #expect(abs(layout.offset.y) < epsilon)
  }

  @Test
  func landscapeVideoCropsWhenForcingPortrait() async throws {
    let layout = VideoOrientationLayout.layout(
      for: CGSize(width: 1920, height: 1080),
      targetOrientation: .portrait
    )

    let epsilon: CGFloat = 0.0001

    #expect(layout.canvasSize.height > layout.canvasSize.width)
    #expect(layout.scale < 1)
    #expect(abs(layout.scale - 0.5625) < epsilon)
    #expect(abs(layout.scaledVideoSize.width - layout.canvasSize.width) < epsilon)
    #expect(layout.scaledVideoSize.height < layout.canvasSize.height)
    #expect(layout.offset.y > 0)
    #expect(abs(layout.offset.x) < epsilon)
  }
}

struct SubtitleFileExporterTests {
  @Test
  func writesSelectedFormatsWithTranslations() async throws {
    var segment = Segment(startTime: 1.0, endTime: 3.5, text: "Hello world")
    segment.translation = SegmentTranslation(text: "你好，世界", language: .chinese)
    let media = MediaFile(
      url: URL(fileURLWithPath: "/tmp/My Video.mov"),
      segments: [segment],
      duration: 4,
      effects: [:],
      translationPlacement: .below,
      styleConfiguration: defaultSubtitleStyles
    )

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try SubtitleFileExporter.export(
      mediaFiles: [media],
      formats: [.srt, .txt],
      directory: tempDirectory,
      filterSilentSegments: false
    )

    let basename = tempDirectory.appendingPathComponent("My_Video")
    let srt = try String(contentsOf: basename.appendingPathExtension("srt"))
    let txt = try String(contentsOf: basename.appendingPathExtension("txt"))

    #expect(srt.contains("Hello world"))
    #expect(srt.contains("你好，世界"))
    #expect(srt.contains("00:00:01,000 --> 00:00:03,500"))

    #expect(txt.contains("[00:01.000 - 00:03.500] Hello world"))
    #expect(txt.contains("↳ 你好，世界"))
  }
}

struct SegmentSplitBySentenceCommaTests {
  @Test
  func splitsOnCommaPunctuation() async throws {
    let words = [
      WordTiming(word: "你好", startTime: 0.0, endTime: 0.3, punctuation: "，"),
      WordTiming(word: "世界", startTime: 0.31, endTime: 0.7, punctuation: "。"),
    ]
    let segment = Segment(startTime: 0, endTime: 0.7, text: "你好，世界。", words: words)

    let output = SegmentSplitBySentence.apply(segments: [segment])

    #expect(output.count == 2)
    #expect(output[0].text == "你好，")
    #expect(output[1].text == "世界。")
  }
}

struct ExportTextNormalizerTests {
  @Test
  func removesPunctuationForOriginalAndTranslation() async throws {
    var segment = Segment(startTime: 0, endTime: 1, text: "Hello, world!")
    segment.translation = SegmentTranslation(text: "你好，世界！", language: .chinese)

    let normalizedSegments = ExportTextNormalizer.normalize(segments: [segment], keepPunctuation: false)

    #expect(normalizedSegments.first?.text == "Hello world")
    #expect(normalizedSegments.first?.translation?.text == "你好世界")
  }
}

struct SegmentEffectConfigurationParsingTests {
  @Test
  func parsesMultilineFillerWords() async throws {
    let parsed = SegmentEffectConfiguration.parseFillerWords(from: "uh\num\n嗯")
    #expect(parsed == ["uh", "um", "嗯"])
  }
}

struct ConfigPresetPayloadEncodingTests {
  @Test
  func fcpxmlEnabledRoundTripsThroughCodable() async throws {
    let payload = ConfigPreset.Payload(
      transcriberType: .parakeet,
      modelVariant: .parakeetV3,
      language: .english,
      leftPadMs: 120,
      rightPadMs: 150,
      splitBySentence: true,
      maxCharsPerSegment: 42,
      filterSilent: true,
      ttsEngine: .qwen3TTS,
      ttsVariantPreference: .automatic,
      ttsSpeakingRate: 1.0,
      fcpxmlProjectName: "Sample",
      fcpxmlEnabled: false,
      fcpxmlFrameRate: 24,
      fcpxmlIncludeSubtitles: false,
      fcpxmlIsResolveCompatible: false,
      exportMode: .merge,
      videoExportEnabled: true,
      videoExportFormat: .mp4,
      videoExportBurnInSubtitles: false,
      keepPunctuationOnExport: false,
      videoExportQuality: .medium,
      audioExportEnabled: true,
      audioExportFormat: .wav,
      effectExtractHighlights: false,
      effectEnableScaling: false,
      effectScaleMultiplier: 1.4,
      effectEnableZoom: false,
      effectZoomMultiplier: 1.5,
      effectFilterFillerWords: false,
      effectFillerWords: ["uh", "um"],
      translationPlacement: .above,
      translationTargetLanguage: .chinese,
      subtitleStyles: defaultSubtitleStyles,
      subtitleExportFormats: [.srt],
      aiProviderKeys: [:],
      selectedAIProvider: .openai,
      aiEnabled: false
    )

    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(ConfigPreset.Payload.self, from: data)

    #expect(decoded.fcpxmlEnabled == false)
    #expect(decoded.exportMode == .merge)
    #expect(decoded.videoExportEnabled == true)
    #expect(decoded.videoExportFormat == .mp4)
    #expect(decoded.keepPunctuationOnExport == false)
    #expect(decoded.videoExportQuality == .parakeetV2)
    #expect(decoded.audioExportEnabled == true)
    #expect(decoded.audioExportFormat == .wav)
    #expect(decoded.aiOpenAIEndpoint == AppConfiguration.defaultOpenAIEndpoint)
    #expect(decoded.aiDefaultCorrectionPrompt.isEmpty)
    #expect(decoded.aiDefaultEnhancePrompt.isEmpty)
    #expect(decoded.aiProviderModels == AIProvider.defaultModelMap)
  }
}

struct ExportRequestDefaultsTests {
  @Test
  @MainActor
  func reflectsConfigurationState() async throws {
    let config = AppConfiguration.shared
    let originalFCPXMLEnabled = config.fcpxmlEnabled
    let originalFormats = config.subtitleExportFormats
    let originalVideoEnabled = config.videoExportEnabled
    let originalVideoQuality = config.videoExportQuality
    let originalAudioEnabled = config.audioExportEnabled
    let originalAudioFormat = config.audioExportFormat
    defer {
      config.fcpxmlEnabled = originalFCPXMLEnabled
      config.subtitleExportFormats = originalFormats
      config.videoExportEnabled = originalVideoEnabled
      config.videoExportQuality = originalVideoQuality
      config.audioExportEnabled = originalAudioEnabled
      config.audioExportFormat = originalAudioFormat
    }

    config.fcpxmlEnabled = false
    config.subtitleExportFormats = []
    config.videoExportEnabled = true
    config.videoExportBurnInSubtitles = false
    config.videoExportQuality = .high
    config.audioExportEnabled = true
    config.audioExportFormat = .wav

    let request = config.defaultExportRequest()
    #expect(request.includeFCPXML == false)
    #expect(request.includeSubtitleFiles == false)
    #expect(request.includeVideos == true)
    #expect(request.includeAudio == true)
    #expect(request.burnSubtitlesIntoVideo == false)
    #expect(request.videoQuality == .high)
    #expect(request.audioFormat == .wav)
  }
}
