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
  public static var port: UInt16 { UInt16(49152 + getuid() % 16000) }
  public let id: String
  public let secret: String

  public init() {
    id = UUID().uuidString
    secret = SymmetricKey(size: .bits256).withUnsafeBytes { bytes in
      bytes.map { String(format: "%02x", $0) }.joined()
    }
  }

  public init?(url: URL) {
    guard url.scheme == "cliptate-cli", url.host == "connect",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let items = components.queryItems, items.count == 2,
      let id = items.first(where: { $0.name == "id" })?.value, UUID(uuidString: id) != nil,
      let secret = items.first(where: { $0.name == "secret" })?.value,
      secret.utf8.count == 64, secret.allSatisfy({ $0.isHexDigit })
    else { return nil }
    self.id = id
    self.secret = secret
  }

  public var url: URL {
    var components = URLComponents()
    components.scheme = "cliptate-cli"
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
  case transcribe, dictionaryList, dictionaryAdd, dictionaryRemove
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

  public init(
    operation: CLIOperation, bookmark: Data? = nil, model: String? = nil,
    language: String? = nil, useDictionary: Bool = true, download: Bool = false,
    entries: [String] = []
  ) {
    self.operation = operation
    self.bookmark = bookmark
    self.model = model
    self.language = language
    self.useDictionary = useDictionary
    self.download = download
    self.entries = entries
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
  public init(
    _ kind: Kind, token: String? = nil, message: String? = nil,
    transcript: CLIFileResult? = nil, entries: [String]? = nil
  ) {
    self.kind = kind
    self.token = token
    self.message = message
    self.transcript = transcript
    self.entries = entries
  }
}
