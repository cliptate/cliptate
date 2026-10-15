import SwiftUI

/// Keeps transport actions and a usable scrubber visible in narrow preview panes.
struct EditorPlaybackControls: View {
  let isPlaying: Bool
  let hasDuration: Bool
  let currentTimeLabel: String
  let durationLabel: String
  let range: ClosedRange<Double>
  @Binding var time: Double
  let onTogglePlayback: () -> Void
  let onSeekBackward: () -> Void
  let onSeekForward: () -> Void
  let onScrubbingChange: (Bool) -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 14) {
        transportButtons
        Text(currentTimeLabel)
          .fixedSize()
        scrubber.frame(minWidth: 100)
        Text(durationLabel)
          .fixedSize()
      }

      VStack(spacing: 8) {
        transportButtons
          .frame(maxWidth: .infinity)
        HStack(spacing: 8) {
          Text(currentTimeLabel).fixedSize()
          scrubber
          Text(durationLabel).fixedSize()
        }
        .font(.system(.caption2, design: .monospaced))
      }
    }
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .frame(maxWidth: 540)
  }

  private var transportButtons: some View {
    HStack(spacing: 10) {
      Button(action: onTogglePlayback) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.primary)
          .frame(width: 32, height: 32)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.space, modifiers: [])
      .background(AppSurface.selectedFill, in: Circle())

      Button(action: onSeekBackward) {
        Image(systemName: "gobackward.5")
          .font(.body)
          .frame(width: 28, height: 28)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .disabled(!hasDuration)

      Button(action: onSeekForward) {
        Image(systemName: "goforward.5")
          .font(.body)
          .frame(width: 28, height: 28)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .disabled(!hasDuration)
    }
    .fixedSize()
  }

  private var scrubber: some View {
    Slider(value: $time, in: range, onEditingChanged: onScrubbingChange)
      .disabled(!hasDuration)
  }
}
