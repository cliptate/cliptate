import CliptateCore
import Foundation
import SwiftUI

enum AICutFlowPhase: Equatable {
  case landing
  case importSetup
  case transcribing
  case readyToEdit
  case editing
}

struct AICutBatchItem: Equatable, Identifiable {
  enum Status: Equatable {
    case pending
    case running
    case succeeded
    case failed(String)
  }

  let id: URL
  let url: URL
  var status: Status
}

struct AICutBatchContext: Equatable {
  var urls: [URL]
  var language: Language
  var items: [AICutBatchItem]
}

@MainActor
final class AICutFlowModel: ObservableObject {
  @Published private(set) var phase: AICutFlowPhase = .landing
  @Published private(set) var pendingURLs: [URL] = []
  @Published var selectedLanguage: Language = .english
  @Published private(set) var currentBatch: AICutBatchContext?
  @Published private(set) var successfulEditingURLs: [URL] = []
  @Published private(set) var failedURLs: [URL] = []
  @Published private(set) var lastErrorSummary: String?

  func beginImport(urls: [URL]) {
    guard phase != .transcribing, phase != .readyToEdit, phase != .editing else { return }

    let normalized = Array(NSOrderedSet(array: urls.filter(\.isFileURL))) as? [URL] ?? []
    guard !normalized.isEmpty else {
      phase = .landing
      pendingURLs = []
      currentBatch = nil
      return
    }

    pendingURLs = normalized
    currentBatch = nil
    successfulEditingURLs = []
    failedURLs = []
    lastErrorSummary = nil
    phase = .importSetup
  }

  func removePendingURL(_ url: URL) {
    pendingURLs.removeAll { $0 == url }
    if pendingURLs.isEmpty {
      cancelImport()
    }
  }

  func cancelImport() {
    pendingURLs = []
    currentBatch = nil
    successfulEditingURLs = []
    failedURLs = []
    lastErrorSummary = nil
    phase = .landing
  }

  @discardableResult
  func startBatch() -> AICutBatchContext {
    let batch = AICutBatchContext(
      urls: pendingURLs,
      language: selectedLanguage,
      items: pendingURLs.map { AICutBatchItem(id: $0, url: $0, status: .pending) }
    )
    currentBatch = batch
    successfulEditingURLs = []
    failedURLs = []
    lastErrorSummary = nil
    phase = .transcribing
    return batch
  }

  func markFileRunning(_ url: URL) {
    updateStatus(for: url, status: .running)
  }

  func markFileSucceeded(_ url: URL) {
    updateStatus(for: url, status: .succeeded)
    finalizeIfNeeded()
  }

  func markFileFailed(_ url: URL, message: String) {
    lastErrorSummary = message
    updateStatus(for: url, status: .failed(message))
    finalizeIfNeeded()
  }

  func establishEditingSession() {
    guard phase == .readyToEdit || phase == .landing else { return }
    phase = .editing
  }

  private func updateStatus(for url: URL, status: AICutBatchItem.Status) {
    guard var batch = currentBatch,
      let index = batch.items.firstIndex(where: { $0.url == url })
    else { return }

    batch.items[index].status = status
    currentBatch = batch
    successfulEditingURLs = batch.items.compactMap { item in
      guard item.status == .succeeded else { return nil }
      return item.url
    }
    failedURLs = batch.items.compactMap { item in
      guard case .failed = item.status else { return nil }
      return item.url
    }
  }

  private func finalizeIfNeeded() {
    guard let batch = currentBatch else { return }

    let hasPending = batch.items.contains {
      switch $0.status {
      case .pending, .running:
        return true
      case .succeeded, .failed:
        return false
      }
    }

    guard !hasPending else { return }
    phase = successfulEditingURLs.isEmpty ? .landing : .readyToEdit
  }
}
