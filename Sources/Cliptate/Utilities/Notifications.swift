import CliptateCore
import Foundation

extension Notification.Name {
  static let openModelsLibrary = Notification.Name("Cliptate.openModelsLibrary")
  static let openVoiceToText = Notification.Name("Cliptate.openVoiceToText")
  static let modelArtifactsDidChange = Notification.Name("Cliptate.modelArtifactsDidChange")
  /// Posted when History wants to navigate the main window to the AI Cut section.
  static let openAICutSection = Notification.Name("Cliptate.openAICutSection")
}

enum ModelArtifactStatusNotifier {
  private static let modelRawValueKey = "modelRawValue"

  static func postChange(for model: ModelVariant) {
    let userInfo = [modelRawValueKey: model.rawValue]
    if Thread.isMainThread {
      NotificationCenter.default.post(
        name: .modelArtifactsDidChange,
        object: nil,
        userInfo: userInfo
      )
      return
    }

    Task { @MainActor in
      NotificationCenter.default.post(
        name: .modelArtifactsDidChange,
        object: nil,
        userInfo: userInfo
      )
    }
  }
}
