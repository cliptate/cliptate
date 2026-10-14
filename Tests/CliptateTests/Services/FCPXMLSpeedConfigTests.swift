import Foundation
import Testing
@testable import Cliptate

@Suite("FCPXML Speed Configuration")
@MainActor
struct FCPXMLSpeedConfigTests {

  @Test func snapshotRoundTrip_preservesSpeed() throws {
    var snapshot = AppConfiguration.defaultSnapshot
    snapshot.fcpxmlSpeed = 2.0

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: data)

    #expect(decoded.fcpxmlSpeed == 2.0)
  }

  @Test func snapshotDefault_speedIsOne() {
    let snapshot = AppConfiguration.defaultSnapshot
    #expect(snapshot.fcpxmlSpeed == 1.0)
  }

  @Test func legacySnapshot_decodesSpeedAsDefault() throws {
    let snapshot = AppConfiguration.defaultSnapshot
    let data = try JSONEncoder().encode(snapshot)
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    json.removeValue(forKey: "fcpxmlSpeed")
    let modifiedData = try JSONSerialization.data(withJSONObject: json)

    let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: modifiedData)
    #expect(decoded.fcpxmlSpeed == 1.0)
  }

  @Test func exportSettings_includesSpeed() {
    let settings = FCPXMLExportSettings(
      frameRate: 25.0,
      projectName: "Test",
      includeSubtitles: true,
      filterEmptySegments: true,
      isResolve: false,
      speed: 1.5
    )
    #expect(settings.speed == 1.5)
  }

  @Test func exportSettings_defaultSpeedIsOne() {
    let settings = FCPXMLExportSettings()
    #expect(settings.speed == 1.0)
  }
}
