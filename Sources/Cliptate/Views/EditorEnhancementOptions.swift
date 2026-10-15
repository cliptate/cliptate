import CliptateCore
import SwiftUI

struct EditorEnhancementOptions: View {
  @Binding var selectedEnhanceModule: EnhanceModule
  @Binding var selectedSubtitleOrientation: SubtitleOrientation

  var body: some View {
    VStack(spacing: 12) {
      Text("Fine-tune AI Enhance effects by switching between focused modules.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Picker("Enhance Module", selection: $selectedEnhanceModule) {
        ForEach(EnhanceModule.allCases) { module in
          Text(module.label).tag(module)
        }
      }
      .pickerStyle(.menu)

      Group {
        switch selectedEnhanceModule {
        case .timing:
          EditorTimingOptions()
        case .highlight:
          EditorHighlightOptions()
        case .zoom:
          EditorZoomOptions()
        case .filter:
          EditorFilterOptions()
        case .style:
          EditorSubtitleOptions(selectedSubtitleOrientation: $selectedSubtitleOrientation)
        case .dubbing:
          EditorDubbingOptions()
        }
      }
      .animation(.easeInOut(duration: 0.2), value: selectedEnhanceModule)
    }
  }
}
