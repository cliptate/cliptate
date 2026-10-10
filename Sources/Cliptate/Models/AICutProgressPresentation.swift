import Foundation

struct AICutProgressPresentation: Equatable {

  enum DisplayPhase: Equatable {
    case modelInit
    case transcribing
    case terminal
  }

  let title: String
  let detail: String
  let currentFileName: String?
  let fractionComplete: Double
  let displayPhase: DisplayPhase
  let displayFraction: Double

  /// Full init with model-init awareness (used by AICutProgressView).
  init(
    batch: AICutBatchContext?,
    statusMessage: String? = nil,
    isInitializingModel: Bool = false,
    modelDownloadProgress: ModelDownloadProgress? = nil
  ) {
    let items = batch?.items ?? []
    let total = items.count
    let runningItem = items.first {
      if case .running = $0.status { return true }
      return false
    }
    let liveStatusMessage = Self.liveStatusMessage(from: statusMessage)
    let terminalCount = items.filter {
      switch $0.status {
      case .succeeded, .failed:
        return true
      case .pending, .running:
        return false
      }
    }.count
    let allPending = !items.isEmpty && items.allSatisfy {
      if case .pending = $0.status { return true }
      return false
    }
    let baseFraction = total > 0 ? Double(terminalCount) / Double(total) : 0
    let fractionWithRunningStatus = Self.fractionComplete(
      baseFraction: baseFraction,
      runningItemPercent: Self.runningItemPercent(from: statusMessage),
      terminalCount: terminalCount,
      total: total
    )

    // Terminal states (failed/cancelled) always take precedence
    if let state = Self.statusState(from: statusMessage) {
      title = state.title
      detail = state.detail
      currentFileName = nil
      fractionComplete = baseFraction
      displayPhase = .terminal
      displayFraction = baseFraction
      return
    }

    // Model initialization phase
    if isInitializingModel {
      title = String(localized: "Preparing transcription…", comment: "AI Cut batch progress title when preparing")
      detail = liveStatusMessage ?? Self.modelPreparationMessage(from: modelDownloadProgress?.currentStep)
      currentFileName = nil
      fractionComplete = fractionWithRunningStatus
      displayPhase = .modelInit
      displayFraction = min(max(Double(modelDownloadProgress?.progress ?? 0), 0), 1)
      return
    }

    // Transcription phase
    guard total > 0, !allPending else {
      title = String(localized: "Preparing transcription…", comment: "AI Cut batch progress title when preparing")
      detail = liveStatusMessage ?? String(localized: "Waiting for next file…", comment: "AI Cut batch progress detail when waiting")
      currentFileName = nil
      fractionComplete = fractionWithRunningStatus
      displayPhase = .transcribing
      displayFraction = fractionWithRunningStatus
      return
    }

    title = String(localized: "Transcribing \(terminalCount)/\(total)", comment: "AI Cut batch progress title with count")
    detail = liveStatusMessage
      ?? runningItem?.url.lastPathComponent
      ?? String(localized: "Finishing up…", comment: "AI Cut batch progress detail when wrapping up")
    currentFileName = runningItem?.url.lastPathComponent
    fractionComplete = fractionWithRunningStatus
    displayPhase = .transcribing
    displayFraction = fractionWithRunningStatus
  }

  private static func statusState(from statusMessage: String?) -> (title: String, detail: String)? {
    guard let statusMessage = statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
      !statusMessage.isEmpty
    else {
      return nil
    }

    let normalized = statusMessage.lowercased()
    if normalized.contains("failed:") {
      return (String(localized: "Transcription failed", comment: "AI Cut progress title when transcription failed"), statusMessage)
    }
    if normalized.contains("cancelled") {
      return (String(localized: "Transcription cancelled", comment: "AI Cut progress title when transcription was cancelled"), statusMessage)
    }
    return nil
  }

  private static func liveStatusMessage(from statusMessage: String?) -> String? {
    guard
      let statusMessage = cleanedStatusMessage(from: statusMessage),
      !statusMessage.isEmpty,
      statusState(from: statusMessage) == nil
    else {
      return nil
    }

    return friendlyStatusMessage(from: statusMessage)
  }

  private static func runningItemPercent(from statusMessage: String?) -> Double? {
    guard let statusMessage else { return nil }

    let pattern = #"\((\d{1,3})%\)|(\d{1,3})%"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.matches(
        in: statusMessage,
        range: NSRange(statusMessage.startIndex..., in: statusMessage)
      ).last
    else {
      return nil
    }

    for captureIndex in 1..<match.numberOfRanges {
      let range = match.range(at: captureIndex)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: statusMessage) else {
        continue
      }
      guard let percentage = Double(statusMessage[swiftRange]) else { continue }
      return min(max(percentage / 100, 0), 1)
    }

    return nil
  }

  private static func cleanedStatusMessage(from statusMessage: String?) -> String? {
    guard let statusMessage = statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
      !statusMessage.isEmpty
    else {
      return nil
    }

    let patterns = [
      #"^\[\d+/\d+\]\s*"#,
      #"\s*-\s*Est\.\s*\d+:\d+\s*remaining"#,
      #"\s*\((\d{1,3})%\)\s*$"#
    ]

    let cleaned = patterns.reduce(statusMessage) { partial, pattern in
      partial.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return cleaned.isEmpty ? nil : cleaned
  }

  private static func friendlyStatusMessage(from cleanedStatusMessage: String) -> String {
    let normalized = cleanedStatusMessage.lowercased()

    if normalized.contains("vad") && normalized.contains("asr") && normalized.contains("align") {
      return String(localized: "Analyzing speech and timing…", comment: "AI Cut batch progress detail when the speech and timing pipeline is running")
    }

    if normalized.contains("result") || normalized.contains("finaliz") || normalized.contains("completed") {
      return String(localized: "Finishing up…", comment: "AI Cut batch progress detail when wrapping up")
    }

    if normalized.contains("align") || normalized.contains("timing") {
      return String(localized: "Matching words to timing…", comment: "AI Cut batch progress detail when timing words")
    }

    if normalized.contains("transcrib") || normalized.contains("recogniz") || normalized.contains("asr") {
      return String(localized: "Converting speech to text…", comment: "AI Cut batch progress detail when transcribing speech")
    }

    if normalized.contains("speech segment") || normalized.contains("vad") || normalized.contains("spoken") || normalized.contains("detect") {
      return String(localized: "Finding spoken parts…", comment: "AI Cut batch progress detail when detecting speech")
    }

    if normalized.contains("load") || normalized.contains("prepar") || normalized.contains("start") || normalized.contains("decod") || normalized.contains("audio") {
      return String(localized: "Getting audio ready…", comment: "AI Cut batch progress detail when preparing audio")
    }

    return String(localized: "Processing your file…", comment: "AI Cut batch progress detail fallback")
  }

  private static func modelPreparationMessage(from currentStep: String?) -> String {
    guard let currentStep = currentStep?.trimmingCharacters(in: .whitespacesAndNewlines),
      !currentStep.isEmpty
    else {
      return String(localized: "Loading required model…", comment: "AI Cut batch progress detail when loading a required model")
    }

    if currentStep.lowercased().contains("download") {
      return String(localized: "Downloading required model…", comment: "AI Cut batch progress detail when downloading a required model")
    }

    return String(localized: "Loading required model…", comment: "AI Cut batch progress detail when loading a required model")
  }

  private static func fractionComplete(
    baseFraction: Double,
    runningItemPercent: Double?,
    terminalCount: Int,
    total: Int
  ) -> Double {
    guard total > 0, let runningItemPercent, terminalCount < total else {
      return min(max(baseFraction, 0), 1)
    }

    let combined = (Double(terminalCount) + runningItemPercent) / Double(total)
    return min(max(combined, baseFraction), 1)
  }
}
