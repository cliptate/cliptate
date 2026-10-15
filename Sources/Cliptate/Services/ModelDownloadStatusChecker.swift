import CliptateCore
import Foundation
import SwiftUI

/// 模型下载状态检查器
actor ModelDownloadStatusChecker {
  static let shared = ModelDownloadStatusChecker()

  private init() {}
 
  /// 检查 MLX Whisper 模型是否已下载
  func isWhisperModelDownloaded(_ model: ModelVariant) async -> Bool {
    guard model.isWhisperModel else { return false }
    return await ModelDownloadManager.shared.isModelDownloaded(model)
  }

  /// 检查 Parakeet 模型是否已下载
  func isParakeetModelDownloaded(_ model: ModelVariant) async -> Bool {
    guard model.isParakeetModel else { return false }
    return await ModelDownloadManager.shared.isModelDownloaded(model)
  }

  /// 获取所有模型的状态
  func getAllModelStatuses() async -> [ModelVariant: Bool] {
    await ModelDownloadManager.shared.getStatuses(for: Array(ModelVariant.allCases))
  }

  /// 获取给定模型列表的状态
  func getStatuses(for models: [ModelVariant]) async -> [ModelVariant: Bool] {
    guard !models.isEmpty else { return [:] }
    return await ModelDownloadManager.shared.getStatuses(for: models)
  }
}

/// UI 使用的下载状态枚举
enum ModelDownloadStatus {
  case downloaded
  case notDownloaded
  case checking

  var displayText: String {
    switch self {
    case .downloaded:
      return "Downloaded"
    case .notDownloaded:
      return "Not Downloaded"
    case .checking:
      return "Checking..."
    }
  }

  var icon: String {
    switch self {
    case .downloaded:
      return "checkmark.circle.fill"
    case .notDownloaded:
      return "arrow.down.circle"
    case .checking:
      return "clock.circle"
    }
  }

  var iconColor: Color {
    switch self {
    case .downloaded:
      return .green
    case .notDownloaded:
      return .blue
    case .checking:
      return .orange
    }
  }
}
