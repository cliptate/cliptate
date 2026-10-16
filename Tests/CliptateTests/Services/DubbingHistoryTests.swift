import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("Dubbing history")
@MainActor
struct DubbingHistoryTests {
  @Test("retained speech survives transcript saves and an application restart")
  func restoresRetainedSpeech() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let historyURL = directory.appendingPathComponent("history.json")
    let history = HistoryRuntime(store: TranscriptHistoryStore(historyURL: historyURL))
    var session = TranscriptSession(source: .fileTranscription)
    session.append(text: "Hello", at: 0)
    history.add(session)
    let clip = DubbedClip(
      segmentIdentifier: .init(startTime: 0, endTime: 1), fingerprint: "speech-v1",
      audioURL: directory.appendingPathComponent("speech.wav"), duration: 1, sampleRate: 24_000)
    try history.retainDubbingClips([clip], for: session.id)
    history.add(session)
    let restored = HistoryRuntime(store: TranscriptHistoryStore(historyURL: historyURL))
    #expect(restored.sessions.first?.aiCutDubbedClips == [clip])
  }
}
