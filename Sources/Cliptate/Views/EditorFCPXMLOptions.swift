import CliptateCore
import SwiftUI

struct EditorFCPXMLOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(spacing: 8) {
      Text("Configure Final Cut Pro XML export settings.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: $config.fcpxmlEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable FCPXML Export")
              .font(.caption)
            Text("When off, exports will only include selected subtitle files.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .appFeatureSwitch()

        if !config.fcpxmlEnabled {
          Text(
            "Re-enable to configure Final Cut Pro specific settings and per-video export button."
          )
          .font(.caption2)
          .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Project Prefix")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("Cliptate", text: $config.fcpxmlProjectName)
            .textFieldStyle(.roundedBorder)
          Text("Suffix will use today's date automatically.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("Frame Rate")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          DecimalTextField(
            value: $config.fcpxmlFrameRate,
            clamp: FCPXMLSpeedParser.clampFrameRate
          )
          .frame(width: 70)
          Text("fps")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("Speed")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          DecimalTextField(
            value: $config.fcpxmlSpeed,
            clamp: FCPXMLSpeedParser.clamp
          )
          .frame(width: 70)
          Text("×")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.fcpxmlEnabled)

      VStack(spacing: 8) {
        HStack {
          Text("Include Subtitles")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Toggle("", isOn: $config.fcpxmlIncludeSubtitles)
            .labelsHidden()
            .accessibilityLabel("Include Subtitles")
            .appFeatureSwitch()
        }

        HStack {
          Text("DaVinci Resolve")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Toggle("", isOn: $config.fcpxmlIsResolveCompatible)
            .labelsHidden()
            .accessibilityLabel("DaVinci Resolve")
            .appFeatureSwitch()
        }
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.fcpxmlEnabled)

      if config.fcpxmlEnabled {
        Text("DaVinci Resolve mode exports FCPXML 1.10 for better compatibility.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("Choose Merge or Separate from the Export All button menu to control project layout.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

struct EditorSubtitleExportOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Choose subtitle file formats to include with each export.")
        .font(.caption2)
        .foregroundColor(.secondary)

      ForEach(SubtitleExportFormat.allCases) { format in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(format.displayName)
              .font(.caption)
              .fontWeight(.medium)
            Text(format.description)
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Spacer()
          Toggle(
            "",
            isOn: Binding(
              get: { config.subtitleExportFormats.contains(format) },
              set: { isOn in
                if isOn {
                  config.subtitleExportFormats.insert(format)
                } else {
                  config.subtitleExportFormats.remove(format)
                }
              }
            )
          )
          .labelsHidden()
        }
        .padding(8)
        .background(
          AppSurface.subtleFill,
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
      }

      Text("Selected formats will be exported alongside video and FCPXML outputs.")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
  }
}
