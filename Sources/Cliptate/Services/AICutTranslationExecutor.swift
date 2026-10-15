import CliptateCore
import Foundation

@MainActor
struct AICutTranslationRequest: Equatable, Sendable {
  let url: URL
  let segments: [Segment]
  let sourceLanguage: Language
  let targetLanguage: Language
}

@MainActor
struct AICutTranslationExecutor {
  typealias Runner =
    @MainActor (_ request: AICutTranslationRequest, _ progress: @escaping (Int, Int) -> Void) async throws
    -> [String: SegmentTranslation]

  let runTranslation: Runner

  init(runTranslation: @escaping Runner) {
    self.runTranslation = runTranslation
  }

  func execute(
    request: AICutTranslationRequest,
    state: VideoState,
    updateStatus: @escaping (String) -> Void
  ) async throws {
    let translations = try await runTranslation(request) { completed, total in
      updateStatus(Self.progressMessage(completed: completed, total: total))
    }

    state.applyTranslations(translations, for: request.segments)
    state.translationSignature = SegmentSignature.compute(for: request.segments)
    state.lastTranslatedLanguage = request.targetLanguage
    updateStatus(
      Self.completionMessage(
        translatedCount: translations.count,
        totalCount: request.segments.count,
        targetLanguage: request.targetLanguage
      ))
  }

  static func progressMessage(completed: Int, total: Int) -> String {
    String(
      localized: "Translating \(completed)/\(total) segments...",
      comment: "AI Cut status message"
    )
  }

  static func completionMessage(
    translatedCount: Int,
    totalCount: Int,
    targetLanguage: Language
  ) -> String {
    String(
      localized: "Translation complete: \(translatedCount)/\(totalCount) segments translated to \(targetLanguage.displayName).",
      comment: "AI Cut status message"
    )
  }
}
