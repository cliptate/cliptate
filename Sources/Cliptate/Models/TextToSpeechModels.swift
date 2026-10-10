import Foundation

/// Supported on-device text-to-speech engines.
public enum TTSEngine: String, CaseIterable, Identifiable, Sendable {
    case qwen3TTS

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .qwen3TTS: return "Qwen3 TTS"
        }
    }

    public var subtitle: String {
        switch self {
        case .qwen3TTS:
            return String(localized: "TTSEngine.qwen3TTS.subtitle", defaultValue: "MLX Qwen3 TTS with voice design & cloning", comment: "Subtitle for Qwen3 TTS engine")
        }
    }
}

extension TTSEngine: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Legacy "kokoro" value maps to qwen3TTS
        if raw == "kokoro" {
            self = .qwen3TTS
        } else {
            self = TTSEngine(rawValue: raw) ?? .qwen3TTS
        }
    }
}

/// Preferred runtime variant for synthesis.
public enum TTSVariantPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Automatically pick the best variant based on text length.
    case automatic
    /// Force the short (≈5 second) variant for ultra-low latency.
    case short
    /// Force the long (≈15 second) variant for higher fidelity.
    case extended

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return String(localized: "TTSVariantPreference.automatic.displayName", defaultValue: "Auto",          comment: "TTS variant: automatic selection")
        case .short:     return String(localized: "TTSVariantPreference.short.displayName",     defaultValue: "Short (≈5s)",   comment: "TTS variant: short, low-latency")
        case .extended:  return String(localized: "TTSVariantPreference.extended.displayName",  defaultValue: "Extended (≈15s)", comment: "TTS variant: extended, higher fidelity")
        }
    }

    /// Maximum practical duration before a chunk hand-off is required.
    public var maxRecommendedDuration: TimeInterval {
        switch self {
        case .automatic: return 12.0
        case .short: return 5.0
        case .extended: return 15.0
        }
    }
}

/// Metadata describing a TTS voice profile.
public struct TTSVoiceProfile: Identifiable, Codable, Hashable, Sendable {
    public enum Locale: String, Codable, Sendable {
        case englishUS = "en-US"
        case englishUK = "en-GB"
        case spanishLatAm = "es-419"
        case french = "fr-FR"
        case hindi = "hi-IN"
        case italian = "it-IT"
        case japanese = "ja-JP"
        case portugueseBR = "pt-BR"
        case mandarin = "zh-CN"

        public var localizedDisplayName: String {
            Foundation.Locale.current.localizedString(forIdentifier: rawValue)
                ?? rawValue
        }
    }

    public let id: String
    public let displayName: String
    public let locale: Locale
    public let descriptor: String
    public let isRecommended: Bool
    public let tags: [String]

    public init(
        id: String,
        displayName: String,
        locale: Locale,
        descriptor: String,
        isRecommended: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.locale = locale
        self.descriptor = descriptor
        self.isRecommended = isRecommended
        self.tags = tags
    }
}
/// A built-in preset speaker that can be passed to Base / CustomVoice TTS models
/// without requiring a reference audio file for cloning.
public struct TTSPresetSpeaker: Identifiable, Sendable, Hashable {
    public enum SpeakerLanguage: String, Sendable {
        case chinese, english, japanese, korean

        /// Language name localized for the current app locale using the system Locale API.
        public var localizedDisplayName: String {
            switch self {
            case .chinese: return Locale.current.localizedString(forLanguageCode: "zh-Hans") ?? "Chinese"
            case .english: return Locale.current.localizedString(forLanguageCode: "en") ?? "English"
            case .japanese: return Locale.current.localizedString(forLanguageCode: "ja") ?? "Japanese"
            case .korean: return Locale.current.localizedString(forLanguageCode: "ko") ?? "Korean"
            }
        }
    }

    public let name: String
    public let language: SpeakerLanguage
    /// Short description of voice character.
    public let description: String
    /// Primary native language label shown in the UI, localized for the current locale.
    public var nativeLanguage: String { language.localizedDisplayName }

    public var id: String { name }

    public static let all: [TTSPresetSpeaker] = [
        // Chinese
        TTSPresetSpeaker(name: "Vivian",   language: .chinese,  description: String(localized: "Vivian.description",   defaultValue: "Bright, slightly sharp young female voice", comment: "Vivian speaker voice description")),
        TTSPresetSpeaker(name: "Serena",   language: .chinese,  description: String(localized: "Serena.description",   defaultValue: "Warm, soft young female voice",              comment: "Serena speaker voice description")),
        TTSPresetSpeaker(name: "Uncle_Fu", language: .chinese,  description: String(localized: "Uncle_Fu.description", defaultValue: "Steady male voice with a deep, mellow tone", comment: "Uncle_Fu speaker voice description")),
        TTSPresetSpeaker(name: "Dylan",    language: .chinese,  description: String(localized: "Dylan.description",    defaultValue: "Beijing young male voice, clear and natural", comment: "Dylan speaker voice description")),
        TTSPresetSpeaker(name: "Eric",     language: .chinese,  description: String(localized: "Eric.description",     defaultValue: "Lively Chengdu male voice, slightly husky",  comment: "Eric speaker voice description")),
        // English
        TTSPresetSpeaker(name: "Ryan",     language: .english,  description: String(localized: "Ryan.description",     defaultValue: "Dynamic male voice with strong rhythm",      comment: "Ryan speaker voice description")),
        TTSPresetSpeaker(name: "Aiden",    language: .english,  description: String(localized: "Aiden.description",    defaultValue: "Sunny American male voice with clear mid-range", comment: "Aiden speaker voice description")),
        // Japanese
        TTSPresetSpeaker(name: "Ono_Anna", language: .japanese, description: String(localized: "Ono_Anna.description", defaultValue: "Cute Japanese female voice, light and lively", comment: "Ono_Anna speaker voice description")),
        // Korean
        TTSPresetSpeaker(name: "Sohee",    language: .korean,   description: String(localized: "Sohee.description",    defaultValue: "Warm Korean female voice with rich expressiveness", comment: "Sohee speaker voice description")),
    ]

    public static func speakers(for language: SpeakerLanguage) -> [TTSPresetSpeaker] {
        all.filter { $0.language == language }
    }
}

/// TTS model family categories for filtering.
public enum TTSModelFamily: String, CaseIterable, Identifiable, Sendable {
    case base
    case customVoice
    case voiceDesign

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .base: return "Base"
        case .customVoice: return "CustomVoice"
        case .voiceDesign: return "VoiceDesign"
        }
    }

    public var subtitle: String {
        switch self {
        case .base:        return String(localized: "TTSModelFamily.base.subtitle",        defaultValue: "Preset speakers + voice cloning via reference audio", comment: "Base TTS model family subtitle")
        case .customVoice: return String(localized: "TTSModelFamily.customVoice.subtitle", defaultValue: "Named speakers with emotion and style control",           comment: "CustomVoice TTS model family subtitle")
        case .voiceDesign: return String(localized: "TTSModelFamily.voiceDesign.subtitle", defaultValue: "Create any voice via text description",                  comment: "VoiceDesign TTS model family subtitle")
        }
    }
}

/// Metadata for an MLX-based TTS model variant.
public struct MLXTTSModelDefinition: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let displayName: String
    public let huggingFaceRepo: String
    public let parameterSize: String
    public let estimatedSizeMB: Int
    public let supportsVoiceDesign: Bool
    public let supportsVoiceClone: Bool
    public let description: String
    public let family: TTSModelFamily
    public let quantization: String
    /// Corresponding ModelVariant for download and cache operations.
    public let modelVariant: ModelVariant

    /// CustomVoice models support named speakers with optional emotion/style prompting.
    /// The `voice:` field accepts `"SpeakerName, emotion description"` or just `"SpeakerName"`.
    public var supportsEmotionControl: Bool { family == .customVoice }

    /// Compose the `voice:` string for CustomVoice synthesis.
    /// Returns `nil` when both inputs are empty (model uses its default voice).
    public static func customVoiceString(speaker: String, emotionPrompt: String) -> String? {
        let s = speaker.trimmingCharacters(in: .whitespaces)
        let e = emotionPrompt.trimmingCharacters(in: .whitespaces)
        switch (s.isEmpty, e.isEmpty) {
        case (true, true): return nil
        case (false, true): return s
        case (true, false): return e
        case (false, false): return "\(s), \(e)"
        }
    }

    public static let availableModels: [MLXTTSModelDefinition] = [
        // Base 0.6B variants (voice cloning)
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-base-4bit",
            displayName: "Qwen3 TTS 0.6B Base (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 400,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Lightweight base model for fast voice cloning.",
            family: .base,
            quantization: "4-bit",
            modelVariant: .qwen3TTS06B4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-base-8bit",
            displayName: "Qwen3 TTS 0.6B Base (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 500,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Balanced quality and speed for everyday synthesis.",
            family: .base,
            quantization: "8-bit",
            modelVariant: .qwen3TTS06B8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-base-bf16",
            displayName: "Qwen3 TTS 0.6B Base (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16",
            parameterSize: "0.6B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Full-precision base model with higher fidelity.",
            family: .base,
            quantization: "bf16",
            modelVariant: .qwen3TTS06Bbf16
        ),

        // Base 1.7B variants (voice cloning)
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-base-4bit",
            displayName: "Qwen3 TTS 1.7B Base (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 700,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Larger base model with stronger voice quality.",
            family: .base,
            quantization: "4-bit",
            modelVariant: .qwen3TTS17B4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-base-8bit",
            displayName: "Qwen3 TTS 1.7B Base (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "High-quality 1.7B base model for richer synthesis.",
            family: .base,
            quantization: "8-bit",
            modelVariant: .qwen3TTS17B8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-base-bf16",
            displayName: "Qwen3 TTS 1.7B Base (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
            parameterSize: "1.7B",
            estimatedSizeMB: 2000,
            supportsVoiceDesign: false,
            supportsVoiceClone: true,
            description: "Highest-fidelity 1.7B base model.",
            family: .base,
            quantization: "bf16",
            modelVariant: .qwen3TTS17Bbf16
        ),

        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-customvoice-4bit",
            displayName: "Qwen3 TTS 0.6B CustomVoice (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 400,
            supportsVoiceDesign: false,
            supportsVoiceClone: false,
            description: "Lightweight CustomVoice model — preset speakers with emotion and style control.",
            family: .customVoice,
            quantization: "4-bit",
            modelVariant: .qwen3TTS06BCustomVoice4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-customvoice-8bit",
            displayName: "Qwen3 TTS 0.6B CustomVoice (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 500,
            supportsVoiceDesign: false,
            supportsVoiceClone: false,
            description: "Balanced CustomVoice model — preset speakers with emotion and style control.",
            family: .customVoice,
            quantization: "8-bit",
            modelVariant: .qwen3TTS06BCustomVoice8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-customvoice-bf16",
            displayName: "Qwen3 TTS 0.6B CustomVoice (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16",
            parameterSize: "0.6B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: false,
            supportsVoiceClone: false,
            description: "Full-precision CustomVoice model — preset speakers with emotion and style control.",
            family: .customVoice,
            quantization: "bf16",
            modelVariant: .qwen3TTS06BCustomVoiceBf16
        ),

        // CustomVoice 1.7B variants
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-customvoice-4bit",
            displayName: "Qwen3 TTS 1.7B CustomVoice (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 700,
            supportsVoiceDesign: false,
            supportsVoiceClone: false,
            description: "Larger CustomVoice model — preset speakers with stronger emotion and style control.",
            family: .customVoice,
            quantization: "4-bit",
            modelVariant: .qwen3TTS17BCustomVoice4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-customvoice-8bit",
            displayName: "Qwen3 TTS 1.7B CustomVoice (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: false,
            supportsVoiceClone: false,
            description: "High-quality 1.7B CustomVoice model — preset speakers with emotion and style control.",
            family: .customVoice,
            quantization: "8-bit",
            modelVariant: .qwen3TTS17BCustomVoice8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-customvoice-bf16",
            displayName: "Qwen3 TTS 1.7B CustomVoice (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16",
            parameterSize: "1.7B",
            estimatedSizeMB: 2000,
            supportsVoiceDesign: false,
            supportsVoiceClone: false,
            description: "Highest-fidelity 1.7B CustomVoice model — preset speakers with emotion and style control.",
            family: .customVoice,
            quantization: "bf16",
            modelVariant: .qwen3TTS17BCustomVoiceBf16
        ),

        // VoiceDesign 0.6B variants (voice creation via text description)
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-voicedesign-4bit",
            displayName: "Qwen3 TTS 0.6B VoiceDesign (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-VoiceDesign-4bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 400,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Lightweight VoiceDesign model — create voices from text descriptions.",
            family: .voiceDesign,
            quantization: "4-bit",
            modelVariant: .qwen3TTS06BVoiceDesign4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-voicedesign-8bit",
            displayName: "Qwen3 TTS 0.6B VoiceDesign (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-VoiceDesign-8bit",
            parameterSize: "0.6B",
            estimatedSizeMB: 500,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Balanced VoiceDesign model for voice creation.",
            family: .voiceDesign,
            quantization: "8-bit",
            modelVariant: .qwen3TTS06BVoiceDesign8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-0.6b-voicedesign-bf16",
            displayName: "Qwen3 TTS 0.6B VoiceDesign (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-0.6B-VoiceDesign-bf16",
            parameterSize: "0.6B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Full-precision VoiceDesign model for high-fidelity voice creation.",
            family: .voiceDesign,
            quantization: "bf16",
            modelVariant: .qwen3TTS06BVoiceDesignBf16
        ),

        // VoiceDesign 1.7B variants
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-voicedesign-4bit",
            displayName: "Qwen3 TTS 1.7B VoiceDesign (4-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 700,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Larger VoiceDesign model with richer voice creation capability.",
            family: .voiceDesign,
            quantization: "4-bit",
            modelVariant: .qwen3TTS17BVoiceDesign4bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-voicedesign-8bit",
            displayName: "Qwen3 TTS 1.7B VoiceDesign (8-bit)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit",
            parameterSize: "1.7B",
            estimatedSizeMB: 900,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "High-quality 1.7B VoiceDesign model.",
            family: .voiceDesign,
            quantization: "8-bit",
            modelVariant: .qwen3TTS17BVoiceDesign8bit
        ),
        MLXTTSModelDefinition(
            id: "qwen3-tts-1.7b-voicedesign-bf16",
            displayName: "Qwen3 TTS 1.7B VoiceDesign (bf16)",
            huggingFaceRepo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
            parameterSize: "1.7B",
            estimatedSizeMB: 2000,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Highest-fidelity 1.7B VoiceDesign model for the most expressive voice creation.",
            family: .voiceDesign,
            quantization: "bf16",
            modelVariant: .qwen3TTS17BVoiceDesignBf16
        ),
    ]

    /// Filter models by family.
    public static func models(for family: TTSModelFamily) -> [MLXTTSModelDefinition] {
        availableModels.filter { $0.family == family }
    }
    
    /// Metric chip data for UI display.
    public struct MetricChip: Sendable {
        public let title: String
        public let value: String
        public let icon: String
    }
    
    /// Visual theming for family icons.
    public struct FamilyVisual: Sendable {
        public let icon: String
        public let colorName: String
    }
    
    public var metricChips: [MetricChip] {
        [
            MetricChip(title: "SIZE", value: parameterSize, icon: "cube.fill"),
            MetricChip(title: "DOWNLOAD", value: "\(estimatedSizeMB) MB", icon: "arrow.down.circle.fill"),
            MetricChip(title: "QUANTIZATION", value: quantization, icon: "speedometer"),
            MetricChip(title: "FAMILY", value: family.displayName, icon: "waveform.badge.mic")
        ]
    }
    
    public var familyVisual: FamilyVisual {
        switch family {
        case .base:
            return FamilyVisual(icon: "person.wave.2.fill", colorName: "orange")
        case .voiceDesign:
            return FamilyVisual(icon: "paintbrush.pointed.fill", colorName: "purple")
        case .customVoice:
            return FamilyVisual(icon: "sparkles", colorName: "blue")
        }
    }
}

enum TTSScriptMetrics {
    static func estimatedSpeechDuration(for text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var latinWordCount = 0
        var cjkCharacterCount = 0
        var sentencePauseCount = 0
        var phrasePauseCount = 0
        var hasOpenLatinWord = false

        func closeLatinWord() {
            if hasOpenLatinWord {
                latinWordCount += 1
                hasOpenLatinWord = false
            }
        }

        for scalar in trimmed.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                closeLatinWord()
                continue
            }

            if Self.isSentencePause(scalar) {
                closeLatinWord()
                sentencePauseCount += 1
                continue
            }

            if Self.isPhrasePause(scalar) {
                closeLatinWord()
                phrasePauseCount += 1
                continue
            }

            if Self.isCJKLike(scalar) {
                closeLatinWord()
                cjkCharacterCount += 1
                continue
            }

            if Self.isLatinWordCharacter(scalar) {
                hasOpenLatinWord = true
                continue
            }

            closeLatinWord()
        }

        closeLatinWord()

        let latinDuration = Double(latinWordCount) * 0.38
        let cjkDuration = Double(cjkCharacterCount) * 0.24
        let sentencePause = Double(sentencePauseCount) * 0.18
        let phrasePause = Double(phrasePauseCount) * 0.08

        return max(0.3, latinDuration + cjkDuration + sentencePause + phrasePause)
    }

    private static func isLatinWordCharacter(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) && !isCJKLike(scalar)
    }

    private static func isSentencePause(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet(charactersIn: ".!?。！？").contains(scalar)
    }

    private static func isPhrasePause(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet(charactersIn: ",;:、，；：").contains(scalar)
    }

    private static func isCJKLike(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F,  // Hiragana
             0x30A0...0x30FF,  // Katakana
             0x3400...0x4DBF,  // CJK Extension A
             0x4E00...0x9FFF,  // CJK Unified Ideographs
             0xF900...0xFAFF,  // CJK Compatibility Ideographs
             0xAC00...0xD7AF:  // Hangul syllables
            return true
        default:
            return scalar.properties.isIdeographic
        }
    }
}
