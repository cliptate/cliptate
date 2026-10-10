import Combine
import Foundation

@MainActor
final class HistoryRuntime: ObservableObject {
  static let shared = HistoryRuntime()

  private let store: TranscriptHistoryStore
  private var cancellable: AnyCancellable?

  init(store: TranscriptHistoryStore? = nil) {
    self.store = store ?? .shared
    cancellable = self.store.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

  var recentDictationSessions: [TranscriptSession] {
    store.recentDictationSessions
  }

  var allSortedSessions: [TranscriptSession] {
    store.allSortedSessions
  }

  var sessions: [TranscriptSession] {
    store.sessions
  }

  func add(_ session: TranscriptSession) {
    store.add(session)
  }

  func replace(_ session: TranscriptSession) {
    store.replace(session)
  }

  func existingFileTranscriptionSessionID(forSourceURL url: URL) -> UUID? {
    store.existingFileTranscriptionSessionID(forSourceURL: url)
  }

  func sourceURLBookmark(for sessionID: UUID?) -> Data? {
    store.sourceURLBookmark(for: sessionID)
  }

  func remove(id: UUID) {
    store.remove(id: id)
  }

  func removeAll(source: SessionSource? = nil) {
    store.removeAll(source: source)
  }
}
