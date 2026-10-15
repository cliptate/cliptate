import CliptateCore
import SwiftUI

struct EditorTimingOptions: View {
  @EnvironmentObject private var config: AppConfiguration
  private let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  var body: some View {
    VStack(spacing: 8) {
      Text("Padding adds ms before/after each segment; auto-adjusts to avoid overlap.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 8) {
        HStack {
          Text("Left Pad")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          TextField("0", value: $config.leftPadMs, formatter: numberFormatter)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
          Text("ms")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        HStack {
          Text("Right Pad")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          TextField("0", value: $config.rightPadMs, formatter: numberFormatter)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
          Text("ms")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(spacing: 8) {
        Toggle(isOn: $config.splitBySentence) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Split By Sentence")
              .font(.caption)
            Text("Break segments on sentence-ending punctuation and commas before other rules.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        VStack(spacing: 6) {
          Text(
            "Control secondary splitting by character length (0 disables)."
          )
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Split By Chars")
                .font(.caption)
              Spacer()
              Text("\(Int(config.maxCharsPerSegment))")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Slider(
              value: Binding(
                get: { Double(config.maxCharsPerSegment) },
                set: { config.maxCharsPerSegment = Int($0) }
              ),
              in: 0...100,
              step: 1
            )
          }
        }
        .help(
          "Set to 0 to skip character-based splitting. Applied after sentence splits if enabled.")
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      Text("Filter Silent hides empty segments in UI/export.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Text("Filter Silent")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Toggle("", isOn: $config.filterSilent)
          .labelsHidden()
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }
}

struct EditorHighlightOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectExtractHighlights) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Extract Highlight Keywords")
              .font(.caption)
            Text("Automatically identify keywords to emphasize in each segment.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectEnableScaling) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Scaling")
              .font(.caption)
            Text("Increase keyword emphasis using the multiplier below.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Scale Multiplier")
              .font(.caption)
            Spacer()
            Text(String(format: "%.1fx", config.effectScaleMultiplier))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Slider(value: $config.effectScaleMultiplier, in: 1.0...2.5, step: 0.1)
            .disabled(!config.effectEnableScaling)
          Text("Higher values make highlighted keywords larger in the Segments panel and exports.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .disabled(!config.effectEnableScaling)

      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }
}

struct EditorZoomOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectEnableZoom) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Zoom")
              .font(.caption)
            Text("Auto-zoom segments when highlights cover more than 50% of the text.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Zoom Multiplier")
              .font(.caption)
            Spacer()
            Text(String(format: "%.1fx", config.effectZoomMultiplier))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Slider(value: $config.effectZoomMultiplier, in: 1.0...3.0, step: 0.1)
            .disabled(!config.effectEnableZoom)
          Text("Applies to the entire segment when highlight coverage exceeds 50%.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .disabled(!config.effectEnableZoom)

      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }
}
