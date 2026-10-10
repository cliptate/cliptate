import Foundation
import Testing

@testable import Cliptate

/// Tests that TTS audio bookmarks (for files in the app's own container) are
/// created and resolved without security scope, so playback and Finder reveal
/// work without calling startAccessingSecurityScopedResource().
@Suite("TTS audio bookmark – app-container files use plain bookmarks")
struct TTSAudioBookmarkTests {

    @Test("Plain bookmark round-trips to a readable URL")
    func plainBookmarkRoundTrips() throws {
        // Arrange: write a temp file that simulates an auto-saved TTS WAV
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let wavURL = tmpDir.appendingPathComponent("test.wav")
        let fakeWAV = Data([0x52, 0x49, 0x46, 0x46]) // "RIFF" header prefix
        try fakeWAV.write(to: wavURL)

        // Act: create bookmark WITHOUT security scope (correct for app-container files)
        let bookmarkData = try wavURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Resolve (mirrors what HistoryView does)
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        // Assert: URL is valid, not stale, and the file is readable
        #expect(!isStale)
        #expect(resolvedURL.lastPathComponent == "test.wav")
        let readBack = try Data(contentsOf: resolvedURL)
        #expect(readBack == fakeWAV)
    }

    @Test("Stale flag is false when file exists at same path")
    func bookmarkIsNotStaleForExistingFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("audio.wav")
        try Data([0x00]).write(to: fileURL)

        let bookmark = try fileURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)

        var isStale = false
        _ = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #expect(!isStale)
    }
}
