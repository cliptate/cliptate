#if os(macOS)
  import AVKit
  import SwiftUI

  struct PlayerContainerView: NSViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> AVPlayerView {
      let view = AVPlayerView()
      view.controlsStyle = .none
      view.videoGravity = videoGravity
      view.player = player
      view.allowsPictureInPicturePlayback = false
      view.showsFullScreenToggleButton = false
      view.updatesNowPlayingInfoCenter = false
      return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
      if nsView.player !== player {
        nsView.player = player
      }
      if nsView.videoGravity != videoGravity {
        nsView.videoGravity = videoGravity
      }
      nsView.controlsStyle = .none
      nsView.allowsPictureInPicturePlayback = false
      nsView.showsFullScreenToggleButton = false
    }
  }
#endif
