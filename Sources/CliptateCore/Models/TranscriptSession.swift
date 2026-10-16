import Foundation

/// Distinguishes the origin of a transcript session.
public enum SessionSource: String, Codable, Equatable, Sendable {
  case voiceDictation
  case fileTranscription
  case ttsSynthesis

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    self = SessionSource(rawValue: raw) ?? .voiceDictation
  }
}

/// Represents a single line within a live transcript session.
public struct TranscriptLine: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let timestamp: TimeInterval
  public var text: String
  public var speakerId: Int?

  public init(id: UUID = UUID(), timestamp: TimeInterval, text: String, speakerId: Int? = nil) {
    self.id = id
    self.timestamp = timestamp
    self.text = text
    self.speakerId = speakerId
  }
}

/// Captures the lifecycle and content of a voice transcription session.
public struct TranscriptSession: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let startTime: Date
  public var endTime: Date?
  public private(set) var lines: [TranscriptLine]
  public var recordingURL: URL?
  public var transcriberType: TranscriberType?
  public var modelVariant: ModelVariant?
  public var language: Language?
  /// Origin of this session. Nil in archived data is treated as `.voiceDictation`.
  public var source: SessionSource?
  /// Last path component of the source file, set for `.fileTranscription` sessions.
  public var sourceFileName: String?
  /// Security-scoped bookmark data for the source video file (`.fileTranscription` only).
  /// Allows re-opening the original file from History even after app restart.
  public var sourceURLBookmark: Data?
  /// Security-scoped bookmark to the auto-saved WAV file for `.ttsSynthesis` sessions.
  /// Nil when the session predates this feature or the audio was never synthesized.
  public var ttsAudioBookmark: Data?
  /// Full transcription segments (with word-timing) saved for `.fileTranscription` sessions.
  /// Allows AI Cut to restore the editing state without re-transcribing.
  /// Translations are embedded in each segment's `translation` field.
  public var aiCutSegments: [Segment]?
  /// Original transcription used by Restore Original, retained across app restarts.
  public var aiCutOriginalSegments: [Segment]?
  /// Applied AI correction evidence; absent in legacy sessions.
  public var corrections: [TranscriptCorrection]?
  /// The translation target language last applied in AI Cut, if any.
  public var aiCutLastTranslatedLanguage: Language?
  /// Processed translations dict keyed by post-processing segment IDs.
  /// Stored separately because processed IDs (from splitting) may differ from raw segment IDs.
  public var aiCutProcessedTranslations: [String: SegmentTranslation]?
  /// Set of segment identifiers that have been marked as deleted in AI Cut.
  /// Persisted so that deletions survive app restart and history restoration.
  public var aiCutRemovedSegmentIDs: Set<SegmentIdentifier>?
  public var aiCutDubbedClips: [DubbedClip]?

  public init(
    id: UUID = UUID(),
    startTime: Date = Date(),
    endTime: Date? = nil,
    lines: [TranscriptLine] = [],
    recordingURL: URL? = nil,
    transcriberType: TranscriberType? = nil,
    modelVariant: ModelVariant? = nil,
    language: Language? = nil,
    source: SessionSource? = nil,
    sourceFileName: String? = nil,
    sourceURLBookmark: Data? = nil,
    ttsAudioBookmark: Data? = nil,
    aiCutSegments: [Segment]? = nil,
    aiCutOriginalSegments: [Segment]? = nil,
    corrections: [TranscriptCorrection]? = nil,
    aiCutLastTranslatedLanguage: Language? = nil,
    aiCutProcessedTranslations: [String: SegmentTranslation]? = nil,
    aiCutRemovedSegmentIDs: Set<SegmentIdentifier>? = nil,
    aiCutDubbedClips: [DubbedClip]? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.lines = lines
    self.recordingURL = recordingURL
    self.transcriberType = transcriberType
    self.modelVariant = modelVariant
    self.language = language
    self.source = source
    self.sourceFileName = sourceFileName
    self.sourceURLBookmark = sourceURLBookmark
    self.ttsAudioBookmark = ttsAudioBookmark
    self.aiCutSegments = aiCutSegments
    self.aiCutOriginalSegments = aiCutOriginalSegments
    self.corrections = corrections
    self.aiCutLastTranslatedLanguage = aiCutLastTranslatedLanguage
    self.aiCutProcessedTranslations = aiCutProcessedTranslations
    self.aiCutRemovedSegmentIDs = aiCutRemovedSegmentIDs
    self.aiCutDubbedClips = aiCutDubbedClips
  }

  /// Appends a new line to the session at the provided offset from the session start.
  public mutating func append(text: String, at offset: TimeInterval) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    lines.append(TranscriptLine(timestamp: max(0, offset), text: text))
  }

  /// Appends a new line with optional speaker ID.
  public mutating func append(text: String, at offset: TimeInterval, speakerId: Int?) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    lines.append(TranscriptLine(timestamp: max(0, offset), text: text, speakerId: speakerId))
  }

  /// Updates the text for the most recent line, useful for incremental streaming updates.
  public mutating func replaceLatestLine(with text: String, at offset: TimeInterval) {
    guard !lines.isEmpty else {
      append(text: text, at: offset)
      return
    }
    lines[lines.count - 1] = TranscriptLine(timestamp: max(0, offset), text: text)
  }

  /// Clears all transcript content but keeps the session metadata intact.
  public mutating func reset() {
    lines.removeAll(keepingCapacity: false)
    endTime = nil
  }

  /// Marks the session as finished.
  public mutating func finish(at date: Date = Date()) {
    endTime = date
  }

  /// Replaces the current transcript contents in one atomic operation.
  public mutating func replaceLines(with newLines: [TranscriptLine]) {
    lines = newLines
  }

  /// Returns all text joined by newlines for exporting to files or sharing.
  public var combinedText: String {
    lines.map { $0.text }.joined(separator: "\n")
  }

  /// Returns all text joined by newlines with speaker prefixes where available.
  public var speakerFormattedText: String {
    lines.map { line in
      if let speakerId = line.speakerId {
        return "Speaker \(speakerId): \(line.text)"
      }
      return line.text
    }.joined(separator: "\n")
  }

  /// Returns formatted text with configurable speaker and timestamp display.
  public func formattedText(showSpeaker: Bool, showTimestamp: Bool) -> String {
    lines.map { line in
      var prefix = ""
      if showTimestamp {
        let minutes = Int(line.timestamp) / 60
        let seconds = Int(line.timestamp) % 60
        prefix += "[\(String(format: "%02d:%02d", minutes, seconds))] "
      }
      if showSpeaker, let speakerId = line.speakerId {
        prefix += "Speaker \(speakerId): "
      }
      return prefix + line.text
    }.joined(separator: "\n")
  }
}

extension TranscriptSession: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, startTime, endTime, lines, recordingURL
    case transcriberType, modelVariant, language
    case source, sourceFileName, sourceURLBookmark
    case ttsAudioBookmark, aiCutSegments, aiCutTranslations, aiCutLastTranslatedLanguage
    case aiCutProcessedTranslations, aiCutRemovedSegmentIDs, aiCutOriginalSegments, corrections
    case aiCutDubbedClips
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    startTime = try container.decode(Date.self, forKey: .startTime)
    endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
    lines = try container.decode([TranscriptLine].self, forKey: .lines)
    recordingURL = try container.decodeIfPresent(URL.self, forKey: .recordingURL)
    transcriberType = try container.decodeIfPresent(TranscriberType.self, forKey: .transcriberType)
    modelVariant = try container.decodeIfPresent(ModelVariant.self, forKey: .modelVariant)
    language = try container.decodeIfPresent(Language.self, forKey: .language)
    source = try container.decodeIfPresent(SessionSource.self, forKey: .source)
    sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName)
    sourceURLBookmark = try container.decodeIfPresent(Data.self, forKey: .sourceURLBookmark)
    ttsAudioBookmark = try container.decodeIfPresent(Data.self, forKey: .ttsAudioBookmark)
    var decodedSegments = try container.decodeIfPresent([Segment].self, forKey: .aiCutSegments)

    // Backward compat: merge legacy aiCutTranslations into segments.
    // Old sessions stored translations separately keyed by the old computed id
    // ("\(startTime)-\(endTime)"). Decoded segments without a stored id got a fresh UUID,
    // so we match by the legacy computed-id algorithm.
    let legacyTranslations = try container.decodeIfPresent(
      [String: SegmentTranslation].self,
      forKey: .aiCutTranslations
    )
    if let legacyTranslations, !legacyTranslations.isEmpty, var segments = decodedSegments {
      for i in segments.indices where segments[i].translation == nil {
        let legacyKey = "\(segments[i].startTime)-\(segments[i].endTime)"
        if let t = legacyTranslations[legacyKey] {
          segments[i].translation = t
        }
      }
      decodedSegments = segments
    }

    aiCutSegments = decodedSegments
    aiCutOriginalSegments = try container.decodeIfPresent([Segment].self, forKey: .aiCutOriginalSegments)
    corrections = try container.decodeIfPresent([TranscriptCorrection].self, forKey: .corrections)
    aiCutLastTranslatedLanguage = try container.decodeIfPresent(
      Language.self,
      forKey: .aiCutLastTranslatedLanguage
    )
    aiCutProcessedTranslations = try container.decodeIfPresent(
      [String: SegmentTranslation].self,
      forKey: .aiCutProcessedTranslations
    )
    aiCutRemovedSegmentIDs = try container.decodeIfPresent(
      Set<SegmentIdentifier>.self,
      forKey: .aiCutRemovedSegmentIDs
    )
    aiCutDubbedClips = try container.decodeIfPresent([DubbedClip].self, forKey: .aiCutDubbedClips)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(startTime, forKey: .startTime)
    try container.encodeIfPresent(endTime, forKey: .endTime)
    try container.encode(lines, forKey: .lines)
    try container.encodeIfPresent(recordingURL, forKey: .recordingURL)
    try container.encodeIfPresent(transcriberType, forKey: .transcriberType)
    try container.encodeIfPresent(modelVariant, forKey: .modelVariant)
    try container.encodeIfPresent(language, forKey: .language)
    try container.encodeIfPresent(source, forKey: .source)
    try container.encodeIfPresent(sourceFileName, forKey: .sourceFileName)
    try container.encodeIfPresent(sourceURLBookmark, forKey: .sourceURLBookmark)
    try container.encodeIfPresent(ttsAudioBookmark, forKey: .ttsAudioBookmark)
    try container.encodeIfPresent(aiCutSegments, forKey: .aiCutSegments)
    try container.encodeIfPresent(aiCutOriginalSegments, forKey: .aiCutOriginalSegments)
    try container.encodeIfPresent(corrections, forKey: .corrections)
    try container.encodeIfPresent(aiCutLastTranslatedLanguage, forKey: .aiCutLastTranslatedLanguage)
    try container.encodeIfPresent(aiCutProcessedTranslations, forKey: .aiCutProcessedTranslations)
    try container.encodeIfPresent(aiCutRemovedSegmentIDs, forKey: .aiCutRemovedSegmentIDs)
    try container.encodeIfPresent(aiCutDubbedClips, forKey: .aiCutDubbedClips)
  }
}

extension TranscriptSession {
  /// Synchronizes the session's lines with the latest streaming snapshot, keeping ordering stable.
  public mutating func applyStreamingSnapshot(_ text: String, at offset: TimeInterval) {
    let sanitizedSegments = text.split(whereSeparator: \.isNewline).map { String($0) }
    let targetSegments = sanitizedSegments.isEmpty ? [text] : sanitizedSegments

    if lines.isEmpty {
      for segment in targetSegments {
        append(text: segment, at: offset)
      }
      return
    }

    let overlapCount = min(lines.count, targetSegments.count)
    for index in 0..<overlapCount {
      let segment = targetSegments[index]
      if lines[index].text != segment {
        lines[index].text = segment
      }
    }

    if targetSegments.count > lines.count {
      for index in lines.count..<targetSegments.count {
        append(text: targetSegments[index], at: offset)
      }
    } else if targetSegments.count < lines.count {
      lines.removeLast(lines.count - targetSegments.count)
    }
  }
}
