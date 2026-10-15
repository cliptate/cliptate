import SwiftUI

struct SegmentsPanelHeader: View {
  let displayCount: Int
  let hasSegments: Bool
  let hasDiarization: Bool
  @Binding var showTimes: Bool

  private var headerControlState: SegmentsPanelHeaderControlState {
    SegmentsPanelHeaderControlState(hasSegments: hasSegments, showTimes: showTimes)
  }

  var body: some View {
    HStack(spacing: 6) {
      Text("Segments")
        .font(.headline)
      if hasSegments {
        Text("\(displayCount)")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(AppSurface.subtleFill))
      }
      // Show a diarization badge when any segment carries a speaker ID
      if hasDiarization {
        Label("Speaker", systemImage: "person.2.wave.2")
          .font(.caption2.weight(.medium))
          .foregroundStyle(Color.accentColor)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Capsule().fill(AppSurface.selectedFill)
          )
          .help(
            String(
              localized: "Diarization active – speaker badges are shown per segment",
              comment: "Tooltip shown when any segment has a speaker ID"))
      }
      Spacer()
      Button(action: { showTimes.toggle() }) {
        Image(systemName: headerControlState.timeSymbolName)
          .foregroundStyle(
            headerControlState.isTimeHighlighted ? Color.accentColor : Color.secondary
          )
          .frame(
            width: headerControlState.controlSize.width,
            height: headerControlState.controlSize.height
          )
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(
                headerControlState.isTimeHighlighted
                  ? AppSurface.selectedFill : AppSurface.hoverFill
              )
          )
      }
      .buttonStyle(.borderless)
      .contentShape(Rectangle())
      .accessibilityIdentifier("segments.toggle-times")
      .help(
        headerControlState.showTimes
          ? String(localized: "Hide times", comment: "Tooltip to hide time labels in segments panel")
          : String(localized: "Show times", comment: "Tooltip to show time labels in segments panel")
      )
    }
    .padding(.horizontal, 4)
  }

}

struct SegmentsPanelHeaderControlState {
  let hasSegments: Bool
  let showTimes: Bool

  let timeSymbolName = "clock"
  var isTimeHighlighted: Bool { showTimes }
  let controlSize = CGSize(width: 30, height: 28)
}
