import CryptoKit
import Darwin
import Foundation

public struct CLIError: LocalizedError, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

public enum CLILocalization {
  // The embedded executable reads the application's compiled string catalog.
  public static var bundle: Bundle {
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    return app.pathExtension == "app" ? (Bundle(url: app) ?? .main) : .main
  }
}

public struct CLIEndpoint: Sendable {
  public static var port: UInt16 { AppIdentity.current.cliPort() }
  private let identity: AppIdentity
  public let id: String
  public let secret: String

  public init(identity: AppIdentity = .current) {
    self.identity = identity
    id = UUID().uuidString
    secret = SymmetricKey(size: .bits256).withUnsafeBytes { bytes in
      bytes.map { String(format: "%02x", $0) }.joined()
    }
  }

  public init?(url: URL, identity: AppIdentity = .current) {
    guard url.scheme == identity.cliURLScheme, url.host == "connect",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let items = components.queryItems, items.count == 2,
      let id = items.first(where: { $0.name == "id" })?.value, UUID(uuidString: id) != nil,
      let secret = items.first(where: { $0.name == "secret" })?.value,
      secret.utf8.count == 64, secret.allSatisfy({ $0.isHexDigit })
    else { return nil }
    self.id = id
    self.secret = secret
    self.identity = identity
  }

  public var url: URL {
    var components = URLComponents()
    components.scheme = identity.cliURLScheme
    components.host = "connect"
    components.queryItems = [.init(name: "id", value: id), .init(name: "secret", value: secret)]
    return components.url!
  }

  public func proof(for role: String) -> String {
    let key = SymmetricKey(data: Data(secret.utf8))
    let code = HMAC<SHA256>.authenticationCode(for: Data("\(role):\(id):v1".utf8), using: key)
    return Data(code).base64EncodedString()
  }
}

public enum CLIOperation: String, Codable, Sendable {
  case transcribe, tts, dictionaryList, dictionaryAdd, dictionaryRemove, history
}

public struct CLIRequest: Codable, Sendable {
  public var operation: CLIOperation
  public var authorization: String?
  public var bookmark: Data?
  public var model: String?
  public var language: String?
  public var useDictionary: Bool
  public var download: Bool
  public var entries: [String]
  public var tts: CLITTSParameters?
  public var outputBookmark: Data?
  public var history: CLIHistoryQuery?

  public init(
    operation: CLIOperation, bookmark: Data? = nil, model: String? = nil,
    language: String? = nil, useDictionary: Bool = true, download: Bool = false,
    entries: [String] = [], tts: CLITTSParameters? = nil, outputBookmark: Data? = nil,
    history: CLIHistoryQuery? = nil
  ) {
    self.operation = operation
    self.bookmark = bookmark
    self.model = model
    self.language = language
    self.useDictionary = useDictionary
    self.download = download
    self.entries = entries
    self.tts = tts
    self.outputBookmark = outputBookmark
    self.history = history
  }
}

/// Optional payload keeps transcription and dictionary requests compatible with protocol 1.
public struct CLITTSParameters: Codable, Sendable {
  public var text: String
  public var voice: String?
  public var emotion: String?
  public var referenceText: String?
  public var variant: String?

  public init(
    text: String, voice: String? = nil, emotion: String? = nil,
    referenceText: String? = nil, variant: String? = nil
  ) {
    self.text = text
    self.voice = voice
    self.emotion = emotion
    self.referenceText = referenceText
    self.variant = variant
  }
}

public struct CLIAudioResult: Codable, Sendable {
  public var file: String
  public let model: String
  public let bytes: Int
  public init(file: String, model: String, bytes: Int) {
    self.file = file
    self.model = model
    self.bytes = bytes
  }
}

public struct CLISegment: Codable, Sendable, Equatable {
  public let id: String
  public let text: String
  public let start: Double
  public let end: Double
  public let speakerId: Int?
  public init(id: String, text: String, start: Double, end: Double, speakerId: Int?) {
    self.id = id
    self.text = text
    self.start = start
    self.end = end
    self.speakerId = speakerId
  }
}

public struct CLIFileResult: Codable, Sendable {
  public var file: String
  public let model: String?
  public let duration: Double?
  public let segments: [CLISegment]
  public let error: String?
  public init(
    file: String, model: String? = nil, duration: Double? = nil,
    segments: [CLISegment] = [], error: String? = nil
  ) {
    self.file = file
    self.model = model
    self.duration = duration
    self.segments = segments
    self.error = error
  }
}

public struct CLIEvent: Codable, Sendable {
  public enum Kind: String, Codable, Sendable { case hello, progress, result, failure }
  public let kind: Kind
  public let token: String?
  public let message: String?
  public let transcript: CLIFileResult?
  public let entries: [String]?
  public let audio: CLIAudioResult?
  public let history: CLIHistoryPage?
  public init(
    _ kind: Kind, token: String? = nil, message: String? = nil,
    transcript: CLIFileResult? = nil, entries: [String]? = nil, audio: CLIAudioResult? = nil,
    history: CLIHistoryPage? = nil
  ) {
    self.kind = kind
    self.token = token
    self.message = message
    self.transcript = transcript
    self.entries = entries
    self.audio = audio
    self.history = history
  }
}

/// Only textual, portable history fields cross the CLI transport. No audio paths or bookmarks.
public struct CLIHistoryQuery: Codable, Equatable, Sendable {
  public enum Action: String, Codable, Sendable { case list, show, corrections }
  public var action: Action
  public var sessionID: String?
  public var source: String?
  public var since: String?
  public var until: String?
  public var search: String?
  public var correctionsOnly: Bool
  public var limit: Int
  public var cursor: String?

  public init(action: Action, sessionID: String? = nil, source: String? = nil,
    since: String? = nil, until: String? = nil, search: String? = nil,
    correctionsOnly: Bool = false, limit: Int = 50, cursor: String? = nil) {
    self.action = action
    self.sessionID = sessionID
    self.source = source
    self.since = since
    self.until = until
    self.search = search
    self.correctionsOnly = correctionsOnly
    self.limit = limit
    self.cursor = cursor
  }

  public static func date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }

  public func validate() throws {
    guard (1...200).contains(limit),
      source == nil || ["voiceDictation", "fileTranscription", "ttsSynthesis"].contains(source!),
      sessionID == nil || UUID(uuidString: sessionID!) != nil,
      action != .show || (sessionID != nil && source == nil && since == nil && until == nil
        && search == nil && !correctionsOnly),
      since == nil || Self.date(since!) != nil,
      until == nil || Self.date(until!) != nil,
      cursor == nil || (cursor!.utf8.count <= 16_384 && !cursor!.isEmpty)
    else { throw Self.invalidArguments() }
    if let since, let until, let start = Self.date(since), let end = Self.date(until), start > end {
      throw Self.invalidArguments()
    }
  }

  public static func invalidArguments() -> CLIError {
    CLIError(String(localized: "Invalid history arguments. Run cliptate history --help.", bundle: CLILocalization.bundle))
  }
}

public struct CLIHistorySession: Codable, Sendable {
  public let id: String
  public let startTime: String
  public let endTime: String?
  public let source: String
  public let sourceFileName: String?
  public let language: String?
  public let model: String?
  public let lineCount: Int
  public let correctionCount: Int
  public let preview: String

  public init(id: String, startTime: String, endTime: String?, source: String,
    sourceFileName: String?, language: String?, model: String?, lineCount: Int,
    correctionCount: Int, preview: String) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.source = source
    self.sourceFileName = sourceFileName
    self.language = language
    self.model = model
    self.lineCount = lineCount
    self.correctionCount = correctionCount
    self.preview = preview
  }
}

public struct CLIHistoryLine: Codable, Sendable {
  public let id: String
  public let timestamp: Double
  public let text: String
  public let speakerId: Int?
  public init(id: String, timestamp: Double, text: String, speakerId: Int?) {
    self.id = id
    self.timestamp = timestamp
    self.text = text
    self.speakerId = speakerId
  }
}

public struct CLIHistoryCorrection: Codable, Sendable {
  public let id: String
  public let batchID: String
  public let sessionID: String
  public let relatedSessionIDs: [String]
  public let source: String
  public let sourceFileName: String?
  public let recordedAt: String
  public let kind: String
  public let status: String
  public let statusChangedAt: String?
  public let original: String
  public let corrected: String
  public let originalContext: String
  public let correctedContext: String
  public let targetID: String?
  public let timestamp: Double?
  public let provider: String
  public let model: String
  public let language: String

  public init(id: String, batchID: String, sessionID: String, relatedSessionIDs: [String],
    source: String, sourceFileName: String?, recordedAt: String, kind: String, status: String,
    statusChangedAt: String?, original: String, corrected: String, originalContext: String,
    correctedContext: String, targetID: String?, timestamp: Double?, provider: String,
    model: String, language: String) {
    self.id = id
    self.batchID = batchID
    self.sessionID = sessionID
    self.relatedSessionIDs = relatedSessionIDs
    self.source = source
    self.sourceFileName = sourceFileName
    self.recordedAt = recordedAt
    self.kind = kind
    self.status = status
    self.statusChangedAt = statusChangedAt
    self.original = original
    self.corrected = corrected
    self.originalContext = originalContext
    self.correctedContext = correctedContext
    self.targetID = targetID
    self.timestamp = timestamp
    self.provider = provider
    self.model = model
    self.language = language
  }
}

public struct CLIHistoryPage: Codable, Sendable {
  public var sessions: [CLIHistorySession] = []
  public var lines: [CLIHistoryLine] = []
  public var corrections: [CLIHistoryCorrection] = []
  public var nextCursor: String?
  public let schemaVersion = 1
  public init() {}

  // The schema identifies the page we produce and stays fixed when decoding.
  private enum CodingKeys: String, CodingKey {
    case sessions, lines, corrections, nextCursor, schemaVersion
  }
}
