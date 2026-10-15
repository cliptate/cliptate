import CliptateCore
import SwiftUI

struct ControlPanelConfigurationView: View {
  @Binding var selectedTab: ControlPanelView.ConfigTab
  @State private var selectedEnhanceModule: EnhanceModule = .timing
  @State private var selectedOutputModule: OutputModule = .fcpxml
  @State private var selectedSubtitleOrientation: SubtitleOrientation = .landscape

  var body: some View {
    VStack(spacing: 0) {
      Picker("Config Tab", selection: $selectedTab) {
        ForEach(ControlPanelView.ConfigTab.allCases) { tab in
          Text(tab.localizedTitle).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(12)

      ScrollView {
        selectedContent
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.bottom, 16)
      }
    }
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .transcription:
      EditorTranscriptionOptions()
    case .translation:
      EditorTranslationOptions()
    case .enhance:
      EditorEnhancementOptions(
        selectedEnhanceModule: $selectedEnhanceModule,
        selectedSubtitleOrientation: $selectedSubtitleOrientation
      )
    case .output:
      EditorExportOptions(selectedOutputModule: $selectedOutputModule)
    }
  }
}

enum EnhanceModule: String, CaseIterable, Identifiable {
  case timing
  case highlight
  case zoom
  case filter
  case style
  case dubbing

  var id: String { rawValue }

  var label: LocalizedStringKey {
    switch self {
    case .timing:   return "Timing"
    case .highlight: return "Highlight"
    case .zoom:     return "Zoom"
    case .filter:   return "Filter"
    case .style:    return "Style"
    case .dubbing:  return "Dubbing"
    }
  }
}

enum OutputModule: String, CaseIterable, Identifiable {
  case fcpxml
  case subtitleFiles
  case video
  case audio

  var id: String { rawValue }

  static var allCases: [OutputModule] { [.fcpxml, .subtitleFiles, .video, .audio] }

  var label: LocalizedStringKey {
    switch self {
    case .fcpxml:        return "FCPXML"
    case .subtitleFiles: return "Subtitle Files"
    case .video:         return "Video"
    case .audio:         return "Audio"
    }
  }
}

extension ControlPanelView {
  // Configuration tabs
  enum ConfigTab: String, CaseIterable, Identifiable {
    case transcription = "Transcription"
    case translation = "Translation"
    case enhance = "Enhance"
    case output = "Export"

    var id: String { rawValue }
    var icon: String {
      switch self {
      case .transcription: return "waveform"
      case .translation: return "globe"
      case .output: return "square.and.arrow.up"
      case .enhance: return "wand.and.stars.inverse"
      }
    }
    /// Properly-extracted localized label for Xcode to statically discover.
    var localizedTitle: String {
      switch self {
      case .transcription:
        return String(localized: "Transcription", comment: "Tab label for transcription settings section")
      case .translation:
        return String(localized: "Translation", comment: "Tab label for translation settings section")
      case .enhance:
        return String(localized: "Enhance", comment: "Tab label for enhance settings section")
      case .output:
        return String(localized: "Export", comment: "Tab label for export settings section")
      }
    }
  }
}
