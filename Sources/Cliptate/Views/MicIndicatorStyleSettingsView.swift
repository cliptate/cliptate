import SwiftUI

struct MicIndicatorStyleSettingsView: View {
  @Binding var selection: MicIndicatorStyle
  private let previewScale: CGFloat = 0.45

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Dictation Indicator", systemImage: "waveform")
        .font(.headline)

      Text("Choose the appearance of the floating indicator. Changes apply immediately.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 6) {
        ForEach(MicIndicatorStyle.allCases) { style in
          styleCard(style)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
      }
      .frame(maxWidth: 560, alignment: .leading)
    }
    .padding(12)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
  }

  private func styleCard(_ style: MicIndicatorStyle) -> some View {
    let isSelected = selection == style
    return Button {
      selection = style
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        GeometryReader { proxy in
          let scale = min(previewScale, proxy.size.width / MicIndicatorStylePreview.size.width)
          MicIndicatorStylePreview(style: style)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: MicIndicatorStylePreview.size.height * previewScale)

        Text(style.displayName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
          .frame(maxWidth: .infinity)
      }
      .padding(6)
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(
            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
            lineWidth: isSelected ? 1.5 : 1)
      }
      .overlay(alignment: .topTrailing) {
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(4)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(style.summary)
    .accessibilityLabel(style.displayName)
    .accessibilityValue(
      isSelected ? String(localized: "Selected") : String(localized: "Not selected")
    )
    .accessibilityHint(style.summary)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

#Preview {
  MicIndicatorStyleSettingsView(selection: .constant(.pulseBlue))
    .padding()
    .frame(width: 960)
}
