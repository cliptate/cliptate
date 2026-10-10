import Foundation

/// Represents word-level timing information
public struct WordTiming: Sendable, Codable, Equatable {
  public let word: String
  public let startTime: TimeInterval
  public let endTime: TimeInterval
  public let confidence: Float?
  public let punctuation: String

  public init(
    word: String,
    startTime: TimeInterval,
    endTime: TimeInterval,
    confidence: Float? = nil,
    punctuation: String = ""
  ) {
    self.word = word
    self.startTime = startTime
    self.endTime = endTime
    self.confidence = confidence
    self.punctuation = punctuation
  }

  private enum CodingKeys: String, CodingKey {
    case word
    case startTime
    case endTime
    case confidence
    case punctuation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    word = try container.decode(String.self, forKey: .word)
    startTime = try container.decode(TimeInterval.self, forKey: .startTime)
    endTime = try container.decode(TimeInterval.self, forKey: .endTime)
    confidence = try container.decodeIfPresent(Float.self, forKey: .confidence)
    punctuation = try container.decodeIfPresent(String.self, forKey: .punctuation) ?? ""
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(word, forKey: .word)
    try container.encode(startTime, forKey: .startTime)
    try container.encode(endTime, forKey: .endTime)
    try container.encodeIfPresent(confidence, forKey: .confidence)
    try container.encode(punctuation, forKey: .punctuation)
  }
}

/// Represents a transcribed speech segment
public struct Segment: Sendable, Identifiable, Codable {
  public let id: String
  public let startTime: TimeInterval
  public let endTime: TimeInterval
  public let text: String
  public let words: [WordTiming]?
  public let confidence: Float?
  /// Speaker index from diarization (nil if speaker identity unknown).
  public let speakerId: Int?
  /// Embedded translation (nil if not yet translated).
  public var translation: SegmentTranslation?

  public var duration: TimeInterval {
    return endTime - startTime
  }

  public init(
    id: String = UUID().uuidString,
    startTime: TimeInterval, endTime: TimeInterval, text: String,
    words: [WordTiming]? = nil, confidence: Float? = nil, speakerId: Int? = nil,
    translation: SegmentTranslation? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.text = text
    self.words = words
    self.confidence = confidence
    self.speakerId = speakerId
    self.translation = translation
  }

  // MARK: - Codable

  private enum CodingKeys: String, CodingKey {
    case id, startTime, endTime, text, words, confidence, speakerId, translation
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    startTime  = try c.decode(TimeInterval.self, forKey: .startTime)
    endTime    = try c.decode(TimeInterval.self, forKey: .endTime)
    text       = try c.decode(String.self,       forKey: .text)
    words      = try c.decodeIfPresent([WordTiming].self, forKey: .words)
    confidence = try c.decodeIfPresent(Float.self, forKey: .confidence)
    speakerId  = try c.decodeIfPresent(Int.self,   forKey: .speakerId)
    translation = try c.decodeIfPresent(SegmentTranslation.self, forKey: .translation)
  }
}

/// Build a deterministic child ID from the parent segment's ID and the child's timing.
/// Ensures the same pipeline run always produces the same segment IDs.
extension Segment {
  static func deterministicChildId(parentId: String, startTime: TimeInterval, endTime: TimeInterval) -> String {
    let startMs = Int((startTime * 1000).rounded())
    let endMs = Int((endTime * 1000).rounded())
    return "\(parentId):\(startMs)-\(endMs)"
  }
}

// MARK: - Equatable (content-based, excludes id)
extension Segment: Equatable {
  public static func == (lhs: Segment, rhs: Segment) -> Bool {
    lhs.startTime == rhs.startTime
      && lhs.endTime == rhs.endTime
      && lhs.text == rhs.text
      && lhs.words == rhs.words
      && lhs.confidence == rhs.confidence
      && lhs.speakerId == rhs.speakerId
      && lhs.translation == rhs.translation
  }
}

/// Stable identifier for a segment built from time boundaries (millisecond precision).
public struct SegmentIdentifier: Hashable, Codable, Sendable {
  public let startMillis: Int
  public let endMillis: Int

  public init(startMillis: Int, endMillis: Int) {
    self.startMillis = min(startMillis, endMillis)
    self.endMillis = max(startMillis, endMillis)
  }

  public init(startTime: TimeInterval, endTime: TimeInterval) {
    let start = Int((startTime * 1000).rounded())
    let end = Int((endTime * 1000).rounded())
    self.init(startMillis: start, endMillis: end)
  }

  public init(segment: Segment) {
    self.init(startTime: segment.startTime, endTime: segment.endTime)
  }
}

/// Progress information for model download
public struct ModelDownloadProgress: Sendable {
  public let currentStep: String
  public let progress: Float  // 0.0 to 1.0
  public let estimatedTimeRemaining: TimeInterval?
  public let attemptNumber: Int
  public let maxAttempts: Int

  public init(
    currentStep: String, progress: Float, estimatedTimeRemaining: TimeInterval? = nil,
    attemptNumber: Int = 1, maxAttempts: Int = 1
  ) {
    self.currentStep = currentStep
    self.progress = progress
    self.estimatedTimeRemaining = estimatedTimeRemaining
    self.attemptNumber = attemptNumber
    self.maxAttempts = maxAttempts
  }
}

/// Progress information for transcription
public struct TranscriptionProgress: Sendable {
  public let currentSegments: [Segment]
  public let progress: Float  // 0.0 to 1.0
  public let statusMessage: String
  public let estimatedTimeRemaining: TimeInterval?

  public init(
    currentSegments: [Segment], progress: Float, statusMessage: String,
    estimatedTimeRemaining: TimeInterval? = nil
  ) {
    self.currentSegments = currentSegments
    self.progress = progress
    self.statusMessage = statusMessage
    self.estimatedTimeRemaining = estimatedTimeRemaining
  }
}

/// Complete transcription result
public struct TranscriptionResult: Sendable, Codable {
  public let segments: [Segment]
  public let totalDuration: TimeInterval
  public let processingTime: TimeInterval
  public let modelUsed: String
  public let createdAt: Date

  public var fullText: String {
    segments.map { $0.text }.joined(separator: " ")
  }

  public init(
    segments: [Segment], totalDuration: TimeInterval, processingTime: TimeInterval,
    modelUsed: String, createdAt: Date = Date()
  ) {
    self.segments = segments
    self.totalDuration = totalDuration
    self.processingTime = processingTime
    self.modelUsed = modelUsed
    self.createdAt = createdAt
  }
}

public protocol Transcriber: AnyObject, Sendable {
  func warmUpModelWithProgress(progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void)
    async throws
  func transcribeWithProgress(
    audioPath: String, language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult
}

public extension Transcriber {
  func transcribeWithProgress(
    audioPath: String,
    language: Language,
    vadModel: ModelVariant,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try await transcribeWithProgress(
      audioPath: audioPath,
      language: language,
      progressHandler: progressHandler
    )
  }
}

/// Protocol for transcribers that can transcribe audio samples directly
/// without internal VAD re-segmentation or file I/O.
public protocol ChunkTranscriber: Transcriber {
  /// Transcribes a single pre-segmented audio chunk (16kHz mono Float32 samples)
  /// and returns the plain text. The caller is responsible for segmentation.
  func transcribeChunk(samples: [Float], language: Language) async throws -> String
}

/// Access level classification for transcription models
public enum ModelAccessLevel: String, Codable, Sendable {
  /// Free models are available without a subscription
  case free

  /// Pro models require an active subscription
  case pro

  /// Reserved for future enterprise-only models
  case enterprise

  /// Indicates whether this access level requires payment
  public var requiresSubscription: Bool {
    self != .free
  }
}

/// Model variants for different transcription engines
public enum ModelVariant: String, CaseIterable, Sendable, Identifiable, Codable {
  // Parakeet models
  case parakeetV2 = "parakeet-v2"
  case parakeetV3 = "parakeet-v3"

  // Qwen3 ASR models
  case qwen3ASR = "qwen3-asr-0.6b-8bit"
  case qwen3ASR06B4bit = "qwen3-asr-0.6b-4bit"
  case qwen3ASR06B5bit = "qwen3-asr-0.6b-5bit"
  case qwen3ASR06B6bit = "qwen3-asr-0.6b-6bit"
  case qwen3ASR06Bbf16 = "qwen3-asr-0.6b-bf16"
  case qwen3ASR17B4bit = "qwen3-asr-1.7b-4bit"
  case qwen3ASR17B5bit = "qwen3-asr-1.7b-5bit"
  case qwen3ASR17B6bit = "qwen3-asr-1.7b-6bit"
  case qwen3ASR17B8bit = "qwen3-asr-1.7b-8bit"
  case qwen3ASR17Bbf16 = "qwen3-asr-1.7b-bf16"

  // Qwen3 ForcedAligner models
  case qwen3ForcedAligner = "qwen3-forcedaligner-0.6b-4bit"
  case qwen3ForcedAligner06B5bit = "qwen3-forcedaligner-0.6b-5bit"
  case qwen3ForcedAligner06B6bit = "qwen3-forcedaligner-0.6b-6bit"
  case qwen3ForcedAligner06B8bit = "qwen3-forcedaligner-0.6b-8bit"
  case qwen3ForcedAligner06Bbf16 = "qwen3-forcedaligner-0.6b-bf16"

  // FireRed ASR models
  case fireRedASR2 = "firered-asr2-aed-mlx"

  // Cohere Transcribe models
  case cohereTranscribe03FP16 = "cohere-transcribe-03-2026-mlx-fp16"
  case cohereTranscribe038bit = "cohere-transcribe-03-2026-mlx-8bit"
  case cohereTranscribe034bit = "cohere-transcribe-03-2026-mlx-4bit"

  // Sortformer VAD models
  case sortformerStreaming = "diar_streaming_sortformer_4spk-v2.1-fp16"
  case sortformerOffline = "diar_sortformer_4spk-v2.0-offline"

  // Silero VAD models
  case sileroVAD = "silero-vad"

  // TTS models
  case qwen3TTS06B4bit = "qwen3-tts-0.6b-4bit"
  case qwen3TTS06B8bit = "qwen3-tts-0.6b-8bit"
  case qwen3TTS06Bbf16 = "qwen3-tts-0.6b-bf16"
  case qwen3TTS17B4bit = "qwen3-tts-1.7b-4bit"
  case qwen3TTS17B8bit = "qwen3-tts-1.7b-8bit"
  case qwen3TTS17Bbf16 = "qwen3-tts-1.7b-bf16"
  // TTS CustomVoice models (preset speakers, no reference audio required)
  case qwen3TTS06BCustomVoice4bit = "qwen3-tts-0.6b-customvoice-4bit"
  case qwen3TTS06BCustomVoice8bit = "qwen3-tts-0.6b-customvoice-8bit"
  case qwen3TTS06BCustomVoiceBf16 = "qwen3-tts-0.6b-customvoice-bf16"
  case qwen3TTS17BCustomVoice4bit = "qwen3-tts-1.7b-customvoice-4bit"
  case qwen3TTS17BCustomVoice8bit = "qwen3-tts-1.7b-customvoice-8bit"
  case qwen3TTS17BCustomVoiceBf16 = "qwen3-tts-1.7b-customvoice-bf16"
  // TTS VoiceDesign models (voice creation via text description)
  case qwen3TTS06BVoiceDesign4bit = "qwen3-tts-0.6b-voicedesign-4bit"
  case qwen3TTS06BVoiceDesign8bit = "qwen3-tts-0.6b-voicedesign-8bit"
  case qwen3TTS06BVoiceDesignBf16 = "qwen3-tts-0.6b-voicedesign-bf16"
  case qwen3TTS17BVoiceDesign4bit = "qwen3-tts-1.7b-voicedesign-4bit"
  case qwen3TTS17BVoiceDesign8bit = "qwen3-tts-1.7b-voicedesign-8bit"
  case qwen3TTS17BVoiceDesignBf16 = "qwen3-tts-1.7b-voicedesign-bf16"

  public var id: String { rawValue }

  private static let legacySileroVADRawValue = "silero-vad-v6"

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)

    if rawValue == Self.legacySileroVADRawValue {
      self = .sileroVAD
      return
    }

    guard let variant = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown ModelVariant raw value: \(rawValue)"
      )
    }
    self = variant
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var displayName: String {
    switch self {
    case .parakeetV2: return "Parakeet v2"
    case .parakeetV3: return "Parakeet v3"
    case .qwen3ASR: return "Qwen3 ASR 0.6B (8bit)"
    case .qwen3ASR06B4bit: return "Qwen3 ASR 0.6B (4bit)"
    case .qwen3ASR06B5bit: return "Qwen3 ASR 0.6B (5bit)"
    case .qwen3ASR06B6bit: return "Qwen3 ASR 0.6B (6bit)"
    case .qwen3ASR06Bbf16: return "Qwen3 ASR 0.6B (bf16)"
    case .qwen3ASR17B4bit: return "Qwen3 ASR 1.7B (4bit)"
    case .qwen3ASR17B5bit: return "Qwen3 ASR 1.7B (5bit)"
    case .qwen3ASR17B6bit: return "Qwen3 ASR 1.7B (6bit)"
    case .qwen3ASR17B8bit: return "Qwen3 ASR 1.7B (8bit)"
    case .qwen3ASR17Bbf16: return "Qwen3 ASR 1.7B (bf16)"
    case .qwen3ForcedAligner: return "Qwen3 Aligner 0.6B (4bit)"
    case .qwen3ForcedAligner06B5bit: return "Qwen3 Aligner 0.6B (5bit)"
    case .qwen3ForcedAligner06B6bit: return "Qwen3 Aligner 0.6B (6bit)"
    case .qwen3ForcedAligner06B8bit: return "Qwen3 Aligner 0.6B (8bit)"
    case .qwen3ForcedAligner06Bbf16: return "Qwen3 Aligner 0.6B (bf16)"
    case .fireRedASR2:
      return NSLocalizedString("FireRed ASR 2", comment: "FireRed model display name")
    case .cohereTranscribe03FP16: return "Cohere Transcribe 03-2026 (FP16)"
    case .cohereTranscribe038bit: return "Cohere Transcribe 03-2026 (8-bit)"
    case .cohereTranscribe034bit: return "Cohere Transcribe 03-2026 (4-bit)"
    case .sortformerStreaming:
      return NSLocalizedString("Sortformer Streaming", comment: "Sortformer streaming model display name")
    case .sortformerOffline: return "Sortformer Offline"
    case .sileroVAD: return "Silero VAD"
    case .qwen3TTS06B4bit: return "Qwen3 TTS 0.6B (4-bit)"
    case .qwen3TTS06B8bit: return "Qwen3 TTS 0.6B (8-bit)"
    case .qwen3TTS06Bbf16: return "Qwen3 TTS 0.6B (bf16)"
    case .qwen3TTS17B4bit: return "Qwen3 TTS 1.7B (4-bit)"
    case .qwen3TTS17B8bit: return "Qwen3 TTS 1.7B (8-bit)"
    case .qwen3TTS17Bbf16: return "Qwen3 TTS 1.7B (bf16)"
    case .qwen3TTS06BCustomVoice4bit: return "Qwen3 TTS 0.6B CustomVoice (4-bit)"
    case .qwen3TTS06BCustomVoice8bit: return "Qwen3 TTS 0.6B CustomVoice (8-bit)"
    case .qwen3TTS06BCustomVoiceBf16: return "Qwen3 TTS 0.6B CustomVoice (bf16)"
    case .qwen3TTS17BCustomVoice4bit: return "Qwen3 TTS 1.7B CustomVoice (4-bit)"
    case .qwen3TTS17BCustomVoice8bit: return "Qwen3 TTS 1.7B CustomVoice (8-bit)"
    case .qwen3TTS17BCustomVoiceBf16: return "Qwen3 TTS 1.7B CustomVoice (bf16)"
    case .qwen3TTS06BVoiceDesign4bit: return "Qwen3 TTS 0.6B VoiceDesign (4-bit)"
    case .qwen3TTS06BVoiceDesign8bit: return "Qwen3 TTS 0.6B VoiceDesign (8-bit)"
    case .qwen3TTS06BVoiceDesignBf16: return "Qwen3 TTS 0.6B VoiceDesign (bf16)"
    case .qwen3TTS17BVoiceDesign4bit: return "Qwen3 TTS 1.7B VoiceDesign (4-bit)"
    case .qwen3TTS17BVoiceDesign8bit: return "Qwen3 TTS 1.7B VoiceDesign (8-bit)"
    case .qwen3TTS17BVoiceDesignBf16: return "Qwen3 TTS 1.7B VoiceDesign (bf16)"
    }
  }

  public var provider: TranscriberType {
    if isParakeetModel { return .parakeet }
    if isFireRedASRModel { return .fireRed }
    if isCohereTranscribeModel { return .cohere }
    if isQwen3Model { return .qwen3 }
    if isSortformerVADModel { return .qwen3 }
    if isSileroVADModel { return .qwen3 }
    return .parakeet
  }

  public var summary: String {
    switch self {
    case .parakeetV2:
      return String(localized: "English-only model optimized for voice activity detection.", comment: "Parakeet v2 model summary")
    case .parakeetV3:
      return String(localized: "Parakeet model with multilingual support and VAD built-in.", comment: "Parakeet v3 model summary")
    case .qwen3ASR, .qwen3ASR06B4bit, .qwen3ASR06B5bit, .qwen3ASR06B6bit, .qwen3ASR06Bbf16:
      return String(localized: "MLX-based ASR (0.6B) supporting 52 languages with high efficiency on Apple Silicon.", comment: "Qwen3 ASR 0.6B model summary")
    case .qwen3ASR17B4bit, .qwen3ASR17B5bit, .qwen3ASR17B6bit, .qwen3ASR17B8bit, .qwen3ASR17Bbf16:
      return String(localized: "MLX-based ASR (1.7B) with higher accuracy, supporting 52 languages on Apple Silicon.", comment: "Qwen3 ASR 1.7B model summary")
    case .qwen3ForcedAligner, .qwen3ForcedAligner06B5bit, .qwen3ForcedAligner06B6bit,
      .qwen3ForcedAligner06B8bit, .qwen3ForcedAligner06Bbf16:
      return String(localized: "Forced alignment model for precise word-level timestamp prediction.", comment: "Qwen3 ForcedAligner model summary")
    case .fireRedASR2:
      return NSLocalizedString("FireRed ASR 2 optimized for Mandarin dialects, English, mixed speech, and lyrics recognition.", comment: "FireRed model summary")
    case .cohereTranscribe03FP16, .cohereTranscribe038bit, .cohereTranscribe034bit:
      return "Encoder-decoder ASR trained on 14 languages with strong multilingual punctuation and transcription quality."
    case .sortformerStreaming:
      return NSLocalizedString(
        "Streaming diarization and speech activity detection optimized for low-latency MLX pipelines.",
        comment: "Sortformer streaming summary"
      )
    case .sortformerOffline:
      return String(localized: "Offline diarization and speech activity detection for MLX audio processing.", comment: "Sortformer offline model summary")
    case .sileroVAD:
      return String(localized: "Lightweight voice activity detection (~2MB). No speaker identification.", comment: "Silero VAD model summary")
    case .qwen3TTS06B4bit, .qwen3TTS06B8bit, .qwen3TTS06Bbf16:
      return String(localized: "MLX-based TTS (0.6B) model for voice synthesis on Apple Silicon.", comment: "Qwen3 TTS 0.6B model summary")
    case .qwen3TTS17B4bit, .qwen3TTS17B8bit, .qwen3TTS17Bbf16:
      return String(localized: "MLX-based TTS (1.7B) model with higher quality voice synthesis on Apple Silicon.", comment: "Qwen3 TTS 1.7B model summary")
    case .qwen3TTS06BCustomVoice4bit, .qwen3TTS06BCustomVoice8bit, .qwen3TTS06BCustomVoiceBf16:
      return String(localized: "MLX-based TTS (0.6B) CustomVoice model with built-in preset speakers.", comment: "Qwen3 TTS 0.6B CustomVoice model summary")
    case .qwen3TTS17BCustomVoice4bit, .qwen3TTS17BCustomVoice8bit, .qwen3TTS17BCustomVoiceBf16:
      return String(localized: "MLX-based TTS (1.7B) CustomVoice model with built-in preset speakers, higher quality.", comment: "Qwen3 TTS 1.7B CustomVoice model summary")
    case .qwen3TTS06BVoiceDesign4bit, .qwen3TTS06BVoiceDesign8bit, .qwen3TTS06BVoiceDesignBf16:
      return String(localized: "MLX-based TTS (0.6B) VoiceDesign model — create voices from text descriptions.", comment: "Qwen3 TTS 0.6B VoiceDesign model summary")
    case .qwen3TTS17BVoiceDesign4bit, .qwen3TTS17BVoiceDesign8bit, .qwen3TTS17BVoiceDesignBf16:
      return String(localized: "MLX-based TTS (1.7B) VoiceDesign model — create voices from text descriptions, higher quality.", comment: "Qwen3 TTS 1.7B VoiceDesign model summary")
    }
  }

  /// Check if this model is a Parakeet model
  var isParakeetModel: Bool {
    switch self {
    case .parakeetV2, .parakeetV3: return true
    default: return false
    }
  }

  /// Check if this model is a Qwen3 ASR model
  var isQwen3Model: Bool {
    isQwen3ASRModel || isQwen3AlignerModel
  }

  /// Check if this model is a FireRed ASR model
  var isFireRedASRModel: Bool {
    switch self {
    case .fireRedASR2:
      return true
    default:
      return false
    }
  }

  var isCohereTranscribeModel: Bool {
    switch self {
    case .cohereTranscribe03FP16, .cohereTranscribe038bit, .cohereTranscribe034bit:
      return true
    default:
      return false
    }
  }

  /// Check if this model is a Qwen3 ASR (speech recognition) model
  var isQwen3ASRModel: Bool {
    switch self {
    case .qwen3ASR, .qwen3ASR06B4bit, .qwen3ASR06B5bit, .qwen3ASR06B6bit, .qwen3ASR06Bbf16,
      .qwen3ASR17B4bit, .qwen3ASR17B5bit, .qwen3ASR17B6bit, .qwen3ASR17B8bit, .qwen3ASR17Bbf16:
      return true
    default: return false
    }
  }

  /// Check if this model is a Qwen3 ForcedAligner model
  var isQwen3AlignerModel: Bool {
    switch self {
    case .qwen3ForcedAligner, .qwen3ForcedAligner06B5bit, .qwen3ForcedAligner06B6bit,
      .qwen3ForcedAligner06B8bit, .qwen3ForcedAligner06Bbf16:
      return true
    default: return false
    }
  }

  var isSortformerVADModel: Bool {
    switch self {
    case .sortformerStreaming, .sortformerOffline:
      return true
    default:
      return false
    }
  }

  var isSileroVADModel: Bool {
    switch self {
    case .sileroVAD:
      return true
    default:
      return false
    }
  }

  var isVADModel: Bool {
    isSortformerVADModel || isSileroVADModel
  }

  var isTTSModel: Bool {
    switch self {
    case .qwen3TTS06B4bit, .qwen3TTS06B8bit, .qwen3TTS06Bbf16,
         .qwen3TTS17B4bit, .qwen3TTS17B8bit, .qwen3TTS17Bbf16,
         .qwen3TTS06BCustomVoice4bit, .qwen3TTS06BCustomVoice8bit, .qwen3TTS06BCustomVoiceBf16,
         .qwen3TTS17BCustomVoice4bit, .qwen3TTS17BCustomVoice8bit, .qwen3TTS17BCustomVoiceBf16,
         .qwen3TTS06BVoiceDesign4bit, .qwen3TTS06BVoiceDesign8bit, .qwen3TTS06BVoiceDesignBf16,
         .qwen3TTS17BVoiceDesign4bit, .qwen3TTS17BVoiceDesign8bit, .qwen3TTS17BVoiceDesignBf16:
      return true
    default:
      return false
    }
  }

  /// Model file size in MB (approximate)
  public var fileSize: Int {
    switch self {
    case .parakeetV2: return 800
    case .parakeetV3: return 900
    case .qwen3ASR: return 400
    case .qwen3ASR06B4bit: return 300
    case .qwen3ASR06B5bit: return 300
    case .qwen3ASR06B6bit: return 300
    case .qwen3ASR06Bbf16: return 800
    case .qwen3ASR17B4bit: return 600
    case .qwen3ASR17B5bit: return 600
    case .qwen3ASR17B6bit: return 700
    case .qwen3ASR17B8bit: return 800
    case .qwen3ASR17Bbf16: return 2000
    case .qwen3ForcedAligner: return 400
    case .qwen3ForcedAligner06B5bit: return 400
    case .qwen3ForcedAligner06B6bit: return 400
    case .qwen3ForcedAligner06B8bit: return 500
    case .qwen3ForcedAligner06Bbf16: return 900
    case .fireRedASR2: return 1000
    case .cohereTranscribe03FP16: return 2200
    case .cohereTranscribe038bit: return 1200
    case .cohereTranscribe034bit: return 700
    case .sortformerStreaming: return 850
    case .sortformerOffline: return 850
    case .sileroVAD: return 2
    case .qwen3TTS06B4bit: return 400
    case .qwen3TTS06B8bit: return 500
    case .qwen3TTS06Bbf16: return 900
    case .qwen3TTS17B4bit: return 700
    case .qwen3TTS17B8bit: return 900
    case .qwen3TTS17Bbf16: return 2000
    case .qwen3TTS06BCustomVoice4bit: return 400
    case .qwen3TTS06BCustomVoice8bit: return 500
    case .qwen3TTS06BCustomVoiceBf16: return 900
    case .qwen3TTS17BCustomVoice4bit: return 700
    case .qwen3TTS17BCustomVoice8bit: return 900
    case .qwen3TTS17BCustomVoiceBf16: return 2000
    case .qwen3TTS06BVoiceDesign4bit: return 400
    case .qwen3TTS06BVoiceDesign8bit: return 500
    case .qwen3TTS06BVoiceDesignBf16: return 900
    case .qwen3TTS17BVoiceDesign4bit: return 700
    case .qwen3TTS17BVoiceDesign8bit: return 900
    case .qwen3TTS17BVoiceDesignBf16: return 2000
    }
  }

  /// Expected relative accuracy
  public var accuracy: String {
    switch self {
    case .parakeetV2, .parakeetV3: return "High"
    case .fireRedASR2: return "High"
    case .cohereTranscribe03FP16, .cohereTranscribe038bit, .cohereTranscribe034bit:
      return "High"
    case .sortformerStreaming, .sortformerOffline: return "High"
    case .sileroVAD: return "High"
    default: return "High"
    }
  }

  /// Relative speed score (0-10 scale) for UI display
  public var speedScore: Double {
    switch self {
    case .parakeetV2: return 8.8
    case .parakeetV3: return 9.0
    case .qwen3ASR06B4bit: return 9.2
    case .qwen3ASR06B5bit: return 9.0
    case .qwen3ASR06B6bit: return 8.8
    case .qwen3ASR: return 8.5
    case .qwen3ASR06Bbf16: return 7.5
    case .qwen3ASR17B4bit: return 8.0
    case .qwen3ASR17B5bit: return 7.8
    case .qwen3ASR17B6bit: return 7.5
    case .qwen3ASR17B8bit: return 7.2
    case .qwen3ASR17Bbf16: return 6.5
    case .qwen3ForcedAligner: return 9.0
    case .qwen3ForcedAligner06B5bit: return 8.8
    case .qwen3ForcedAligner06B6bit: return 8.6
    case .qwen3ForcedAligner06B8bit: return 8.3
    case .qwen3ForcedAligner06Bbf16: return 7.5
    case .fireRedASR2: return 8.1
    case .cohereTranscribe03FP16: return 6.8
    case .cohereTranscribe038bit: return 8.0
    case .cohereTranscribe034bit: return 9.1
    case .sortformerStreaming: return 8.4
    case .sortformerOffline: return 7.8
    case .sileroVAD: return 9.5
    case .qwen3TTS06B4bit: return 9.0
    case .qwen3TTS06B8bit: return 8.5
    case .qwen3TTS06Bbf16: return 7.5
    case .qwen3TTS17B4bit: return 8.0
    case .qwen3TTS17B8bit: return 7.5
    case .qwen3TTS17Bbf16: return 6.5
    case .qwen3TTS06BCustomVoice4bit: return 9.0
    case .qwen3TTS06BCustomVoice8bit: return 8.5
    case .qwen3TTS06BCustomVoiceBf16: return 7.5
    case .qwen3TTS17BCustomVoice4bit: return 8.0
    case .qwen3TTS17BCustomVoice8bit: return 7.5
    case .qwen3TTS17BCustomVoiceBf16: return 6.5
    case .qwen3TTS06BVoiceDesign4bit: return 8.8
    case .qwen3TTS06BVoiceDesign8bit: return 8.3
    case .qwen3TTS06BVoiceDesignBf16: return 7.3
    case .qwen3TTS17BVoiceDesign4bit: return 7.8
    case .qwen3TTS17BVoiceDesign8bit: return 7.3
    case .qwen3TTS17BVoiceDesignBf16: return 6.3
    }
  }

  /// Relative accuracy score (0-10 scale) for UI display
  public var accuracyScore: Double {
    switch self {
    case .parakeetV2: return 8.8
    case .parakeetV3: return 9.0
    case .qwen3ASR06B4bit: return 8.5
    case .qwen3ASR06B5bit: return 8.7
    case .qwen3ASR06B6bit: return 8.8
    case .qwen3ASR: return 9.0
    case .qwen3ASR06Bbf16: return 9.1
    case .qwen3ASR17B4bit: return 9.0
    case .qwen3ASR17B5bit: return 9.1
    case .qwen3ASR17B6bit: return 9.2
    case .qwen3ASR17B8bit: return 9.3
    case .qwen3ASR17Bbf16: return 9.5
    case .qwen3ForcedAligner: return 9.0
    case .qwen3ForcedAligner06B5bit: return 9.1
    case .qwen3ForcedAligner06B6bit: return 9.1
    case .qwen3ForcedAligner06B8bit: return 9.2
    case .qwen3ForcedAligner06Bbf16: return 9.3
    case .fireRedASR2: return 9.2
    case .cohereTranscribe03FP16: return 9.5
    case .cohereTranscribe038bit: return 9.2
    case .cohereTranscribe034bit: return 8.9
    case .sortformerStreaming: return 8.8
    case .sortformerOffline: return 9.0
    case .sileroVAD: return 8.5
    case .qwen3TTS06B4bit: return 8.5
    case .qwen3TTS06B8bit: return 9.0
    case .qwen3TTS06Bbf16: return 9.2
    case .qwen3TTS17B4bit: return 9.0
    case .qwen3TTS17B8bit: return 9.3
    case .qwen3TTS17Bbf16: return 9.5
    case .qwen3TTS06BCustomVoice4bit: return 8.5
    case .qwen3TTS06BCustomVoice8bit: return 9.0
    case .qwen3TTS06BCustomVoiceBf16: return 9.2
    case .qwen3TTS17BCustomVoice4bit: return 9.0
    case .qwen3TTS17BCustomVoice8bit: return 9.3
    case .qwen3TTS17BCustomVoiceBf16: return 9.5
    case .qwen3TTS06BVoiceDesign4bit: return 8.5
    case .qwen3TTS06BVoiceDesign8bit: return 9.0
    case .qwen3TTS06BVoiceDesignBf16: return 9.2
    case .qwen3TTS17BVoiceDesign4bit: return 9.0
    case .qwen3TTS17BVoiceDesign8bit: return 9.3
    case .qwen3TTS17BVoiceDesignBf16: return 9.5
    }
  }

  /// Supported languages for this specific model
  public var supportedLanguages: [Language] {
    switch self {
    case .parakeetV2:
      return [.english]
    case .parakeetV3:
      return [
        .english, .bulgarian, .croatian, .czech, .danish, .dutch, .estonian, .finnish,
        .french, .german, .greek, .hungarian, .italian, .latvian, .lithuanian, .maltese,
        .polish, .portuguese, .romanian, .slovak, .slovenian, .spanish, .swedish,
        .russian, .ukrainian,
      ].sorted { $0.displayName < $1.displayName }
    case _ where self.isQwen3ASRModel:
      return [
        .auto, .english, .chinese, .japanese, .korean, .french, .german,
        .spanish, .portuguese, .italian, .russian, .arabic, .hindi,
        .dutch, .polish, .turkish, .vietnamese, .thai, .indonesian,
      ]
    case _ where self.isFireRedASRModel:
      return [.auto, .chinese, .english]
    case _ where self.isCohereTranscribeModel:
      return [
        .auto, .english, .french, .german, .italian, .spanish, .portuguese,
        .greek, .dutch, .polish, .chinese, .japanese, .korean, .vietnamese,
        .arabic,
      ]
    case _ where self.isQwen3AlignerModel:
      return [
        .english, .chinese, .japanese, .korean, .french, .german,
        .spanish, .portuguese, .italian, .russian,
      ]
    default:
      return Language.allCases
    }
  }

  public var languageSummary: String {
    switch self {
    case .parakeetV2:
      return String(localized: "English only", comment: "Language support indicator: model only supports English")
    case .parakeetV3:
      return "25 supported languages"
    case _ where self.isQwen3ASRModel:
      return "52 supported languages"
    case _ where self.isFireRedASRModel:
      return NSLocalizedString("Chinese dialects, English, mixed speech, lyrics", comment: "FireRed language summary")
    case _ where self.isCohereTranscribeModel:
      return "14 supported languages"
    case _ where self.isQwen3AlignerModel:
      return "11 supported languages"
    case _ where self.isSortformerVADModel:
      return NSLocalizedString("Language independent", comment: "Sortformer language summary")
    case _ where self.isSileroVADModel:
      return NSLocalizedString("Language independent", comment: "Silero VAD language summary")
    default:
      return "All languages"
    }
  }

  public var featureHighlights: [String] {
    switch self {
    case .parakeetV2:
      return ["Voice Activity Detection", "Real-time optimized", "English tuning"]
    case .parakeetV3:
      return ["Voice Activity Detection", "Multilingual"]
    case _ where self.isQwen3ASRModel:
      return ["MLX optimized", "52 languages", "Streaming support"]
    case _ where self.isFireRedASRModel:
      return [
        NSLocalizedString("Mandarin + 20+ dialects / accents", comment: "FireRed highlight"),
        NSLocalizedString("Chinese-English mixed speech", comment: "FireRed highlight"),
        NSLocalizedString("Lyrics recognition", comment: "FireRed highlight"),
      ]
    case _ where self.isCohereTranscribeModel:
      return ["Encoder-decoder ASR", "14 languages", "Streaming support"]
    case _ where self.isQwen3AlignerModel:
      return ["Word-level timestamps", "Forced alignment", "High precision"]
    case .sortformerStreaming:
      return [
        NSLocalizedString("Streaming diarization", comment: "Sortformer streaming highlight"),
        NSLocalizedString("MLX optimized", comment: "Sortformer streaming highlight"),
        NSLocalizedString("Low-latency VAD", comment: "Sortformer streaming highlight"),
      ]
    case .sortformerOffline:
      return ["Offline diarization", "MLX optimized", "4-speaker support"]
    case .sileroVAD:
      return [
        NSLocalizedString("Lightweight (~2MB)", comment: "Silero VAD highlight"),
        NSLocalizedString("Fast inference", comment: "Silero VAD highlight"),
        NSLocalizedString("No speaker identification", comment: "Silero VAD highlight"),
      ]
    default:
      return ["High accuracy", "MLX optimized"]
    }
  }
}

/// Access level helpers for model variants
extension ModelVariant {
  /// Access level classification for this model variant
  public var accessLevel: ModelAccessLevel {
    guard SubscriptionPolicy.isBillingEnabled else { return .free }
    switch self {
    case .parakeetV3,
      .qwen3ASR17B4bit, .qwen3ASR17B5bit, .qwen3ASR17B6bit, .qwen3ASR17B8bit,
      .qwen3ASR17Bbf16,
      .fireRedASR2,
      .cohereTranscribe03FP16, .cohereTranscribe038bit, .cohereTranscribe034bit,
      .sortformerStreaming, .sortformerOffline:
      return .pro
    default:
      return .free
    }
  }
  /// Indicates whether the model requires a Pro subscription
  public var requiresProSubscription: Bool {
    accessLevel.requiresSubscription
  }

  /// Convenience list of all free models
  public static var freeModels: [ModelVariant] {
    allCases.filter { !$0.requiresProSubscription }
  }

  /// Convenience list of all Pro models
  public static var proModels: [ModelVariant] {
    allCases.filter(\.requiresProSubscription)
  }

  /// All Qwen3 ForcedAligner model variants
  public static var alignerModels: [ModelVariant] {
    allCases.filter { $0.isQwen3AlignerModel && !$0.isHiddenFromSelection }
  }

  /// All VAD model variants (Sortformer + Silero).
  public static var vadModels: [ModelVariant] {
    allCases.filter { $0.isVADModel && !$0.isHiddenFromSelection }
  }

  /// All TTS model variants.
  public static var ttsModels: [ModelVariant] {
    allCases.filter { $0.isTTSModel }
  }

  /// Variants hidden from model-selection UI to keep the catalog focused.
  public var isHiddenFromSelection: Bool {
    switch self {
    case .qwen3ASR06B5bit, .qwen3ASR06B6bit, .qwen3ASR17B5bit, .qwen3ASR17B6bit,
      .qwen3ForcedAligner06B5bit, .qwen3ForcedAligner06B6bit, .sortformerOffline:
      return true
    default:
      return false
    }
  }
}

/// Available transcription engines
public enum TranscriberType: String, CaseIterable, Identifiable, Codable, Sendable {
  case whisper
  case parakeet = "parakeet"
  case qwen3 = "qwen3"
  case fireRed = "fireRed"
  case cohere = "cohere"

  public var id: String { rawValue }

  /// Whether this engine should appear in user-facing pickers.
  /// Whisper is retained for backward compatibility with persisted configs but hidden from UI.
  public var isSelectableByUser: Bool {
    switch self {
    case .whisper: return false
    default: return true
    }
  }

  /// All engine cases that should appear in user-facing pickers.
  public static var selectableCases: [TranscriberType] {
    allCases.filter { $0.isSelectableByUser }
  }

  public var displayName: String {
    switch self {
    case .whisper: return String(localized: "Whisper", comment: "Transcription engine name: OpenAI Whisper")
    case .parakeet: return String(localized: "Parakeet", comment: "Transcription engine name: Parakeet")
    case .qwen3: return String(localized: "Qwen3 ASR", comment: "Transcription engine name: Qwen3 ASR")
    case .fireRed:
      return NSLocalizedString("FireRed", comment: "FireRed engine display name")
    case .cohere:
      return NSLocalizedString("Cohere", comment: "Cohere engine display name")
    }
  }

  public var description: String {
    switch self {
    case .whisper: return String(localized: "OpenAI Whisper models with configurable local downloads", comment: "Whisper engine description")
    case .parakeet: return String(localized: "Parakeet engine with voice activity detection", comment: "Parakeet engine description")
    case .qwen3: return String(localized: "Qwen3 ASR with MLX optimization for Apple Silicon", comment: "Qwen3 ASR engine description")
    case .fireRed:
      return NSLocalizedString("FireRed ASR for Mandarin dialects, English, mixed speech, and lyrics recognition", comment: "FireRed engine description")
    case .cohere:
      return "Cohere Transcribe multilingual ASR optimized for Apple Silicon with paid MLX checkpoints."
    }
  }

  public var supportedModels: [ModelVariant] {
    switch self {
    case .whisper:
      return [.parakeetV3]  // Whisper removed; redirect to Parakeet for saved configs
    case .parakeet: return [.parakeetV2, .parakeetV3]
    case .qwen3:
      return ModelVariant.allCases.filter { $0.isQwen3ASRModel && !$0.isHiddenFromSelection }
    case .fireRed:
      return [.fireRedASR2]
    case .cohere:
      return [.cohereTranscribe03FP16, .cohereTranscribe038bit, .cohereTranscribe034bit]
    }
  }

  // Deprecated: Use ModelVariant.supportedLanguages instead
  public var supportedLanguages: [Language] {
    switch self {
    case .whisper, .parakeet: return Language.allCases
    case .qwen3: return Language.allCases
    case .fireRed: return [.auto, .chinese, .english]
    case .cohere:
      return [
        .auto, .english, .french, .german, .italian, .spanish, .portuguese,
        .greek, .dutch, .polish, .chinese, .japanese, .korean, .vietnamese,
        .arabic,
      ]
    }
  }

  public func createTranscriber(model: ModelVariant = .parakeetV3) -> Transcriber {
    switch self {
    case .whisper:
      let parakeetModel = model.isParakeetModel ? model : .parakeetV3
      return MLXParakeetTranscriber(model: parakeetModel)
    case .parakeet:
      let parakeetModel = model.isParakeetModel ? model : .parakeetV2
      return MLXParakeetTranscriber(model: parakeetModel)
    case .qwen3:
      let qwenModel = model.isQwen3Model ? model : .qwen3ASR
      return Qwen3ASRTranscriber(model: qwenModel)
    case .fireRed:
      let fireRedModel = model.isFireRedASRModel ? model : .fireRedASR2
      return FireRedASRTranscriber(model: fireRedModel)
    case .cohere:
      let cohereModel = model.isCohereTranscribeModel ? model : .cohereTranscribe03FP16
      return CohereTranscribeASRTranscriber(model: cohereModel)
    }
  }
}
