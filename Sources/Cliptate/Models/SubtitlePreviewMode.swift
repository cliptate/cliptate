import Foundation

enum SubtitlePreviewMode: Equatable {
  case attachedToPlayer
  case nativeTextOverlay

  static func resolve(hasVideoTrack: Bool) -> Self {
    hasVideoTrack ? .attachedToPlayer : .nativeTextOverlay
  }
}
