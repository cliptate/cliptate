import CliptateCore
import Foundation
import Testing
@testable import Cliptate
import CoreGraphics

@Suite("FCPXML Speed Export")
struct FCPXMLSpeedExporterTests {

  private func makeMediaFile(
    segments: [Segment],
    duration: TimeInterval
  ) -> MediaFile {
    MediaFile(
      url: URL(fileURLWithPath: "/tmp/test.mp4"),
      segments: segments,
      duration: duration,
      presentationSize: CGSize(width: 1920, height: 1080)
    )
  }

  @Test func speed1_noTimeMap() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 1.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 1.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    #expect(!xml.contains("timeMap"))
  }

  @Test func speed2_hasTimeMap() {
    let segments = [
      Segment(startTime: 0.0, endTime: 2.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 2.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 2.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    #expect(xml.contains("timeMap"))
    #expect(xml.contains("timept"))
  }

  @Test func speed2_segmentTimelineFramesHalved() {
    let segments = [
      Segment(startTime: 0.0, endTime: 2.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 2.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 2.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    // Source: 50 frames. Timeline: ceil(50/2)=25 frames.
    // The asset-clip duration should be 25/25s
    #expect(xml.contains("duration=\"25/25s\""))
  }

  @Test func speed0_5_doublesTimelineDuration() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 1.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 0.5
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    #expect(xml.contains("timeMap"))
    // Source: 25 frames. Timeline: ceil(25/0.5)=50.
    #expect(xml.contains("duration=\"50/25s\""))
  }

  @Test func gapClipsAlsoGetTimeMap_whenSpeedNotOne() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
      Segment(startTime: 2.0, endTime: 3.0, text: "world"),
    ]
    let media = makeMediaFile(segments: segments, duration: 3.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: false,
      isResolve: false, speed: 2.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    let timeMapCount = xml.components(separatedBy: "<timeMap>").count - 1
    // gap clip + 2 segment clips = at least 3 timeMaps
    #expect(timeMapCount >= 3)
  }
}
