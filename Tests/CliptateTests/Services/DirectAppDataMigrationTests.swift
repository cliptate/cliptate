import XCTest

@testable import Cliptate

final class DirectAppDataMigrationTests: XCTestCase {
  func testMigrationPreservesCurrentDataAndOriginalsAndDoesNotResurrectDeletedFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("sandbox")
    let target = root.appendingPathComponent("direct")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("recordings"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: source.appendingPathComponent("config.json"))
    try Data("current".utf8).write(to: target.appendingPathComponent("config.json"))
    let recording = source.appendingPathComponent("recordings/audio.wav")
    try Data("audio".utf8).write(to: recording)
    try DirectAppDataMigration.copyMissingData(from: source, to: target)
    XCTAssertEqual(
      try String(contentsOf: target.appendingPathComponent("config.json"), encoding: .utf8),
      "current")
    XCTAssertEqual(
      try Data(contentsOf: target.appendingPathComponent("recordings/audio.wav")),
      Data("audio".utf8))
    XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    try FileManager.default.removeItem(at: target.appendingPathComponent("recordings/audio.wav"))
    try DirectAppDataMigration.copyMissingData(from: source, to: target)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: target.appendingPathComponent("recordings/audio.wav").path))
  }
}
