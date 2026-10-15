import AVFoundation
import CliptateCore
import SwiftUI

/// The video and subtitles share one fitted canvas, independent of transport controls.
struct EditorVideoCanvas<Subtitles: View>: View {
  let player: AVPlayer?
  let layout: VideoOrientationLayout.Result
  @ViewBuilder var subtitles: (AVPlayer, CGSize) -> Subtitles

  private var targetAspectRatio: CGFloat? {
    let ratio = layout.aspectRatio
    return ratio.isFinite && ratio > 0 ? ratio : nil
  }

  var body: some View {
    ZStack {
      if let player {
        GeometryReader { proxy in
          let containerSize = proxy.size
          let fitScale = Self.scaleToFit(layout.canvasSize, in: containerSize)
          let canvasSize = CGSize(
            width: layout.canvasSize.width * fitScale,
            height: layout.canvasSize.height * fitScale
          )

          let displayedVideoSize = CGSize(
            width: layout.scaledVideoSize.width * fitScale,
            height: layout.scaledVideoSize.height * fitScale
          )

          let canvasOffset = CGSize(
            width: layout.offset.x * fitScale,
            height: layout.offset.y * fitScale
          )

          ZStack(alignment: .topLeading) {
            Color.black
              .frame(width: canvasSize.width, height: canvasSize.height)

            PlayerContainerView(player: player, videoGravity: .resizeAspect)
              .frame(width: displayedVideoSize.width, height: displayedVideoSize.height)
              .offset(x: canvasOffset.width, y: canvasOffset.height)

            subtitles(player, canvasSize)
          }
          .frame(width: canvasSize.width, height: canvasSize.height)
          .clipped()
          .position(x: containerSize.width / 2, y: containerSize.height / 2)
        }
        .background(Color.black)
        .aspectRatio(targetAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading video…")
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.6))
      }
    }
  }

  private static func scaleToFit(_ content: CGSize, in container: CGSize) -> CGFloat {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
      return 1
    }
    let scaleX = container.width / content.width
    let scaleY = container.height / content.height
    return min(scaleX, scaleY)
  }
}
