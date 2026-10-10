import Foundation

@MainActor
final class TTSSessionRuntime {
  static let shared = TTSSessionRuntime()

  private let ttsService: MLXTTSService
  private let historyRuntime: HistoryRuntime

  init(
    ttsService: MLXTTSService = .shared,
    historyRuntime: HistoryRuntime? = nil
  ) {
    self.ttsService = ttsService
    self.historyRuntime = historyRuntime ?? .shared
  }

  func synthesize(
    text: String,
    modelDefinition: MLXTTSModelDefinition,
    voiceDescription: String?,
    referenceAudioURL: URL?,
    referenceText: String?,
    language: String?,
    variantPreference: TTSVariantPreference = .automatic
  ) async throws -> Data {
    try await ttsService.synthesize(
      text: text,
      modelDefinition: modelDefinition,
      voiceDescription: voiceDescription,
      referenceAudioURL: referenceAudioURL,
      referenceText: referenceText,
      language: language,
      variantPreference: variantPreference
    )
  }

  func persistSynthesisHistory(text: String, audioData: Data, sourceName: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let now = Date()

    var ttsBookmark: Data?
    let audioDir = TranscriptHistoryStore.ttsAudioDirectory()
    let audioURL = audioDir.appendingPathComponent("\(UUID().uuidString).wav")
    do {
      try audioData.write(to: audioURL, options: [.atomic])
      ttsBookmark = try audioURL.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    } catch {
      ttsBookmark = nil
    }

    var session = TranscriptSession(
      startTime: now,
      endTime: now,
      lines: [TranscriptLine(timestamp: 0, text: text)],
      recordingURL: nil,
      transcriberType: nil,
      modelVariant: nil,
      language: nil,
      source: .ttsSynthesis,
      sourceFileName: sourceName,
      ttsAudioBookmark: ttsBookmark
    )
    session.finish(at: now)
    historyRuntime.add(session)
  }
}
