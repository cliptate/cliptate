import CliptateCore
import Foundation

struct FileTranscriptionHistorySessionFactory {
  static func makeSession(
    existingSessionID: UUID? = nil,
    url: URL,
    segments: [Segment],
    originalSegments: [Segment]? = nil,
    lastTranslatedLanguage: Language? = nil,
    processedTranslations: [String: SegmentTranslation]? = nil,
    removedSegmentIDs: Set<SegmentIdentifier>? = nil,
    sourceURLBookmark: Data? = nil,
    duration: TimeInterval,
    transcriberType: TranscriberType,
    modelVariant: ModelVariant,
    language: Language
  ) throws -> TranscriptSession {
    let lines = segments.compactMap { segment -> TranscriptLine? in
      let text = resolvedText(for: segment)
      guard !text.isEmpty else { return nil }
      return TranscriptLine(
        timestamp: segment.startTime,
        text: text,
        speakerId: segment.speakerId
      )
    }
    let endDate = Date()
    let startDate = endDate.addingTimeInterval(-max(0, duration))
    let bookmark = sourceURLBookmark ?? (try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ))

    var session = TranscriptSession(
      id: existingSessionID ?? UUID(),
      startTime: startDate,
      endTime: endDate,
      lines: lines,
      recordingURL: nil,
      transcriberType: transcriberType,
      modelVariant: modelVariant,
      language: language,
      source: .fileTranscription,
      sourceFileName: url.lastPathComponent,
      sourceURLBookmark: bookmark,
      aiCutSegments: segments,
      aiCutOriginalSegments: originalSegments,
      aiCutLastTranslatedLanguage: lastTranslatedLanguage,
      aiCutProcessedTranslations: processedTranslations,
      aiCutRemovedSegmentIDs: removedSegmentIDs
    )
    session.finish(at: endDate)
    return session
  }

  private static func resolvedText(for segment: Segment) -> String {
    let directText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !directText.isEmpty {
      return directText
    }
    guard let words = segment.words else { return "" }
    return WordTimingTextComposer.composeText(from: words)
  }
}
