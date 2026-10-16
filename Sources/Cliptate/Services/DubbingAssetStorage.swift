import CliptateCore
import CryptoKit
import Foundation

enum DubbingAssetStorage {
  static var root: URL {
    AppIdentity.current.applicationSupportDirectory().appendingPathComponent(
      "dubbing-audio", isDirectory: true)
  }

  static func directory(sessionID: UUID?, sourceURL: URL) -> URL {
    let name =
      sessionID?.uuidString
      ?? SHA256.hash(data: Data(sourceURL.standardizedFileURL.path.utf8)).map {
        String(format: "%02x", $0)
      }.joined()
    return root.appendingPathComponent(name, isDirectory: true)
  }

  static func removeAssets(for session: TranscriptSession) {
    let ownedRoot = root.resolvingSymlinksInPath().path + "/"
    for clip in session.aiCutDubbedClips ?? [] {
      let url = clip.audioURL.resolvingSymlinksInPath()
      if url.path.hasPrefix(ownedRoot) { try? FileManager.default.removeItem(at: url) }
    }
    try? FileManager.default.removeItem(at: root.appendingPathComponent(session.id.uuidString))
  }
}

extension VideoDubbingRequest {
  @MainActor
  static func make(
    sourceURL: URL, state: VideoState, segments: [Segment],
    configuration: AppConfiguration, duration: TimeInterval? = nil
  ) throws -> Self {
    guard
      let model = DubbingModelResolver.resolveVoiceCloneModel(
        preferredRepo: configuration.ttsMLXModelId)
    else {
      throw DubbingService.DubbingError.ttsModelNotAvailable
    }
    var request = Self(
      sourceMediaURL: sourceURL, segments: segments,
      totalDuration: duration ?? state.audioDuration ?? segments.map(\.endTime).max() ?? 0,
      filterSilentSegments: configuration.filterSilent, model: model,
      language: configuration.translationTargetLanguage.rawValue,
      assetDirectory: DubbingAssetStorage.directory(
        sessionID: state.historySessionID, sourceURL: sourceURL),
      referenceSegments: state.originalSegments.isEmpty ? state.segments : state.originalSegments)
    if configuration.dubbingVoiceReferenceMode == .custom {
      var referenceURL: URL?
      if let bookmark = configuration.ttsReferenceAudioBookmark {
        var stale = false
        referenceURL = try? URL(
          resolvingBookmarkData: bookmark, options: .withSecurityScope,
          bookmarkDataIsStale: &stale)
        if stale { referenceURL = nil }
      }
      if referenceURL == nil && !configuration.ttsReferenceAudioPath.isEmpty {
        referenceURL = URL(fileURLWithPath: configuration.ttsReferenceAudioPath)
      }
      guard let referenceURL, FileManager.default.fileExists(atPath: referenceURL.path),
        !configuration.ttsReferenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw VideoDubbingError.referenceUnavailable
      }
      request.referenceAudioURL = referenceURL
      request.referenceText = configuration.ttsReferenceText
    }
    return request
  }
}
