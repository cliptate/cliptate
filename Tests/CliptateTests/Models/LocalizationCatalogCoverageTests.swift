import Foundation
import Testing

@Suite("Localization catalog coverage")
struct LocalizationCatalogCoverageTests {
  private static let requiredLocales = ["zh-Hans", "ja", "ko", "de"]
  private static let separatorOnlyKeys: Set<String> = ["·", "→", "×"]
  private static let nativeLanguageNameKeys: Set<String> = ["中文", "日本語", "한국어"]
  private static let pureFormatPlaceholder = try! NSRegularExpression(
    pattern: #"%(?:\d+\$)?(?:@|lld|d|s|f)"#
  )

  @Test("user-visible entries provide zh-Hans ja and ko translations")
  func userVisibleEntriesProvideRequiredTranslations() throws {
    let strings = try Self.catalogStrings()

    let missingTranslations = strings.keys.sorted().compactMap { key -> String? in
      guard !Self.isIntentionallyUntranslated(key) else {
        return nil
      }

      let entry = strings[key] as? [String: Any] ?? [:]
      let localizations = entry["localizations"] as? [String: Any] ?? [:]
      let missingLocales = Self.requiredLocales.filter { locale in
        guard
          let localizedEntry = localizations[locale] as? [String: Any],
          let stringUnit = localizedEntry["stringUnit"] as? [String: Any],
          let state = stringUnit["state"] as? String,
          let value = stringUnit["value"] as? String
        else {
          return true
        }

        return state != "translated" || value.isEmpty
      }

      guard !missingLocales.isEmpty else {
        return nil
      }

      return "\"\(key)\" -> \(missingLocales.joined(separator: ", "))"
    }

    #expect(
      missingTranslations.isEmpty,
      "Missing required translations:\n\(missingTranslations.joined(separator: "\n"))"
    )
  }

  @Test("native navigation and dictation controls have localization entries")
  func nativeUIControlKeys() throws {
    let strings = try Self.catalogStrings()
    let requiredKeys = [
      "Back to History",
      "1 entry",
      "%lld entries",
      "Changes are saved automatically.",
      "Remove %@",
      "AI Enhance",
      "Clipboard Context",
      "Window Context",
      "Language list matches the active Voice Dictation ASR model.",
      "Language changed automatically from %@ to %@.",
      "%lld supported languages",
      "All languages",
    ]

    let missingKeys = requiredKeys.filter { strings[$0] == nil }
    #expect(missingKeys.isEmpty, "Missing UI localization keys: \(missingKeys)")
  }

  @Test("voice feature names are consistent across supported languages")
  func voiceFeatureNames() throws {
    let strings = try Self.catalogStrings()
    let names = [
      "File Transcription": ["zh-Hans": "文件转录", "ja": "ファイル文字起こし", "ko": "파일 전사", "de": "Dateitranskription"],
      "Voice Dictation": ["zh-Hans": "语音听写", "ja": "音声入力", "ko": "음성 받아쓰기", "de": "Sprachdiktat"],
      "Voice Generation": ["zh-Hans": "语音生成", "ja": "音声生成", "ko": "음성 생성", "de": "Sprachgenerierung"],
    ]
    for (key, translations) in names {
      let entry = strings[key] as? [String: Any]
      let localizations = entry?["localizations"] as? [String: Any]
      for (locale, expected) in translations {
        let localized = localizations?[locale] as? [String: Any]
        let unit = localized?["stringUnit"] as? [String: Any]
        #expect(unit?["value"] as? String == expected, "Unexpected \(locale) name for \(key)")
      }
    }
  }

  @Test("accessibility permission strings have localized catalog entries")
  func accessibilityPermissionStringsHaveLocalizedCatalogEntries() throws {
    let strings = try Self.catalogStrings()
    let requiredKeys = [
      "Getting Started",
      "Permissions and setup guidance",
      "Enable the permissions below to unlock dictation and assistant features.",
      "Keyboard Shortcuts",
      "Set up quick toggles for dictation and assistant modes.",
      "Manage in Voice Dictation",
      "Set up shortcut",
      "Microphone Access",
      "Screen Recording",
      "Allow on-screen text capture to improve assistant context.",
      "Open System Settings",
      "Continue",
      "Enable hands-free text insertion",
      "This allows Cliptate to insert the text you dictate directly into any app.",
      "Without this permission, Cliptate cannot enter the text you speak.",
      "Open Accessibility Settings",
    ]

    let missingKeys = requiredKeys.filter { strings[$0] == nil }
    #expect(
      missingKeys.isEmpty,
      "Missing accessibility localization keys:\n\(missingKeys.joined(separator: "\n"))"
    )
  }

  private static func catalogStrings() throws -> [String: Any] {
    let catalogURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Cliptate")
      .appendingPathComponent("Localizable.xcstrings")

    let data = try Data(contentsOf: catalogURL)
    let rootObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(rootObject["strings"] as? [String: Any])
  }

  private static func isIntentionallyUntranslated(_ key: String) -> Bool {
    if key.isEmpty || separatorOnlyKeys.contains(key) || nativeLanguageNameKeys.contains(key) {
      return true
    }

    let range = NSRange(key.startIndex..<key.endIndex, in: key)
    let stripped = pureFormatPlaceholder.stringByReplacingMatches(
      in: key,
      options: [],
      range: range,
      withTemplate: ""
    )

    guard !stripped.isEmpty else {
      return true
    }

    let allowedScalars = CharacterSet(charactersIn: " \t\n/•:().-+")
    return stripped.unicodeScalars.allSatisfy(allowedScalars.contains)
  }
}
