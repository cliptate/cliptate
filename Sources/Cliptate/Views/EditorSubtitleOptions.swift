import CliptateCore
import SwiftUI

struct EditorSubtitleOptions: View {
  @EnvironmentObject private var config: AppConfiguration
  @Binding var selectedSubtitleOrientation: SubtitleOrientation

  var body: some View {
    let orientation = selectedSubtitleOrientation
    let defaultStyles = defaultSubtitleStyles[orientation]

    return VStack(alignment: .leading, spacing: 8) {
      Text("Subtitle Styles")
        .font(.caption)
      Text("Customize fonts, colors, and emphasis for the selected orientation.")
        .font(.caption2)
        .foregroundColor(.secondary)

      Picker("Subtitle Orientation", selection: $selectedSubtitleOrientation) {
        Text("Landscape").tag(SubtitleOrientation.landscape)
        Text("Portrait").tag(SubtitleOrientation.portrait)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      HStack {
        Text(orientation == .landscape ? "16:9 and wider videos" : "Vertical and square videos")
          .font(.caption2)
          .foregroundColor(.secondary)
        Spacer()
        Button("Reset Orientation") {
          config.updateSubtitleStyleSet(defaultStyles, for: orientation)
        }
        .buttonStyle(.borderless)
        .font(.caption2)
      }

      VStack(spacing: 12) {
        SubtitleStyleEditor(
          title: "Primary Line",
          subtitle: "Main transcription line shown in the Segments pane and exports.",
          kind: .primary,
          style: Binding(
            get: { config.subtitleStyleSet(for: orientation).primary },
            set: { newValue in
              var updated = config.subtitleStyleSet(for: orientation)
              updated.primary = newValue
              config.updateSubtitleStyleSet(updated, for: orientation)
            }
          ),
          defaultStyle: defaultStyles.primary
        )

        SubtitleStyleEditor(
          title: "Translation Line",
          subtitle: "Displayed when translated subtitles are enabled.",
          kind: .translation,
          style: Binding(
            get: { config.subtitleStyleSet(for: orientation).translation },
            set: { newValue in
              var updated = config.subtitleStyleSet(for: orientation)
              updated.translation = newValue
              config.updateSubtitleStyleSet(updated, for: orientation)
            }
          ),
          defaultStyle: defaultStyles.translation
        )

        SubtitleStyleEditor(
          title: "Highlight Emphasis",
          subtitle: "Applied to AI-highlighted keywords for emphasis.",
          kind: .highlight,
          style: Binding(
            get: { config.subtitleStyleSet(for: orientation).highlight },
            set: { newValue in
              var updated = config.subtitleStyleSet(for: orientation)
              updated.highlight = newValue
              config.updateSubtitleStyleSet(updated, for: orientation)
            }
          ),
          defaultStyle: defaultStyles.highlight
        )
      }
    }
    .padding(8)
    .background(
      AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
  }
}
