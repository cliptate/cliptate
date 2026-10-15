import CliptateCore
import CoreGraphics
import Foundation
import Testing

@testable import Cliptate

@Suite("Segment speakerId")
struct SegmentSpeakerIdTests {
  @Test("speakerId defaults to nil")
  func speakerIdDefaultsToNil() {
    let seg = Segment(startTime: 0.0, endTime: 1.0, text: "hello")
    #expect(seg.speakerId == nil)
  }

  @Test("speakerId is stored and returned")
  func speakerIdIsStored() {
    let seg = Segment(startTime: 0.0, endTime: 1.0, text: "hello", speakerId: 2)
    #expect(seg.speakerId == 2)
  }

  @Test("Segment with speakerId encodes and decodes correctly")
  func speakerIdRoundTrips() throws {
    let original = Segment(startTime: 1.0, endTime: 3.0, text: "test", speakerId: 1)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Segment.self, from: data)
    #expect(decoded.speakerId == 1)
  }

  @Test("Segment without speakerId decodes from legacy JSON with nil speakerId")
  func legacyJsonDecodesWithNilSpeakerId() throws {
    let json = #"{"startTime":0.5,"endTime":1.5,"text":"hi"}"#
    let decoded = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
    #expect(decoded.speakerId == nil)
    #expect(decoded.text == "hi")
  }
}

@Suite("Segment UUID identity")
struct SegmentUUIDTests {
  @Test("id is a stable UUID string, not derived from timing")
  func idIsStableUUID() {
    let seg = Segment(startTime: 1.0, endTime: 2.0, text: "hello")
    // UUID format: 8-4-4-4-12 hex chars
    let uuidPattern = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/
    #expect(seg.id.uppercased().contains(where: { _ in true }))
    #expect(seg.id.uppercased().wholeMatch(of: uuidPattern) != nil,
            "id should be a valid UUID, got: \(seg.id)")
    // Must NOT be the old computed format
    #expect(seg.id != "\(seg.startTime)-\(seg.endTime)")
  }

  @Test("two segments with same timing get different UUIDs")
  func twoSegmentsGetDifferentUUIDs() {
    let a = Segment(startTime: 0, endTime: 1, text: "a")
    let b = Segment(startTime: 0, endTime: 1, text: "a")
    #expect(a.id != b.id)
  }

  @Test("UUID round-trips through Codable")
  func uuidRoundTrips() throws {
    let original = Segment(startTime: 1.0, endTime: 2.0, text: "test")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Segment.self, from: data)
    #expect(decoded.id == original.id)
  }

  @Test("legacy JSON without id field decodes with a generated UUID")
  func legacyJsonGetsGeneratedUUID() throws {
    let json = #"{"startTime":0.5,"endTime":1.5,"text":"hi"}"#
    let decoded = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
    #expect(!decoded.id.isEmpty)
    #expect(decoded.id != "0.5-1.5", "Should not fall back to old computed id format")
  }

  @Test("Equatable ignores id — same content with different UUIDs are equal")
  func equatableIgnoresId() {
    let a = Segment(startTime: 0, endTime: 1, text: "hello")
    let b = Segment(startTime: 0, endTime: 1, text: "hello")
    // Different UUIDs, but should be equal by content
    #expect(a.id != b.id)
    #expect(a == b)
  }

  @Test("explicit id is preserved through init")
  func explicitIdPreserved() {
    let customId = UUID().uuidString
    let seg = Segment(id: customId, startTime: 0, endTime: 1, text: "test")
    #expect(seg.id == customId)
  }
}

@Suite("Segment embedded translation")
struct SegmentTranslationEmbedTests {
  @Test("translation defaults to nil")
  func translationDefaultsToNil() {
    let seg = Segment(startTime: 0, endTime: 1, text: "hello")
    #expect(seg.translation == nil)
  }

  @Test("translation can be set via init")
  func translationCanBeSet() {
    let t = SegmentTranslation(text: "你好", language: .chinese)
    let seg = Segment(startTime: 0, endTime: 1, text: "hello", translation: t)
    #expect(seg.translation?.text == "你好")
    #expect(seg.translation?.language == .chinese)
  }

  @Test("translation round-trips through Codable")
  func translationCodableRoundTrip() throws {
    let t = SegmentTranslation(text: "你好", language: .chinese)
    let original = Segment(startTime: 0, endTime: 1, text: "hello", translation: t)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Segment.self, from: data)
    #expect(decoded.translation?.text == "你好")
  }

  @Test("Equatable includes translation — different translations are not equal")
  func equatableIncludesTranslation() {
    let a = Segment(startTime: 0, endTime: 1, text: "hello",
                    translation: SegmentTranslation(text: "你好", language: .chinese))
    let b = Segment(startTime: 0, endTime: 1, text: "hello")
    #expect(a != b, "Translation difference should affect equality")
  }

  @Test("Equatable treats identical translations as equal")
  func equatableSameTranslation() {
    let t = SegmentTranslation(text: "你好", language: .chinese)
    let a = Segment(startTime: 0, endTime: 1, text: "hello", translation: t)
    let b = Segment(startTime: 0, endTime: 1, text: "hello", translation: t)
    #expect(a == b)
  }

  @Test("Equatable treats both-nil translations as equal")
  func equatableNilTranslations() {
    let a = Segment(startTime: 0, endTime: 1, text: "hello")
    let b = Segment(startTime: 0, endTime: 1, text: "hello")
    #expect(a == b)
  }
}

@Suite("Speaker badge helpers")
struct SpeakerBadgeTests {
  @Test("speakerBadgeText returns 1-indexed label")
  func speakerBadgeTextIsOneIndexed() {
    #expect(speakerBadgeText(id: 0) == "S1")
    #expect(speakerBadgeText(id: 3) == "S4")
    #expect(speakerBadgeText(id: 7) == "S8")
  }

  @Test("speakerBadgeColor wraps at palette boundary")
  func speakerBadgeColorWraps() {
    let color0 = speakerBadgeColor(id: 0)
    let color8 = speakerBadgeColor(id: 8)
    #expect(color0 == color8)
  }

  @Test("speakerBadgeColor returns distinct colors for first 8 speakers")
  func speakerBadgeColorDistinct() {
    let colors = (0..<8).map { speakerBadgeColor(id: $0) }
    let unique = Set(colors.map { "\($0)" })
    #expect(unique.count == 8, "All 8 speaker colors should be distinct")
  }
}

@Suite("Subtitle preview mode")
struct SubtitlePreviewModeTests {
  @Test("audio-only previews use manual subtitle synchronization")
  func audioOnlyPreviewUsesManualSynchronization() {
    #expect(SubtitlePreviewMode.resolve(hasVideoTrack: false) == .nativeTextOverlay)
  }
}

@Suite("Subtitle canvas scaling")
struct VideoCanvasScalingTests {
  // Verifies that the display canvas size scales proportionally with the container.
  // This is the invariant that ASS subtitle rendering relies on: as the container grows,
  // canvasSize (= layout.canvasSize * fitScale) must grow by the same ratio so that
  // AssSubtitlesView.layout() receives updated bounds and re-renders at the correct scale.
  // Without this guarantee (e.g., when .fixedSize() is applied by the .attach modifier),
  // subtitles stay at their initial size even when the player is enlarged.
  @Test("display canvas size doubles when container doubles")
  func displayCanvasSizeScalesProportionallyWithContainer() {
    let videoSize = CGSize(width: 1920, height: 1080)
    let layout = VideoOrientationLayout.layout(for: videoSize, targetOrientation: .landscape)
    let logicalCanvas = layout.canvasSize

    let smallContainer = CGSize(width: 640, height: 360)
    let largeContainer = CGSize(width: 1280, height: 720)

    let fitScaleSmall = min(
      smallContainer.width / logicalCanvas.width,
      smallContainer.height / logicalCanvas.height)
    let fitScaleLarge = min(
      largeContainer.width / logicalCanvas.width,
      largeContainer.height / logicalCanvas.height)

    let canvasSizeSmall = CGSize(
      width: logicalCanvas.width * fitScaleSmall,
      height: logicalCanvas.height * fitScaleSmall)
    let canvasSizeLarge = CGSize(
      width: logicalCanvas.width * fitScaleLarge,
      height: logicalCanvas.height * fitScaleLarge)

    #expect(canvasSizeLarge.width > canvasSizeSmall.width)
    #expect(canvasSizeLarge.height > canvasSizeSmall.height)

    let epsilon: CGFloat = 0.001
    let widthRatio = canvasSizeLarge.width / canvasSizeSmall.width
    let heightRatio = canvasSizeLarge.height / canvasSizeSmall.height
    #expect(abs(widthRatio - 2.0) < epsilon)
    #expect(abs(heightRatio - 2.0) < epsilon)

    #expect(abs(canvasSizeSmall.width - 640) < epsilon)
    #expect(abs(canvasSizeLarge.width - 1280) < epsilon)
  }
}

@Suite("Segment processing preserves identity")
struct SegmentProcessingIdentityTests {
  @Test("padding preserves segment UUID and translation")
  func paddingPreservesUUIDAndTranslation() {
    let translation = SegmentTranslation(text: "你好", language: .chinese)
    let original = Segment(
      startTime: 1.0, endTime: 2.0, text: "hello",
      translation: translation)
    let padded = SegmentProcess.process(
      segments: [original],
      totalDuration: 10.0,
      operations: [.padding(leftMs: 100, rightMs: 100)])
    #expect(padded.count == 1)
    #expect(padded[0].id == original.id, "UUID must survive padding")
    #expect(padded[0].translation?.text == "你好", "Translation must survive padding")
  }

  @Test("ExportTextNormalizer preserves UUID and translation")
  func exportNormalizerPreservesUUIDAndTranslation() {
    let translation = SegmentTranslation(text: "你好！", language: .chinese)
    let original = Segment(
      startTime: 0, endTime: 1, text: "hello!",
      translation: translation)
    let normalized = ExportTextNormalizer.normalize(
      segments: [original], keepPunctuation: false)
    #expect(normalized.count == 1)
    #expect(normalized[0].id == original.id, "UUID must survive normalization")
    #expect(normalized[0].translation?.text == "你好", "Translation must survive normalization and be normalized")
  }
}

struct AudioSubtitlePreviewResolverTests {
  @Test("resolves the original segment and translation at compressed time")
  func resolvesSegmentAtCompressedTime() {
    var segments = [
      Segment(startTime: 2.0, endTime: 4.0, text: "第一句"),
      Segment(startTime: 7.0, endTime: 9.0, text: "第二句"),
    ]
    segments[1].translation = SegmentTranslation(text: "Second line", language: .english)

    let snapshot = AudioSubtitlePreviewResolver.snapshot(
      segments: segments,
      placement: .below,
      filterSilentSegments: true,
      time: 2.5
    )

    #expect(snapshot?.primaryText == "第二句")
    #expect(snapshot?.translationText == "Second line")
  }
}
