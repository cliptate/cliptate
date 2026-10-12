import Foundation

/// Evidence of an AI edit that was actually applied. The text and provenance never change;
/// status describes subsequent restoration or transcription, rather than user approval.
public struct TranscriptCorrection: Identifiable, Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case phrase, dictation }
  public enum Status: String, Codable, Sendable { case applied, reverted, superseded }

  public let id: UUID
  public let batchID: UUID
  public let recordedAt: Date
  public let kind: Kind
  public let original: String
  public let corrected: String
  public let originalContext: String
  public let correctedContext: String
  public let targetID: String?
  public let timestamp: TimeInterval?
  public let provider: String
  public let model: String
  public let language: String
  public let relatedSessionIDs: [UUID]
  public var status: Status = .applied
  public var statusChangedAt: Date?

  public init(
    id: UUID = UUID(), batchID: UUID = UUID(), recordedAt: Date = Date(), kind: Kind,
    original: String, corrected: String, originalContext: String, correctedContext: String,
    targetID: String? = nil, timestamp: TimeInterval? = nil, provider: String, model: String,
    language: String, relatedSessionIDs: [UUID] = []
  ) {
    self.id = id
    self.batchID = batchID
    self.recordedAt = recordedAt
    self.kind = kind
    self.original = original
    self.corrected = corrected
    self.originalContext = originalContext
    self.correctedContext = correctedContext
    self.targetID = targetID
    self.timestamp = timestamp
    self.provider = provider
    self.model = model
    self.language = language
    self.relatedSessionIDs = relatedSessionIDs
  }
}
