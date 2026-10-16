import CliptateCore
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif

struct SubtitleStyleEditor: View {
  let title: String
  let subtitle: String
  let kind: SubtitleStyleKind
  @Binding var style: SubtitleStyle
  let defaultStyle: SubtitleStyle

  #if canImport(AppKit)
    private static let availableFonts: [String] = {
      let manager = NSFontManager.shared
      var names = Set(manager.availableFontFamilies.map { $0.trimmingCharacters(in: .whitespaces) })
      names.insert("Arial Unicode MS")
      return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
  #else
    private static let availableFonts: [String] = ["Arial Unicode MS"]
  #endif

  private let fontRange: ClosedRange<Double> = 12...120

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(subtitle)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Style Preset")
          .font(.caption)
          .foregroundColor(.secondary)

        Picker("Style Preset", selection: presetBinding) {
          ForEach(SubtitleStylePreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .pickerStyle(.menu)

        Text(selectedPreset.description)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Divider()

      fontControls

      Divider()

      emphasisControls

      Button(role: .destructive) {
        style = normalized(defaultStyle)
      } label: {
        Label("Reset to Default", systemImage: "arrow.clockwise")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .padding(.top, 4)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(AppSurface.subtleFill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(AppSurface.border)
    )
    .onAppear {
      style = normalized(style)
    }
  }

  private var selectedPreset: SubtitleStylePreset {
    style.matchedPreset() ?? SubtitleStylePreset.default(for: kind)
  }

  private var presetBinding: Binding<SubtitleStylePreset> {
    Binding(
      get: { selectedPreset },
      set: { newPreset in
        let fontSize = style.fontSize
        var updated = style.applyingPreset(newPreset, kind: kind)
        updated.fontSize = clamp(fontSize, within: fontRange)
        style = updated
      }
    )
  }

  private var fontControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      #if canImport(AppKit)
        Picker(
          "Font",
          selection: Binding(
            get: { style.fontName },
            set: { style.fontName = $0 }
          )
        ) {
          ForEach(Self.availableFonts, id: \.self) { name in
            Text(name).tag(name)
          }
        }
        .pickerStyle(.menu)
      #else
        TextField(
          "Font",
          text: Binding(
            get: { style.fontName },
            set: { style.fontName = $0 }
          )
        )
        .textFieldStyle(.roundedBorder)
      #endif

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Font Size")
            .font(.caption)
          Spacer()
          Text("\(Int(round(style.fontSize))) pt")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        Slider(
          value: Binding(
            get: { style.fontSize },
            set: { style.fontSize = clamp($0, within: fontRange) }
          ),
          in: fontRange,
          step: 1
        )
      }
    }
  }

  private var emphasisControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      if kind == .highlight {
        HStack(spacing: 4) {
          Image(systemName: "bolt.fill")
            .foregroundStyle(Color.accentColor)
          Text("Highlight lines stay bold for emphasis.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
      } else {
        Toggle(
          "Bold",
          isOn: Binding(
            get: { style.bold },
            set: { style.bold = $0 }
          )
        )
        .appFeatureSwitch()
        .font(.caption)
      }

      Toggle(
        "Italic",
        isOn: Binding(
          get: { style.italic },
          set: { style.italic = $0 }
        )
      )
      .appFeatureSwitch()
      .font(.caption)
    }
  }

  private func normalized(_ incoming: SubtitleStyle) -> SubtitleStyle {
    var next = incoming
    if next.matchedPreset() == nil {
      next = next.applyingPreset(.default(for: kind), kind: kind)
    }
    if kind == .highlight {
      next.bold = true
    }
    next.fontSize = clamp(next.fontSize, within: fontRange)
    return next
  }

  private func clamp(_ value: Double, within range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
