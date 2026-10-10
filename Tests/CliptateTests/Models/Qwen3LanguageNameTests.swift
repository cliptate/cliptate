import Foundation
import Testing

@testable import Cliptate

@Suite("Qwen3 language name mapping")
struct Qwen3LanguageNameTests {

  @Test("qwen3LanguageName returns English name for every Language case")
  func allCasesReturnEnglishNames() {
    // Map of expected English-only names for Qwen3
    let expected: [Language: String] = [
      .auto: "auto",
      .english: "English",
      .chinese: "Chinese",
      .german: "German",
      .spanish: "Spanish",
      .russian: "Russian",
      .korean: "Korean",
      .french: "French",
      .japanese: "Japanese",
      .portuguese: "Portuguese",
      .turkish: "Turkish",
      .polish: "Polish",
      .catalan: "Catalan",
      .dutch: "Dutch",
      .arabic: "Arabic",
      .swedish: "Swedish",
      .italian: "Italian",
      .indonesian: "Indonesian",
      .hindi: "Hindi",
      .finnish: "Finnish",
      .vietnamese: "Vietnamese",
      .hebrew: "Hebrew",
      .ukrainian: "Ukrainian",
      .greek: "Greek",
      .malay: "Malay",
      .czech: "Czech",
      .romanian: "Romanian",
      .danish: "Danish",
      .hungarian: "Hungarian",
      .tamil: "Tamil",
      .norwegian: "Norwegian",
      .thai: "Thai",
      .urdu: "Urdu",
      .croatian: "Croatian",
      .bulgarian: "Bulgarian",
      .lithuanian: "Lithuanian",
      .latin: "Latin",
      .maori: "Maori",
      .maltese: "Maltese",
      .welsh: "Welsh",
      .slovak: "Slovak",
      .slovenian: "Slovenian",
      .swahili: "Swahili",
      .galician: "Galician",
      .amharic: "Amharic",
      .assamese: "Assamese",
      .azerbaijani: "Azerbaijani",
      .bashkir: "Bashkir",
      .belarusian: "Belarusian",
      .bengali: "Bengali",
      .bosnian: "Bosnian",
      .breton: "Breton",
      .burmese: "Burmese",
      .esperanto: "Esperanto",
      .estonian: "Estonian",
      .faroese: "Faroese",
      .georgian: "Georgian",
      .gujarati: "Gujarati",
      .haitian: "Haitian",
      .hausa: "Hausa",
      .hawaiian: "Hawaiian",
      .icelandic: "Icelandic",
      .javanese: "Javanese",
      .kannada: "Kannada",
      .kazakh: "Kazakh",
      .khmer: "Khmer",
      .lao: "Lao",
      .latvian: "Latvian",
      .lingala: "Lingala",
      .luxembourgish: "Luxembourgish",
      .macedonian: "Macedonian",
      .malagasy: "Malagasy",
      .malayalam: "Malayalam",
      .marathi: "Marathi",
      .mongolian: "Mongolian",
      .nepali: "Nepali",
      .nynorsk: "Nynorsk",
      .occitan: "Occitan",
      .pashto: "Pashto",
      .persian: "Persian",
      .punjabi: "Punjabi",
      .serbian: "Serbian",
      .shona: "Shona",
      .sindhi: "Sindhi",
      .sinhala: "Sinhala",
      .somali: "Somali",
      .sundanese: "Sundanese",
      .tagalog: "Tagalog",
      .tajik: "Tajik",
      .tatar: "Tatar",
      .telugu: "Telugu",
      .tibetan: "Tibetan",
      .turkmen: "Turkmen",
      .uyghur: "Uyghur",
      .uzbek: "Uzbek",
      .yiddish: "Yiddish",
      .yoruba: "Yoruba",
    ]

    // Verify every Language case is covered
    for lang in Language.allCases {
      let name = lang.qwen3LanguageName
      if let expectedName = expected[lang] {
        #expect(name == expectedName, "Language.\(lang) should return \"\(expectedName)\" but got \"\(name)\"")
      } else {
        Issue.record("Language.\(lang) is not in the expected map — add it")
      }
      // Ensure no localized strings leaked through (they would contain non-ASCII for CJK locales)
      // The name should be a simple English word (or "auto")
      #expect(!name.isEmpty, "Language.\(lang) returned empty qwen3LanguageName")
    }
  }

  @Test("qwen3LanguageName does not use String(localized:)")
  func autoReturnsLiteralAuto() {
    // The simplest canary: auto must always be "auto", not the localized "Auto Detect"
    #expect(Language.auto.qwen3LanguageName == "auto")
    #expect(Language.auto.qwen3LanguageName != Language.auto.displayName)
  }
}
