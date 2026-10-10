import Foundation
import Testing
@testable import Cliptate

/// These tests verify the `ttsReferenceAudioBookmark` field on `AppConfiguration.Snapshot`
/// using pure value-type semantics — no singleton access, no shared mutable state.
@Suite("AppConfiguration TTS Bookmark Tests")
struct AppConfigurationTTSBookmarkTests {

    @Test("Default snapshot has nil ttsReferenceAudioBookmark")
    func testDefaultSnapshotHasNilBookmark() {
        let snap = AppConfiguration.defaultSnapshot
        #expect(snap.ttsReferenceAudioBookmark == nil)
    }

    @Test("Snapshot with bookmark set round-trips through Codable")
    func testSnapshotBookmarkCodableRoundTrip() throws {
        var snap = AppConfiguration.defaultSnapshot
        let fakeBookmark = Data([0x01, 0x02, 0x03])
        snap.ttsReferenceAudioBookmark = fakeBookmark

        let encoded = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: encoded)
        #expect(decoded.ttsReferenceAudioBookmark == fakeBookmark)
    }

    @Test("Snapshot without bookmark encodes nil and decodes nil")
    func testSnapshotNilBookmarkRoundTrip() throws {
        var snap = AppConfiguration.defaultSnapshot
        snap.ttsReferenceAudioBookmark = nil

        let encoded = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: encoded)
        #expect(decoded.ttsReferenceAudioBookmark == nil)
    }

    @Test("Snapshot equality reflects bookmark field")
    func testSnapshotEqualityWithBookmark() {
        var snap1 = AppConfiguration.defaultSnapshot
        var snap2 = AppConfiguration.defaultSnapshot

        snap1.ttsReferenceAudioBookmark = Data([0xAA, 0xBB])
        snap2.ttsReferenceAudioBookmark = Data([0xAA, 0xBB])
        #expect(snap1 == snap2)

        snap2.ttsReferenceAudioBookmark = Data([0xCC])
        #expect(snap1 != snap2)

        snap2.ttsReferenceAudioBookmark = nil
        #expect(snap1 != snap2)
    }
}
