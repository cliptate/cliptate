import Foundation
import SwiftUI

/// Shared download state for ModelsView, lifted out of view @State so it survives navigation.
@MainActor
final class ModelDownloadStateStore: ObservableObject {
  static let shared = ModelDownloadStateStore()

  @Published var progressMap: [ModelVariant: ModelDownloadProgress] = [:]
  @Published var downloadedMap: [ModelVariant: Bool] = [:]
  @Published var errorMap: [ModelVariant: String] = [:]

  func setProgress(_ progress: ModelDownloadProgress, for model: ModelVariant) {
    var next = progressMap
    next[model] = progress
    progressMap = next
  }

  func clearProgress(for model: ModelVariant) {
    var next = progressMap
    next[model] = nil
    progressMap = next
  }

  func progress(for model: ModelVariant) -> ModelDownloadProgress? {
    progressMap[model]
  }

  func setDownloaded(_ isDownloaded: Bool, for model: ModelVariant) {
    var next = downloadedMap
    next[model] = isDownloaded
    downloadedMap = next
  }

  func setError(_ message: String?, for model: ModelVariant) {
    var next = errorMap
    next[model] = message
    errorMap = next
  }
}
