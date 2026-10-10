import Foundation

public enum Language: String, CaseIterable, Identifiable, Codable, Sendable {
  case auto = "auto"
  case english = "en"
  case chinese = "zh"
  case german = "de"
  case spanish = "es"
  case russian = "ru"
  case korean = "ko"
  case french = "fr"
  case japanese = "ja"
  case portuguese = "pt"
  case turkish = "tr"
  case polish = "pl"
  case catalan = "ca"
  case dutch = "nl"
  case arabic = "ar"
  case swedish = "sv"
  case italian = "it"
  case indonesian = "id"
  case hindi = "hi"
  case finnish = "fi"
  case vietnamese = "vi"
  case hebrew = "he"
  case ukrainian = "uk"
  case greek = "el"
  case malay = "ms"
  case czech = "cs"
  case romanian = "ro"
  case danish = "da"
  case hungarian = "hu"
  case tamil = "ta"
  case norwegian = "no"
  case thai = "th"
  case urdu = "ur"
  case croatian = "hr"
  case bulgarian = "bg"
  case lithuanian = "lt"
  case latin = "la"
  case maori = "mi"
  case maltese = "mt"
  case welsh = "cy"
  case slovak = "sk"
  case slovenian = "sl"
  case swahili = "sw"
  case galician = "gl"
  case amharic = "am"
  case assamese = "as"
  case azerbaijani = "az"
  case bashkir = "ba"
  case belarusian = "be"
  case bengali = "bn"
  case bosnian = "bs"
  case breton = "br"
  case burmese = "my"

  case esperanto = "eo"
  case estonian = "et"
  case faroese = "fo"

  case georgian = "ka"
  case gujarati = "gu"
  case haitian = "ht"
  case hausa = "ha"
  case hawaiian = "haw"
  case icelandic = "is"
  case javanese = "jw"
  case kannada = "kn"
  case kazakh = "kk"
  case khmer = "km"
  case lao = "lo"
  case latvian = "lv"
  case lingala = "ln"
  case luxembourgish = "lb"
  case macedonian = "mk"
  case malagasy = "mg"
  case malayalam = "ml"
  case marathi = "mr"

  case mongolian = "mn"
  case nepali = "ne"
  case nynorsk = "nn"
  case occitan = "oc"
  case pashto = "ps"
  case persian = "fa"
  case punjabi = "pa"

  case serbian = "sr"
  case shona = "sn"
  case sindhi = "sd"
  case sinhala = "si"
  case somali = "so"
  case sundanese = "su"
  case tagalog = "tl"
  case tajik = "tg"
  case tatar = "tt"
  case telugu = "te"
  case tibetan = "bo"
  case turkmen = "tk"
  case uyghur = "ug"
  case uzbek = "uz"

  case yiddish = "yi"
  case yoruba = "yo"

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .auto: return String(localized: "Auto Detect", comment: "Language name")
    case .english: return String(localized: "English", comment: "Language name")
    case .chinese: return String(localized: "Chinese", comment: "Language name")
    case .german: return String(localized: "German", comment: "Language name")
    case .spanish: return String(localized: "Spanish", comment: "Language name")
    case .russian: return String(localized: "Russian", comment: "Language name")
    case .korean: return String(localized: "Korean", comment: "Language name")
    case .french: return String(localized: "French", comment: "Language name")
    case .japanese: return String(localized: "Japanese", comment: "Language name")
    case .portuguese: return String(localized: "Portuguese", comment: "Language name")
    case .turkish: return String(localized: "Turkish", comment: "Language name")
    case .polish: return String(localized: "Polish", comment: "Language name")
    case .catalan: return String(localized: "Catalan", comment: "Language name")
    case .dutch: return String(localized: "Dutch", comment: "Language name")
    case .arabic: return String(localized: "Arabic", comment: "Language name")
    case .swedish: return String(localized: "Swedish", comment: "Language name")
    case .italian: return String(localized: "Italian", comment: "Language name")
    case .indonesian: return String(localized: "Indonesian", comment: "Language name")
    case .hindi: return String(localized: "Hindi", comment: "Language name")
    case .finnish: return String(localized: "Finnish", comment: "Language name")
    case .vietnamese: return String(localized: "Vietnamese", comment: "Language name")
    case .hebrew: return String(localized: "Hebrew", comment: "Language name")
    case .ukrainian: return String(localized: "Ukrainian", comment: "Language name")
    case .greek: return String(localized: "Greek", comment: "Language name")
    case .malay: return String(localized: "Malay", comment: "Language name")
    case .czech: return String(localized: "Czech", comment: "Language name")
    case .romanian: return String(localized: "Romanian", comment: "Language name")
    case .danish: return String(localized: "Danish", comment: "Language name")
    case .hungarian: return String(localized: "Hungarian", comment: "Language name")
    case .tamil: return String(localized: "Tamil", comment: "Language name")
    case .norwegian: return String(localized: "Norwegian", comment: "Language name")
    case .thai: return String(localized: "Thai", comment: "Language name")
    case .urdu: return String(localized: "Urdu", comment: "Language name")
    case .croatian: return String(localized: "Croatian", comment: "Language name")
    case .bulgarian: return String(localized: "Bulgarian", comment: "Language name")
    case .lithuanian: return String(localized: "Lithuanian", comment: "Language name")
    case .latin: return String(localized: "Latin", comment: "Language name")
    case .maori: return String(localized: "Maori", comment: "Language name")
    case .maltese: return String(localized: "Maltese", comment: "Language name")
    case .welsh: return String(localized: "Welsh", comment: "Language name")
    case .slovak: return String(localized: "Slovak", comment: "Language name")
    case .slovenian: return String(localized: "Slovenian", comment: "Language name")
    case .swahili: return String(localized: "Swahili", comment: "Language name")
    case .galician: return String(localized: "Galician", comment: "Language name")
    case .amharic: return String(localized: "Amharic", comment: "Language name")
    case .assamese: return String(localized: "Assamese", comment: "Language name")
    case .azerbaijani: return String(localized: "Azerbaijani", comment: "Language name")
    case .bashkir: return String(localized: "Bashkir", comment: "Language name")
    case .belarusian: return String(localized: "Belarusian", comment: "Language name")
    case .bengali: return String(localized: "Bengali", comment: "Language name")
    case .bosnian: return String(localized: "Bosnian", comment: "Language name")
    case .breton: return String(localized: "Breton", comment: "Language name")
    case .burmese: return String(localized: "Burmese", comment: "Language name")
    case .esperanto: return String(localized: "Esperanto", comment: "Language name")
    case .estonian: return String(localized: "Estonian", comment: "Language name")
    case .faroese: return String(localized: "Faroese", comment: "Language name")
    case .georgian: return String(localized: "Georgian", comment: "Language name")
    case .gujarati: return String(localized: "Gujarati", comment: "Language name")
    case .haitian: return String(localized: "Haitian", comment: "Language name")
    case .hausa: return String(localized: "Hausa", comment: "Language name")
    case .hawaiian: return String(localized: "Hawaiian", comment: "Language name")
    case .icelandic: return String(localized: "Icelandic", comment: "Language name")
    case .javanese: return String(localized: "Javanese", comment: "Language name")
    case .kannada: return String(localized: "Kannada", comment: "Language name")
    case .kazakh: return String(localized: "Kazakh", comment: "Language name")
    case .khmer: return String(localized: "Khmer", comment: "Language name")
    case .lao: return String(localized: "Lao", comment: "Language name")
    case .latvian: return String(localized: "Latvian", comment: "Language name")
    case .lingala: return String(localized: "Lingala", comment: "Language name")
    case .luxembourgish: return String(localized: "Luxembourgish", comment: "Language name")
    case .macedonian: return String(localized: "Macedonian", comment: "Language name")
    case .malagasy: return String(localized: "Malagasy", comment: "Language name")
    case .malayalam: return String(localized: "Malayalam", comment: "Language name")
    case .marathi: return String(localized: "Marathi", comment: "Language name")
    case .mongolian: return String(localized: "Mongolian", comment: "Language name")
    case .nepali: return String(localized: "Nepali", comment: "Language name")
    case .nynorsk: return String(localized: "Nynorsk", comment: "Language name")
    case .occitan: return String(localized: "Occitan", comment: "Language name")
    case .pashto: return String(localized: "Pashto", comment: "Language name")
    case .persian: return String(localized: "Persian", comment: "Language name")
    case .punjabi: return String(localized: "Punjabi", comment: "Language name")
    case .serbian: return String(localized: "Serbian", comment: "Language name")
    case .shona: return String(localized: "Shona", comment: "Language name")
    case .sindhi: return String(localized: "Sindhi", comment: "Language name")
    case .sinhala: return String(localized: "Sinhala", comment: "Language name")
    case .somali: return String(localized: "Somali", comment: "Language name")
    case .sundanese: return String(localized: "su", comment: "Language name")
    case .tagalog: return String(localized: "Tagalog", comment: "Language name")
    case .tajik: return String(localized: "Tajik", comment: "Language name")
    case .tatar: return String(localized: "tt", comment: "Language name")
    case .telugu: return String(localized: "te", comment: "Language name")
    case .tibetan: return String(localized: "bo", comment: "Language name")
    case .turkmen: return String(localized: "tk", comment: "Language name")
    case .uyghur: return String(localized: "ug", comment: "Language name")
    case .uzbek: return String(localized: "uz", comment: "Language name")
    case .yiddish: return String(localized: "yi", comment: "Language name")
    case .yoruba: return String(localized: "yo", comment: "Language name")
    }
  }

  public var isAuto: Bool {
    if case .auto = self { return true }
    return false
  }

  public var whisperKitLanguageCode: String? {
    isAuto ? nil : rawValue
  }

  // 支持翻译的常用语言（限制翻译选项）
  static let translationSupported: [Language] = [
    .english, .chinese, .spanish, .french, .german, .italian, .portuguese,
    .russian, .japanese, .korean, .arabic, .hindi, .dutch, .swedish,
    .norwegian, .danish, .finnish, .polish, .czech, .hungarian, .romanian,
    .bulgarian, .ukrainian, .greek, .turkish, .thai, .vietnamese, .indonesian,
    .malay, .tagalog, .hebrew,
  ]
}
