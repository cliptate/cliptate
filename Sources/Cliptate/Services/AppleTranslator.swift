import Foundation
import Translation

enum AppleTranslationError: LocalizedError {
  case unsupportedLanguagePair(source: Language, target: Language)
  case emptyInput
  case platformUnavailable

  var errorDescription: String? {
    switch self {
    case .unsupportedLanguagePair(let source, let target):
      return "Translation not supported between \(source.displayName) and \(target.displayName)."
    case .emptyInput:
      return "No text available for translation."
    case .platformUnavailable:
      return AppleTranslationAvailability.minimumRequirementMessage
    }
  }
}

@available(macOS 15.0, *)
@MainActor
protocol AppleTranslationSessionHandling {
  func prepareTranslation() async throws
  func translateBatchResponses(_ requests: [TranslationSession.Request]) async throws -> [TranslationSession.Response]
}

@available(macOS 15.0, *)
@MainActor
extension TranslationSession: AppleTranslationSessionHandling {
  func translateBatchResponses(_ requests: [TranslationSession.Request]) async throws -> [TranslationSession.Response] {
    var responses: [TranslationSession.Response] = []
    for try await response in translate(batch: requests) {
      responses.append(response)
    }
    return responses
  }
}

@available(macOS 15.0, *)
@MainActor
struct AppleTranslator {
  static func translateSegments(
    _ segments: [Segment],
    from source: Language,
    to target: Language,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [String: SegmentTranslation] {
    guard AppleTranslationAvailability.isRuntimeSupported else {
      throw AppleTranslationError.platformUnavailable
    }
    guard #available(macOS 26.0, *) else {
      throw AppleTranslationError.platformUnavailable
    }

    let session = try await makeSession(from: source, to: target)
    return try await translateSegments(
      segments,
      using: session,
      from: source,
      to: target,
      progress: progress
    )
  }

  static func translateSegments<Session: AppleTranslationSessionHandling>(
    _ segments: [Segment],
    using session: Session,
    from source: Language,
    to target: Language,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [String: SegmentTranslation] {
    guard !segments.isEmpty else { throw AppleTranslationError.emptyInput }

    var results = Array(repeating: "", count: segments.count)
    var completed = 0

    var requests: [TranslationSession.Request] = []
    requests.reserveCapacity(segments.count)

    for (idx, segment) in segments.enumerated() {
      let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        completed += 1
        progress?(completed, segments.count)
        continue
      }

      requests.append(
        TranslationSession.Request(
          sourceText: trimmed,
          clientIdentifier: String(idx)
        )
      )
    }

    guard !requests.isEmpty else { return [:] }

    do {
      try await Self.prepareWithRetry(session)

      for response in try await session.translateBatchResponses(requests) {
        guard let identifier = response.clientIdentifier,
          let index = Int(identifier),
          results.indices.contains(index)
        else { continue }

        results[index] = response.targetText
        completed += 1
        progress?(completed, segments.count)
      }

      if completed < segments.count {
        progress?(segments.count, segments.count)
      }

      var translations: [String: SegmentTranslation] = [:]
      for (segment, translatedText) in zip(segments, results) {
        let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        translations[segment.id] = SegmentTranslation(text: trimmed, language: target)
      }

      return translations
    } catch {
      throw mapTranslationError(error, source: source, target: target)
    }
  }

  private static func mapTranslationError(
    _ error: Error,
    source: Language,
    target: Language
  ) -> Error {
    guard let translationError = error as? TranslationError else { return error }

    switch translationError {
    case TranslationError.unsupportedSourceLanguage,
      TranslationError.unsupportedTargetLanguage,
      TranslationError.unsupportedLanguagePairing:
      return AppleTranslationError.unsupportedLanguagePair(source: source, target: target)
    default:
      return translationError
    }
  }

  @available(macOS 26.0, *)
  private static func makeSession(
    from source: Language,
    to target: Language
  ) async throws -> TranslationSession {
    let sourceLocale = Locale.Language(identifier: source.rawValue)
    let targetLocale = Locale.Language(identifier: target.rawValue)

    let availability = LanguageAvailability()
    let status = await availability.status(from: sourceLocale, to: targetLocale)

    switch status {
    case .installed, .supported:
      break
    case .unsupported:
      throw AppleTranslationError.unsupportedLanguagePair(source: source, target: target)
    @unknown default:
      throw AppleTranslationError.unsupportedLanguagePair(source: source, target: target)
    }

    return TranslationSession(installedSource: sourceLocale, target: targetLocale)
  }

  /// Prepare the translation session with a single retry for cases where
  /// language resources need downloading (status `.supported` but not `.installed`).
  static func prepareWithRetry(_ session: some AppleTranslationSessionHandling) async throws {
    do {
      try await session.prepareTranslation()
    } catch {
      // First attempt may fail while language resources are being prepared.
      // Wait briefly and retry once.
      try await Task.sleep(for: .seconds(2))
      try await session.prepareTranslation()
    }
  }

}
