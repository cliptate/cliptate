import CliptateCore
import SwiftUI

struct EditorVideoExportOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose default behaviour for exporting video files during batch export.")
        .font(.caption2)
        .foregroundColor(.secondary)

      GroupBox {
        Toggle(isOn: $config.videoExportEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Video Export")
              .font(.caption)
            Text(
              "When enabled, batch export can create rendered video files using the options below."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      } label: {
        Label("Video Export", systemImage: "play.rectangle")
      }

      VStack(spacing: 10) {
        HStack {
          Text("Format")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Picker("Format", selection: $config.videoExportFormat) {
            ForEach(VideoExportFormat.allCases) { format in
              Text(format.displayName).tag(format)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .disabled(!config.videoExportEnabled)
        }

        Toggle(isOn: $config.videoExportBurnInSubtitles) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Burn Subtitles Into Video")
              .font(.caption)
            Text("If off, the export keeps a clean copy without rendered subtitles.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
        .disabled(!config.videoExportEnabled)

        Divider()

        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text("Quality")
              .font(.caption)
              .foregroundColor(.secondary)
            Spacer()
            Picker("Quality", selection: $config.videoExportQuality) {
              ForEach(VideoExportQuality.allCases) { quality in
                Text(quality.displayName).tag(quality)
              }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(!config.videoExportEnabled)
          }

          Text(config.videoExportQuality.description)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.videoExportEnabled)

      Text("These settings become the defaults when opening the Export All dialog.")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
  }
}

struct EditorAudioExportOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure standalone audio exports to accompany your subtitles and projects.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      GroupBox {
        Toggle(isOn: $config.audioExportEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Audio Export")
              .font(.caption)
            Text("Create audio-only files during batch export using the selected format.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      } label: {
        Label("Audio Export", systemImage: "waveform.circle")
      }

      VStack(spacing: 10) {
        HStack {
          Text("Format")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Picker("Format", selection: $config.audioExportFormat) {
            ForEach(AudioExportFormat.allCases) { format in
              Text(format.displayName).tag(format)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .disabled(!config.audioExportEnabled)
        }

        Text("Audio files are exported alongside other assets when the option is enabled.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.audioExportEnabled)
    }
  }

  // MARK: - Dubbing Enhancement
}
