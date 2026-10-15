import CliptateCore
import SwiftUI

struct EditorExportOptions: View {
  @Binding var selectedOutputModule: OutputModule

  var body: some View {
    VStack(spacing: 12) {
      Text("Configure export formats and related options.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Picker("Output Module", selection: $selectedOutputModule) {
        ForEach(OutputModule.allCases) { module in
          Text(module.label).tag(module)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .onAppear {
        if !OutputModule.allCases.contains(selectedOutputModule) {
          selectedOutputModule = OutputModule.allCases.first ?? .fcpxml
        }
      }
      .onChange(of: selectedOutputModule) { _, newValue in
        if !OutputModule.allCases.contains(newValue) {
          selectedOutputModule = OutputModule.allCases.first ?? .fcpxml
        }
      }

      Group {
        switch selectedOutputModule {
        case .fcpxml:
          EditorFCPXMLOptions()
        case .subtitleFiles:
          EditorSubtitleExportOptions()
        case .video:
          EditorVideoExportOptions()
        case .audio:
          EditorAudioExportOptions()
        }
      }
      .animation(.easeInOut(duration: 0.2), value: selectedOutputModule)
    }
  }
}
