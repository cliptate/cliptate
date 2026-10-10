import Foundation

/// 默认字幕样式配置
let defaultSubtitleStyles: SubtitleStylesConfiguration = {
  let landscape = SubtitleStyleSet.makeDefault(
    primaryFontSize: 55,
    translationFontSize: 40,
    highlightFontSize: 60
  )

  let portrait = SubtitleStyleSet.makeDefault(
    primaryFontSize: 48,
    translationFontSize: 34,
    highlightFontSize: 54
  )

  return SubtitleStylesConfiguration(landscape: landscape, portrait: portrait)
}()

/// Voice reference mode for dubbing: auto-extract from source or use custom reference.
public enum DubbingVoiceReferenceMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case automatic
  case custom

  public var id: String { rawValue }
}

/// AI Provider 类型
enum AIProvider: String, CaseIterable, Identifiable, Codable {
  case openai = "OpenAI"
  case gemini = "Gemini"
  case deepseek = "DeepSeek"
  case anthropic = "Anthropic"
  case groq = "Groq"

  var id: String { rawValue }

  var displayName: String { rawValue }

  var placeholderKey: String {
    switch self {
    case .openai: return "sk-..."
    case .gemini: return "AIza..."
    case .deepseek: return "sk-..."
    case .anthropic: return "sk-ant-..."
    case .groq: return "gsk_..."
    }
  }
}

extension AIProvider {
  var defaultModel: String {
    switch self {
    case .openai: return "gpt-5.4-nano"
    case .gemini: return "gemini-flash-lite-latest"
    case .deepseek: return "deepseek-v4-flash"
    case .anthropic: return "claude-haiku-4-5"
    case .groq: return "llama-3.3-8b-instruct"
    }
  }

  static var defaultModelMap: [AIProvider: String] {
    var map: [AIProvider: String] = [:]
    for provider in AIProvider.allCases {
      map[provider] = provider.defaultModel
    }
    return map
  }
}

/// 全局应用配置，集中管理可调参数（模型、语言、padding 等）
@MainActor
final class AppConfiguration: ObservableObject {
  static let shared = AppConfiguration()
  static let defaultOpenAIEndpoint = "https://api.openai.com/v1"
  nonisolated static let defaultSystemCorrectionPrompt =
    "You are a helpful assistant that corrects transcription errors."
  nonisolated static let defaultSystemKeywordPrompt =
    "You are an expert content editor that extracts concise keywords from speech transcripts."

  init() {
    let defaults = Self.defaultSnapshot
    transcriberType = defaults.transcriberType
    modelVariant = defaults.modelVariant
    language = defaults.language
    useHuggingFaceMirror = defaults.useHuggingFaceMirror
    voiceToTextTranscriberType = defaults.voiceToTextTranscriberType
    voiceToTextModelVariant = defaults.voiceToTextModelVariant
    voiceToTextLanguage = defaults.voiceToTextLanguage
    voiceToTextDictationAIEnhanceEnabled = defaults.voiceToTextDictationAIEnhanceEnabled
    voiceToTextAssistantAIEnhanceEnabled = defaults.voiceToTextAssistantAIEnhanceEnabled
    voiceToTextAssistantIncludeClipboardContext =
      defaults.voiceToTextAssistantIncludeClipboardContext
    voiceToTextAssistantIncludeWindowContext =
      defaults.voiceToTextAssistantIncludeWindowContext
    voiceToTextCustomDictionary =
      AppConfiguration.normalizeDictionaryEntries(defaults.voiceToTextCustomDictionary)
    alignModelVariant = defaults.alignModelVariant
    vadModelVariant = defaults.vadModelVariant
    modelCleanupTimeoutSeconds = defaults.modelCleanupTimeoutSeconds
    asrIdleTimeoutSeconds = defaults.asrIdleTimeoutSeconds
    ttsEngine = defaults.ttsEngine
    ttsVariantPreference = defaults.ttsVariantPreference
    ttsSpeakingRate = defaults.ttsSpeakingRate
    ttsMLXModelId = defaults.ttsMLXModelId
    ttsVoiceDescription = defaults.ttsVoiceDescription
    ttsPresetSpeaker = defaults.ttsPresetSpeaker
    ttsEmotionPrompt = defaults.ttsEmotionPrompt
    ttsReferenceAudioPath = defaults.ttsReferenceAudioPath
    ttsReferenceAudioBookmark = defaults.ttsReferenceAudioBookmark
    ttsReferenceText = defaults.ttsReferenceText
    ttsLanguage = defaults.ttsLanguage
    leftPadMs = defaults.leftPadMs
    rightPadMs = defaults.rightPadMs
    filterSilent = defaults.filterSilent
    splitBySentence = defaults.splitBySentence

    splitBySilence = defaults.splitBySilence
    splitThreshold = defaults.splitThreshold
    maxCharsPerSegment = defaults.maxCharsPerSegment
    fcpxmlEnabled = defaults.fcpxmlEnabled
    fcpxmlFrameRate = defaults.fcpxmlFrameRate
    fcpxmlIncludeSubtitles = defaults.fcpxmlIncludeSubtitles
    fcpxmlProjectName = defaults.fcpxmlProjectName
    fcpxmlIsResolveCompatible = defaults.fcpxmlIsResolveCompatible
    fcpxmlSpeed = defaults.fcpxmlSpeed
    exportMode = defaults.exportMode
    videoExportEnabled = defaults.videoExportEnabled
    videoExportFormat = defaults.videoExportFormat
    videoExportBurnInSubtitles = defaults.videoExportBurnInSubtitles
    keepPunctuationOnExport = defaults.keepPunctuationOnExport ?? true
    videoExportQuality = defaults.videoExportQuality
    audioExportEnabled = defaults.audioExportEnabled
    audioExportFormat = defaults.audioExportFormat
    audioDubbingEnabled = defaults.audioDubbingEnabled
    dubbingVoiceReferenceMode = defaults.dubbingVoiceReferenceMode
    effectExtractHighlights = defaults.effectExtractHighlights
    effectEnableScaling = defaults.effectEnableScaling
    effectScaleMultiplier = defaults.effectScaleMultiplier
    effectEnableZoom = defaults.effectEnableZoom
    effectZoomMultiplier = defaults.effectZoomMultiplier
    effectFilterFillerWords = defaults.effectFilterFillerWords
    effectFillerWords = defaults.effectFillerWords
    translationPlacement = defaults.translationPlacement
    translationSourceLanguage = defaults.translationSourceLanguage
    translationTargetLanguage = defaults.translationTargetLanguage
    subtitleStyles = defaults.subtitleStyles
    subtitleExportFormats = defaults.subtitleExportFormats
    aiProviderKeys = defaults.aiProviderKeys
    selectedAIProvider = defaults.selectedAIProvider
    aiEnabled = defaults.aiEnabled
    aiOpenAIEndpoint = defaults.aiOpenAIEndpoint
    aiDefaultCorrectionPrompt = defaults.aiDefaultCorrectionPrompt
    aiDefaultEnhancePrompt = defaults.aiDefaultEnhancePrompt
    aiProviderModels = defaults.aiProviderModels
    aiIncludeClipboardContext = defaults.aiIncludeClipboardContext
    aiIncludeWindowContext = defaults.aiIncludeWindowContext
    voiceToTextUsageTotalDuration = defaults.voiceToTextUsageTotalDuration
    voiceToTextUsageSessionCount = defaults.voiceToTextUsageSessionCount
    voiceToTextUsageTotalCharacters = defaults.voiceToTextUsageTotalCharacters
    voiceToTextUsageTotalWords = defaults.voiceToTextUsageTotalWords
  }

  // 转写相关
  @Published var transcriberType: TranscriberType {
    didSet {
      guard transcriberType != oldValue else { return }
      if voiceToTextTranscriberType != transcriberType {
        voiceToTextTranscriberType = transcriberType
      }
      scheduleNormalization {
        self.normalizeAfterTranscriberChange()
      }
    }
  }
  @Published var modelVariant: ModelVariant {
    didSet {
      guard modelVariant != oldValue else { return }
      if voiceToTextModelVariant != modelVariant {
        voiceToTextModelVariant = modelVariant
      }
      scheduleNormalization {
        self.normalizeAfterModelChange()
      }
    }
  }
  @Published var language: Language
  // 控制是否启用 Hugging Face 镜像
  @Published var useHuggingFaceMirror: Bool

  // Voice To Text 独立配置（不影响 Voice Cut）
  @Published var voiceToTextTranscriberType: TranscriberType = .parakeet {
    didSet {
      guard voiceToTextTranscriberType != oldValue else { return }
      scheduleNormalization {
        self.normalizeVoiceToTextAfterTranscriberChange()
      }
    }
  }
  @Published var voiceToTextModelVariant: ModelVariant = .parakeetV3 {
    didSet {
      guard voiceToTextModelVariant != oldValue else { return }
      scheduleNormalization {
        self.normalizeVoiceToTextAfterModelChange()
      }
    }
  }
  @Published var voiceToTextLanguage: Language = .english
  @Published var voiceToTextDictationAIEnhanceEnabled: Bool
  @Published var voiceToTextAssistantAIEnhanceEnabled: Bool
  @Published var voiceToTextAssistantIncludeClipboardContext: Bool
  @Published var voiceToTextAssistantIncludeWindowContext: Bool
  @Published var voiceToTextCustomDictionary: [String]

  var activeVoiceToTextTranscriberType: TranscriberType { transcriberType }
  var activeVoiceToTextModelVariant: ModelVariant { modelVariant }

  // Align model selection (ForcedAligner variant used for timestamp alignment, nil = disabled)
  @Published var alignModelVariant: ModelVariant?

  // VAD model selection used by MLX/Qwen3 streaming dictation.
  @Published var vadModelVariant: ModelVariant {
    didSet {
      guard vadModelVariant != oldValue else { return }
      // Accept any streaming-capable VAD model (Silero or Sortformer streaming).
      // Reject sortformerOffline and non-VAD models.
      if !vadModelVariant.isVADModel || vadModelVariant == .sortformerOffline {
        vadModelVariant = .sileroVAD
      }
    }
  }

  // Model lifecycle configuration and observable state
  @Published var modelCleanupTimeoutSeconds: TimeInterval {
    didSet {
      if modelCleanupTimeoutSeconds < 60 {
        modelCleanupTimeoutSeconds = 60
      }
      Task {
        await ModelCacheManager.shared.updateCleanupTimeout(seconds: modelCleanupTimeoutSeconds)
      }
    }
  }
  @Published var asrIdleTimeoutSeconds: TimeInterval {
    didSet {
      if asrIdleTimeoutSeconds < 60 {
        asrIdleTimeoutSeconds = 60
      }
      Task {
        await ModelCacheManager.shared.updateASRIdleTimeout(seconds: asrIdleTimeoutSeconds)
      }
    }
  }
  @Published private(set) var modelLifecycleStatuses: [ModelLifecycleStatus] = []
  @Published private(set) var modelLifecycleTotalMemoryMB: Int = 0

  // Voice To Text usage statistics (persisted across launches)
  @Published var voiceToTextUsageTotalDuration: TimeInterval
  @Published var voiceToTextUsageSessionCount: Int
  @Published var voiceToTextUsageTotalCharacters: Int
  @Published var voiceToTextUsageTotalWords: Int

  // Text-to-Speech
  @Published var ttsEngine: TTSEngine
  @Published var ttsVariantPreference: TTSVariantPreference
  @Published var ttsSpeakingRate: Double {
    didSet {
      if ttsSpeakingRate < 0.5 { ttsSpeakingRate = 0.5 }
      if ttsSpeakingRate > 1.5 { ttsSpeakingRate = 1.5 }
    }
  }
  @Published var ttsMLXModelId: String {
    didSet {
      let knownModelIDs = Set(MLXTTSModelDefinition.availableModels.map { $0.huggingFaceRepo })
      guard knownModelIDs.contains(ttsMLXModelId) else {
        ttsMLXModelId =
          MLXTTSModelDefinition.availableModels.first?.huggingFaceRepo
          ?? "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
        return
      }
    }
  }
  @Published var ttsVoiceDescription: String
  @Published var ttsPresetSpeaker: String
  /// Emotion or style prompt appended to the speaker name for CustomVoice synthesis.
  /// Composed as "SpeakerName, emotionPrompt" when both are non-empty.
  @Published var ttsEmotionPrompt: String
  @Published var ttsReferenceAudioPath: String
  /// Security-scoped bookmark data for the reference audio file.
  /// Must be stored alongside the path to allow sandbox access across app restarts.
  @Published var ttsReferenceAudioBookmark: Data?
  @Published var ttsReferenceText: String
  @Published var ttsLanguage: String

  // 字幕时间 padding（毫秒）
  @Published var leftPadMs: Int {
    didSet { if leftPadMs < 0 { leftPadMs = 100 } }
  }

  @Published var rightPadMs: Int {
    didSet { if rightPadMs < 0 { rightPadMs = 100 } }
  }

  // 过滤静音
  @Published var filterSilent: Bool

  // 控制按句子拆分
  @Published var splitBySentence: Bool

  // 按静音间隔拆分
  @Published var splitBySilence: Bool

  // 静音拆分阈值（秒）：当两个连续 word 之间的间隔超过此阈值时，在该位置分割 segment
  @Published var splitThreshold: Double {
    didSet {
      if splitThreshold < 0.01 { splitThreshold = 0.01 }
      if splitThreshold > 2.0 { splitThreshold = 2.0 }
    }
  }

  // 每段最大字符数。0 表示关闭拆分；>0 启用按字/字符聚合拆分。默认 30，允许 0..100。
  @Published var maxCharsPerSegment: Int {
    didSet {
      if maxCharsPerSegment < 0 { maxCharsPerSegment = 0 }
      if maxCharsPerSegment > 100 { maxCharsPerSegment = 100 }
    }
  }

  // FCPXML 导出相关
  @Published var fcpxmlEnabled: Bool
  @Published var fcpxmlFrameRate: Double {
    didSet {
      if fcpxmlFrameRate <= 0 { fcpxmlFrameRate = 25.0 }
      if fcpxmlFrameRate > 120 { fcpxmlFrameRate = 120.0 }
    }
  }

  @Published var fcpxmlIncludeSubtitles: Bool
  // 配置导出文件名前缀（最终名称会自动追加当天日期）
  @Published var fcpxmlProjectName: String
  @Published var fcpxmlIsResolveCompatible: Bool
  @Published var fcpxmlSpeed: Double {
    didSet {
      if fcpxmlSpeed < 0.1 { fcpxmlSpeed = 0.1 }
      if fcpxmlSpeed > 10.0 { fcpxmlSpeed = 10.0 }
    }
  }
  @Published var exportMode: ExportMode

  // 视频导出
  @Published var videoExportEnabled: Bool
  @Published var videoExportFormat: VideoExportFormat
  @Published var videoExportBurnInSubtitles: Bool
  @Published var keepPunctuationOnExport: Bool
  @Published var videoExportQuality: VideoExportQuality
  @Published var audioExportEnabled: Bool
  @Published var audioExportFormat: AudioExportFormat
  @Published var audioDubbingEnabled: Bool
  @Published var dubbingVoiceReferenceMode: DubbingVoiceReferenceMode

  // Effect 配置
  @Published var effectExtractHighlights: Bool
  @Published var effectEnableScaling: Bool
  @Published var effectScaleMultiplier: Double {
    didSet {
      if effectScaleMultiplier < 1.0 { effectScaleMultiplier = 1.0 }
      if effectScaleMultiplier > 2.5 { effectScaleMultiplier = 2.5 }
    }
  }
  @Published var effectEnableZoom: Bool
  @Published var effectZoomMultiplier: Double {
    didSet {
      if effectZoomMultiplier < 1.0 { effectZoomMultiplier = 1.0 }
      if effectZoomMultiplier > 3.0 { effectZoomMultiplier = 3.0 }
    }
  }
  @Published var effectFilterFillerWords: Bool
  @Published var effectFillerWords: [String]
  @Published var translationPlacement: SubtitleTranslationPlacement
  @Published var translationSourceLanguage: Language
  @Published var translationTargetLanguage: Language
  @Published var subtitleStyles: SubtitleStylesConfiguration
  @Published var subtitleExportFormats: Set<SubtitleExportFormat>

  // AI Provider 配置
  @Published var aiProviderKeys: [AIProvider: String]
  @Published var selectedAIProvider: AIProvider
  @Published var aiEnabled: Bool
  @Published var aiOpenAIEndpoint: String
  @Published var aiDefaultCorrectionPrompt: String
  @Published var aiDefaultEnhancePrompt: String
  @Published var aiProviderModels: [AIProvider: String]
  @Published var aiIncludeClipboardContext: Bool
  @Published var aiIncludeWindowContext: Bool

  var aiSystemCorrectionPrompt: String { Self.defaultSystemCorrectionPrompt }
  var aiSystemKeywordPrompt: String { Self.defaultSystemKeywordPrompt }

  var resolvedOpenAIEndpoint: String {
    let trimmed = aiOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? Self.defaultOpenAIEndpoint : trimmed
  }

  var hasAnyExportsEnabled: Bool {
    fcpxmlEnabled || !subtitleExportFormats.isEmpty || videoExportEnabled || audioExportEnabled
  }

  var effectConfiguration: SegmentEffectConfiguration {
    SegmentEffectConfiguration(
      extractHighlights: effectExtractHighlights,
      enableScaling: effectEnableScaling,
      scaleMultiplier: effectScaleMultiplier,
      enableZoom: effectEnableZoom,
      zoomMultiplier: effectZoomMultiplier,
      filterFillerWords: effectFilterFillerWords,
      fillerWords: effectFillerWords
    )
  }

  func subtitleStyleSet(for orientation: SubtitleOrientation) -> SubtitleStyleSet {
    subtitleStyles[orientation]
  }

  func updateSubtitleStyleSet(_ set: SubtitleStyleSet, for orientation: SubtitleOrientation) {
    var next = subtitleStyles
    next[orientation] = set
    guard next != subtitleStyles else { return }
    subtitleStyles = next
  }

  func defaultExportRequest() -> ExportAllRequest {
    ExportAllRequest(
      includeFCPXML: fcpxmlEnabled,
      exportMode: exportMode,
      includeSubtitleFiles: !subtitleExportFormats.isEmpty,
      includeVideos: videoExportEnabled,
      includeAudio: audioExportEnabled,
      burnSubtitlesIntoVideo: videoExportBurnInSubtitles,
      videoQuality: videoExportQuality,
      audioFormat: audioExportFormat
    )
  }

  @MainActor
  func updateAIProviderKey(_ key: String?, for provider: AIProvider) {
    var next = aiProviderKeys
    let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      next[provider] = trimmed
    } else {
      next.removeValue(forKey: provider)
    }
    guard next != aiProviderKeys else { return }
    aiProviderKeys = next
  }

  func aiModel(for provider: AIProvider) -> String {
    let stored = aiProviderModels[provider]?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let stored, !stored.isEmpty {
      return stored
    }
    return provider.defaultModel
  }

  @MainActor
  func updateAIProviderModel(_ model: String?, for provider: AIProvider) {
    var next = aiProviderModels
    let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      next[provider] = trimmed
    } else {
      next.removeValue(forKey: provider)
    }
    guard next != aiProviderModels else { return }
    aiProviderModels = next
  }
}

// MARK: - Preset Snapshot Helpers
extension AppConfiguration {
  private func scheduleNormalization(_ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      work()
    }
  }

  private func normalizeAfterTranscriberChange() {
    if transcriberType == .parakeet, !modelVariant.isParakeetModel {
      modelVariant = .parakeetV3
    } else if transcriberType == .whisper,
      !modelVariant.isParakeetModel
    {
      modelVariant = .parakeetV3
    } else if transcriberType == .qwen3, !modelVariant.isQwen3ASRModel {
      modelVariant = .qwen3ASR
    } else if transcriberType == .cohere, !modelVariant.isCohereTranscribeModel {
      modelVariant = .cohereTranscribe03FP16
    }

    if !transcriberType.supportedModels.contains(modelVariant),
      let fallback = transcriberType.supportedModels.first
    {
      modelVariant = fallback
    }

    normalizeAfterModelChange()
  }

  private func normalizeAfterModelChange() {
    guard !modelVariant.supportedLanguages.isEmpty else { return }
    if !modelVariant.supportedLanguages.contains(language) {
      language = modelVariant.supportedLanguages.first ?? .english
    }
  }

  private func normalizeVoiceToTextAfterTranscriberChange() {
    if voiceToTextTranscriberType == .parakeet, !voiceToTextModelVariant.isParakeetModel {
      voiceToTextModelVariant = .parakeetV3
    } else if voiceToTextTranscriberType == .whisper, !voiceToTextModelVariant.isParakeetModel {
      voiceToTextModelVariant = .parakeetV3
    } else if voiceToTextTranscriberType == .cohere,
      !voiceToTextModelVariant.isCohereTranscribeModel
    {
      voiceToTextModelVariant = .cohereTranscribe03FP16
    } else if !voiceToTextTranscriberType.supportedModels.contains(voiceToTextModelVariant),
      let fallback = voiceToTextTranscriberType.supportedModels.first
    {
      voiceToTextModelVariant = fallback
    }

    normalizeVoiceToTextAfterModelChange()
  }

  private func normalizeVoiceToTextAfterModelChange() {
    guard !voiceToTextModelVariant.supportedLanguages.isEmpty else { return }
    if !voiceToTextModelVariant.supportedLanguages.contains(voiceToTextLanguage) {
      voiceToTextLanguage = voiceToTextModelVariant.supportedLanguages.first ?? .english
    }
  }

  func normalizeModelSelections() {
    if vadModelVariant == .sortformerOffline {
      vadModelVariant = .sileroVAD
    }
  }

  func refreshModelLifecycleState() async {
    let snapshot = await ModelCacheManager.shared.snapshot()
    modelLifecycleStatuses = snapshot.statuses
    modelLifecycleTotalMemoryMB = snapshot.totalMemoryUsageMB
  }

  struct Snapshot: Equatable, Codable, Sendable {
    var transcriberType: TranscriberType
    var modelVariant: ModelVariant
    var language: Language
    var useHuggingFaceMirror: Bool
    var voiceToTextTranscriberType: TranscriberType
    var voiceToTextModelVariant: ModelVariant
    var voiceToTextLanguage: Language
    var voiceToTextDictationAIEnhanceEnabled: Bool = true
    var voiceToTextAssistantAIEnhanceEnabled: Bool = true
    var voiceToTextAssistantIncludeClipboardContext: Bool = true
    var voiceToTextAssistantIncludeWindowContext: Bool = true
    var voiceToTextCustomDictionary: [String]
    var alignModelVariant: ModelVariant?
    var vadModelVariant: ModelVariant
    var modelCleanupTimeoutSeconds: TimeInterval = 600
    var asrIdleTimeoutSeconds: TimeInterval = 600
    var ttsEngine: TTSEngine
    var ttsVariantPreference: TTSVariantPreference
    var ttsSpeakingRate: Double
    var ttsMLXModelId: String
    var ttsVoiceDescription: String
    var ttsPresetSpeaker: String = ""
    var ttsEmotionPrompt: String = ""
    var ttsReferenceAudioPath: String
    var ttsReferenceAudioBookmark: Data?
    var ttsReferenceText: String
    var ttsLanguage: String
    var leftPadMs: Int
    var rightPadMs: Int
    var splitBySentence: Bool
    var splitBySilence: Bool
    var splitThreshold: Double
    var maxCharsPerSegment: Int
    var filterSilent: Bool
    var fcpxmlEnabled: Bool
    var fcpxmlProjectName: String
    var fcpxmlFrameRate: Double
    var fcpxmlIncludeSubtitles: Bool
    var fcpxmlIsResolveCompatible: Bool
    var fcpxmlSpeed: Double
    var exportMode: ExportMode
    var videoExportEnabled: Bool
    var videoExportFormat: VideoExportFormat
    var videoExportBurnInSubtitles: Bool
    var keepPunctuationOnExport: Bool?
    var videoExportQuality: VideoExportQuality
    var audioExportEnabled: Bool
    var audioExportFormat: AudioExportFormat
    var audioDubbingEnabled: Bool
    var dubbingVoiceReferenceMode: DubbingVoiceReferenceMode
    var effectExtractHighlights: Bool
    var effectEnableScaling: Bool
    var effectScaleMultiplier: Double
    var effectEnableZoom: Bool
    var effectZoomMultiplier: Double
    var effectFilterFillerWords: Bool
    var effectFillerWords: [String]
    var translationPlacement: SubtitleTranslationPlacement
    var translationSourceLanguage: Language
    var translationTargetLanguage: Language
    var subtitleStyles: SubtitleStylesConfiguration
    var subtitleExportFormats: Set<SubtitleExportFormat>
    var aiProviderKeys: [AIProvider: String]
    var selectedAIProvider: AIProvider
    var aiEnabled: Bool
    var aiOpenAIEndpoint: String
    var aiDefaultCorrectionPrompt: String
    var aiDefaultEnhancePrompt: String
    var aiProviderModels: [AIProvider: String]
    var aiIncludeClipboardContext: Bool
    var aiIncludeWindowContext: Bool
    var voiceToTextUsageTotalDuration: TimeInterval
    var voiceToTextUsageSessionCount: Int
    var voiceToTextUsageTotalCharacters: Int
    var voiceToTextUsageTotalWords: Int = 0
  }
}

// MARK: - Snapshot backward-compatible Decodable
extension AppConfiguration.Snapshot {
  /// Custom decoder that tolerates missing keys for fields that were added after
  /// the initial release. Fields with in-struct defaults use `decodeIfPresent`
  /// so old persisted snapshots still decode correctly.
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    transcriberType = try c.decode(TranscriberType.self, forKey: .transcriberType)
    modelVariant = try c.decode(ModelVariant.self, forKey: .modelVariant)
    language = try c.decode(Language.self, forKey: .language)
    useHuggingFaceMirror = try c.decode(Bool.self, forKey: .useHuggingFaceMirror)
    voiceToTextTranscriberType = try c.decode(TranscriberType.self, forKey: .voiceToTextTranscriberType)
    voiceToTextModelVariant = try c.decode(ModelVariant.self, forKey: .voiceToTextModelVariant)
    voiceToTextLanguage = try c.decode(Language.self, forKey: .voiceToTextLanguage)
    voiceToTextDictationAIEnhanceEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceToTextDictationAIEnhanceEnabled) ?? true
    voiceToTextAssistantAIEnhanceEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceToTextAssistantAIEnhanceEnabled) ?? true
    voiceToTextAssistantIncludeClipboardContext = try c.decodeIfPresent(Bool.self, forKey: .voiceToTextAssistantIncludeClipboardContext) ?? true
    voiceToTextAssistantIncludeWindowContext = try c.decodeIfPresent(Bool.self, forKey: .voiceToTextAssistantIncludeWindowContext) ?? true
    voiceToTextCustomDictionary = try c.decode([String].self, forKey: .voiceToTextCustomDictionary)
    alignModelVariant = try c.decodeIfPresent(ModelVariant.self, forKey: .alignModelVariant)
    vadModelVariant = try c.decode(ModelVariant.self, forKey: .vadModelVariant)
    modelCleanupTimeoutSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .modelCleanupTimeoutSeconds) ?? 600
    asrIdleTimeoutSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .asrIdleTimeoutSeconds) ?? 600
    ttsEngine = try c.decode(TTSEngine.self, forKey: .ttsEngine)
    ttsVariantPreference = try c.decode(TTSVariantPreference.self, forKey: .ttsVariantPreference)
    ttsSpeakingRate = try c.decode(Double.self, forKey: .ttsSpeakingRate)
    ttsMLXModelId = try c.decode(String.self, forKey: .ttsMLXModelId)
    ttsVoiceDescription = try c.decode(String.self, forKey: .ttsVoiceDescription)
    ttsPresetSpeaker = try c.decodeIfPresent(String.self, forKey: .ttsPresetSpeaker) ?? ""
    ttsEmotionPrompt = try c.decodeIfPresent(String.self, forKey: .ttsEmotionPrompt) ?? ""
    ttsReferenceAudioPath = try c.decode(String.self, forKey: .ttsReferenceAudioPath)
    ttsReferenceAudioBookmark = try c.decodeIfPresent(Data.self, forKey: .ttsReferenceAudioBookmark)
    ttsReferenceText = try c.decode(String.self, forKey: .ttsReferenceText)
    ttsLanguage = try c.decode(String.self, forKey: .ttsLanguage)
    leftPadMs = try c.decode(Int.self, forKey: .leftPadMs)
    rightPadMs = try c.decode(Int.self, forKey: .rightPadMs)
    splitBySentence = try c.decode(Bool.self, forKey: .splitBySentence)
    splitBySilence = try c.decode(Bool.self, forKey: .splitBySilence)
    splitThreshold = try c.decode(Double.self, forKey: .splitThreshold)
    maxCharsPerSegment = try c.decode(Int.self, forKey: .maxCharsPerSegment)
    filterSilent = try c.decode(Bool.self, forKey: .filterSilent)
    fcpxmlEnabled = try c.decode(Bool.self, forKey: .fcpxmlEnabled)
    fcpxmlProjectName = try c.decode(String.self, forKey: .fcpxmlProjectName)
    fcpxmlFrameRate = try c.decode(Double.self, forKey: .fcpxmlFrameRate)
    fcpxmlIncludeSubtitles = try c.decode(Bool.self, forKey: .fcpxmlIncludeSubtitles)
    fcpxmlIsResolveCompatible = try c.decode(Bool.self, forKey: .fcpxmlIsResolveCompatible)
    fcpxmlSpeed = try c.decodeIfPresent(Double.self, forKey: .fcpxmlSpeed) ?? 1.0
    exportMode = try c.decode(ExportMode.self, forKey: .exportMode)
    videoExportEnabled = try c.decode(Bool.self, forKey: .videoExportEnabled)
    videoExportFormat = try c.decode(VideoExportFormat.self, forKey: .videoExportFormat)
    videoExportBurnInSubtitles = try c.decode(Bool.self, forKey: .videoExportBurnInSubtitles)
    keepPunctuationOnExport = try c.decodeIfPresent(Bool.self, forKey: .keepPunctuationOnExport)
    videoExportQuality = try c.decode(VideoExportQuality.self, forKey: .videoExportQuality)
    audioExportEnabled = try c.decode(Bool.self, forKey: .audioExportEnabled)
    audioExportFormat = try c.decode(AudioExportFormat.self, forKey: .audioExportFormat)
    audioDubbingEnabled = try c.decodeIfPresent(Bool.self, forKey: .audioDubbingEnabled) ?? false
    dubbingVoiceReferenceMode = try c.decodeIfPresent(DubbingVoiceReferenceMode.self, forKey: .dubbingVoiceReferenceMode) ?? .automatic
    effectExtractHighlights = try c.decode(Bool.self, forKey: .effectExtractHighlights)
    effectEnableScaling = try c.decode(Bool.self, forKey: .effectEnableScaling)
    effectScaleMultiplier = try c.decode(Double.self, forKey: .effectScaleMultiplier)
    effectEnableZoom = try c.decode(Bool.self, forKey: .effectEnableZoom)
    effectZoomMultiplier = try c.decode(Double.self, forKey: .effectZoomMultiplier)
    effectFilterFillerWords = try c.decode(Bool.self, forKey: .effectFilterFillerWords)
    effectFillerWords = try c.decode([String].self, forKey: .effectFillerWords)
    translationPlacement = try c.decode(SubtitleTranslationPlacement.self, forKey: .translationPlacement)
    translationSourceLanguage = try c.decode(Language.self, forKey: .translationSourceLanguage)
    translationTargetLanguage = try c.decode(Language.self, forKey: .translationTargetLanguage)
    subtitleStyles = try c.decode(SubtitleStylesConfiguration.self, forKey: .subtitleStyles)
    subtitleExportFormats = try c.decode(Set<SubtitleExportFormat>.self, forKey: .subtitleExportFormats)
    aiProviderKeys = try c.decode([AIProvider: String].self, forKey: .aiProviderKeys)
    selectedAIProvider = try c.decode(AIProvider.self, forKey: .selectedAIProvider)
    aiEnabled = try c.decode(Bool.self, forKey: .aiEnabled)
    aiOpenAIEndpoint = try c.decode(String.self, forKey: .aiOpenAIEndpoint)
    aiDefaultCorrectionPrompt = try c.decode(String.self, forKey: .aiDefaultCorrectionPrompt)
    aiDefaultEnhancePrompt = try c.decode(String.self, forKey: .aiDefaultEnhancePrompt)
    aiProviderModels = try c.decode([AIProvider: String].self, forKey: .aiProviderModels)
    aiIncludeClipboardContext = try c.decode(Bool.self, forKey: .aiIncludeClipboardContext)
    aiIncludeWindowContext = try c.decode(Bool.self, forKey: .aiIncludeWindowContext)
    voiceToTextUsageTotalDuration = try c.decode(TimeInterval.self, forKey: .voiceToTextUsageTotalDuration)
    voiceToTextUsageSessionCount = try c.decode(Int.self, forKey: .voiceToTextUsageSessionCount)
    voiceToTextUsageTotalCharacters = try c.decode(Int.self, forKey: .voiceToTextUsageTotalCharacters)
    voiceToTextUsageTotalWords = try c.decodeIfPresent(Int.self, forKey: .voiceToTextUsageTotalWords) ?? 0
  }
}

extension AppConfiguration {
  static let defaultSnapshot = Snapshot(
    transcriberType: .parakeet,
    modelVariant: .parakeetV3,
    language: .english,
    useHuggingFaceMirror: false,
    voiceToTextTranscriberType: .parakeet,
    voiceToTextModelVariant: .parakeetV3,
    voiceToTextLanguage: .english,
    voiceToTextDictationAIEnhanceEnabled: true,
    voiceToTextAssistantAIEnhanceEnabled: true,
    voiceToTextAssistantIncludeClipboardContext: true,
    voiceToTextAssistantIncludeWindowContext: true,
    voiceToTextCustomDictionary: [],
    alignModelVariant: nil,
    vadModelVariant: .sileroVAD,
    modelCleanupTimeoutSeconds: 600,
    asrIdleTimeoutSeconds: 600,
    ttsEngine: .qwen3TTS,
    ttsVariantPreference: .automatic,
    ttsSpeakingRate: 1.0,
    ttsMLXModelId: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
    ttsVoiceDescription: "A young female speaker with a clear and gentle voice",
    ttsPresetSpeaker: "",
    ttsEmotionPrompt: "",
    ttsReferenceAudioPath: "",
    ttsReferenceAudioBookmark: nil,
    ttsReferenceText: "",
     ttsLanguage: "en",
    leftPadMs: 100,
    rightPadMs: 100,
    splitBySentence: true,
    splitBySilence: false,
    splitThreshold: 0.3,
    maxCharsPerSegment: 50,
    filterSilent: true,
    fcpxmlEnabled: true,
    fcpxmlProjectName: "Cliptate",
    fcpxmlFrameRate: 25.0,
    fcpxmlIncludeSubtitles: true,
    fcpxmlIsResolveCompatible: false,
    fcpxmlSpeed: 1.0,
    exportMode: .merge,
    videoExportEnabled: false,
    videoExportFormat: .mp4,
    videoExportBurnInSubtitles: true,
    keepPunctuationOnExport: true,
    videoExportQuality: .original,
    audioExportEnabled: false,
    audioExportFormat: .m4a,
    audioDubbingEnabled: false,
    dubbingVoiceReferenceMode: .automatic,
    effectExtractHighlights: true,
    effectEnableScaling: true,
    effectScaleMultiplier: 1.2,
    effectEnableZoom: false,
    effectZoomMultiplier: 1.2,
    effectFilterFillerWords: true,
    effectFillerWords: SegmentEffectConfiguration.defaultFillerWords,
    translationPlacement: .below,
    translationSourceLanguage: .english,
    translationTargetLanguage: .chinese,
    subtitleStyles: defaultSubtitleStyles,
    subtitleExportFormats: [],
    aiProviderKeys: [:],
    selectedAIProvider: .gemini,
    aiEnabled: false,
    aiOpenAIEndpoint: AppConfiguration.defaultOpenAIEndpoint,
    aiDefaultCorrectionPrompt: "",
    aiDefaultEnhancePrompt: "",
    aiProviderModels: AIProvider.defaultModelMap,
    aiIncludeClipboardContext: true,
    aiIncludeWindowContext: true,
    voiceToTextUsageTotalDuration: 0,
    voiceToTextUsageSessionCount: 0,
    voiceToTextUsageTotalCharacters: 0,
    voiceToTextUsageTotalWords: 0
  )

  func makeSnapshot() -> Snapshot {
    Snapshot(
      transcriberType: transcriberType,
      modelVariant: modelVariant,
      language: language,
      useHuggingFaceMirror: useHuggingFaceMirror,
      voiceToTextTranscriberType: voiceToTextTranscriberType,
      voiceToTextModelVariant: voiceToTextModelVariant,
      voiceToTextLanguage: voiceToTextLanguage,
      voiceToTextDictationAIEnhanceEnabled: voiceToTextDictationAIEnhanceEnabled,
      voiceToTextAssistantAIEnhanceEnabled: voiceToTextAssistantAIEnhanceEnabled,
      voiceToTextAssistantIncludeClipboardContext: voiceToTextAssistantIncludeClipboardContext,
      voiceToTextAssistantIncludeWindowContext: voiceToTextAssistantIncludeWindowContext,
      voiceToTextCustomDictionary: voiceToTextCustomDictionary,
      alignModelVariant: alignModelVariant,
      vadModelVariant: vadModelVariant,
      modelCleanupTimeoutSeconds: modelCleanupTimeoutSeconds,
      asrIdleTimeoutSeconds: asrIdleTimeoutSeconds,
      ttsEngine: ttsEngine,
      ttsVariantPreference: ttsVariantPreference,
      ttsSpeakingRate: ttsSpeakingRate,
      ttsMLXModelId: ttsMLXModelId,
      ttsVoiceDescription: ttsVoiceDescription,
      ttsPresetSpeaker: ttsPresetSpeaker,
      ttsEmotionPrompt: ttsEmotionPrompt,
      ttsReferenceAudioPath: ttsReferenceAudioPath,
      ttsReferenceAudioBookmark: ttsReferenceAudioBookmark,
      ttsReferenceText: ttsReferenceText,
      ttsLanguage: ttsLanguage,
      leftPadMs: leftPadMs,
      rightPadMs: rightPadMs,
      splitBySentence: splitBySentence,
      splitBySilence: splitBySilence,
      splitThreshold: splitThreshold,
      maxCharsPerSegment: maxCharsPerSegment,
      filterSilent: filterSilent,
      fcpxmlEnabled: fcpxmlEnabled,
      fcpxmlProjectName: fcpxmlProjectName,
      fcpxmlFrameRate: fcpxmlFrameRate,
      fcpxmlIncludeSubtitles: fcpxmlIncludeSubtitles,
      fcpxmlIsResolveCompatible: fcpxmlIsResolveCompatible,
      fcpxmlSpeed: fcpxmlSpeed,
      exportMode: exportMode,
      videoExportEnabled: videoExportEnabled,
      videoExportFormat: videoExportFormat,
      videoExportBurnInSubtitles: videoExportBurnInSubtitles,
      keepPunctuationOnExport: keepPunctuationOnExport,
      videoExportQuality: videoExportQuality,
      audioExportEnabled: audioExportEnabled,
      audioExportFormat: audioExportFormat,
      audioDubbingEnabled: audioDubbingEnabled,
      dubbingVoiceReferenceMode: dubbingVoiceReferenceMode,
      effectExtractHighlights: effectExtractHighlights,
      effectEnableScaling: effectEnableScaling,
      effectScaleMultiplier: effectScaleMultiplier,
      effectEnableZoom: effectEnableZoom,
      effectZoomMultiplier: effectZoomMultiplier,
      effectFilterFillerWords: effectFilterFillerWords,
      effectFillerWords: effectFillerWords,
      translationPlacement: translationPlacement,
      translationSourceLanguage: translationSourceLanguage,
      translationTargetLanguage: translationTargetLanguage,
      subtitleStyles: subtitleStyles,
      subtitleExportFormats: subtitleExportFormats,
      aiProviderKeys: aiProviderKeys,
      selectedAIProvider: selectedAIProvider,
      aiEnabled: aiEnabled,
      aiOpenAIEndpoint: aiOpenAIEndpoint,
      aiDefaultCorrectionPrompt: aiDefaultCorrectionPrompt,
      aiDefaultEnhancePrompt: aiDefaultEnhancePrompt,
      aiProviderModels: aiProviderModels,
      aiIncludeClipboardContext: aiIncludeClipboardContext,
      aiIncludeWindowContext: aiIncludeWindowContext,
      voiceToTextUsageTotalDuration: voiceToTextUsageTotalDuration,
      voiceToTextUsageSessionCount: voiceToTextUsageSessionCount,
      voiceToTextUsageTotalCharacters: voiceToTextUsageTotalCharacters,
      voiceToTextUsageTotalWords: voiceToTextUsageTotalWords
    )
  }

  func applySnapshot(_ snap: Snapshot) {
    transcriberType = snap.transcriberType
    modelVariant = snap.modelVariant
    language = snap.language
    useHuggingFaceMirror = snap.useHuggingFaceMirror
    // Voice To Text now follows the active ASR model used by AI Cut / Models page.
    voiceToTextTranscriberType = snap.transcriberType
    voiceToTextModelVariant = snap.modelVariant
    voiceToTextLanguage = snap.voiceToTextLanguage
    voiceToTextDictationAIEnhanceEnabled = snap.voiceToTextDictationAIEnhanceEnabled
    voiceToTextAssistantAIEnhanceEnabled = snap.voiceToTextAssistantAIEnhanceEnabled
    voiceToTextAssistantIncludeClipboardContext =
      snap.voiceToTextAssistantIncludeClipboardContext
    voiceToTextAssistantIncludeWindowContext =
      snap.voiceToTextAssistantIncludeWindowContext
    voiceToTextCustomDictionary = AppConfiguration.normalizeDictionaryEntries(
      snap.voiceToTextCustomDictionary)
    alignModelVariant = snap.alignModelVariant
    vadModelVariant = snap.vadModelVariant
    modelCleanupTimeoutSeconds = snap.modelCleanupTimeoutSeconds
    asrIdleTimeoutSeconds = snap.asrIdleTimeoutSeconds
    ttsEngine = snap.ttsEngine
    ttsVariantPreference = snap.ttsVariantPreference
    ttsSpeakingRate = snap.ttsSpeakingRate
    ttsMLXModelId = snap.ttsMLXModelId
    ttsVoiceDescription = snap.ttsVoiceDescription
    ttsPresetSpeaker = snap.ttsPresetSpeaker
    ttsEmotionPrompt = snap.ttsEmotionPrompt
    ttsReferenceAudioPath = snap.ttsReferenceAudioPath
    ttsReferenceAudioBookmark = snap.ttsReferenceAudioBookmark
    ttsReferenceText = snap.ttsReferenceText
    ttsLanguage = snap.ttsLanguage
    leftPadMs = snap.leftPadMs
    rightPadMs = snap.rightPadMs
    splitBySentence = snap.splitBySentence
    splitBySilence = snap.splitBySilence
    splitThreshold = snap.splitThreshold
    maxCharsPerSegment = snap.maxCharsPerSegment
    filterSilent = snap.filterSilent
    fcpxmlEnabled = snap.fcpxmlEnabled
    fcpxmlProjectName = snap.fcpxmlProjectName
    fcpxmlFrameRate = snap.fcpxmlFrameRate
    fcpxmlIncludeSubtitles = snap.fcpxmlIncludeSubtitles
    fcpxmlIsResolveCompatible = snap.fcpxmlIsResolveCompatible
    fcpxmlSpeed = snap.fcpxmlSpeed
    exportMode = snap.exportMode
    videoExportEnabled = snap.videoExportEnabled
    videoExportFormat = snap.videoExportFormat
    videoExportBurnInSubtitles = snap.videoExportBurnInSubtitles
    keepPunctuationOnExport = snap.keepPunctuationOnExport ?? true
    videoExportQuality = snap.videoExportQuality
    audioExportEnabled = snap.audioExportEnabled
    audioExportFormat = snap.audioExportFormat
    audioDubbingEnabled = snap.audioDubbingEnabled
    dubbingVoiceReferenceMode = snap.dubbingVoiceReferenceMode
    effectExtractHighlights = snap.effectExtractHighlights
    effectEnableScaling = snap.effectEnableScaling
    effectScaleMultiplier = snap.effectScaleMultiplier
    effectEnableZoom = snap.effectEnableZoom
    effectZoomMultiplier = snap.effectZoomMultiplier
    effectFilterFillerWords = snap.effectFilterFillerWords
    effectFillerWords = snap.effectFillerWords
    translationPlacement = snap.translationPlacement
    translationSourceLanguage = snap.translationSourceLanguage
    translationTargetLanguage = snap.translationTargetLanguage
    subtitleStyles = snap.subtitleStyles
    subtitleExportFormats = snap.subtitleExportFormats
    aiProviderKeys = snap.aiProviderKeys
    selectedAIProvider = snap.selectedAIProvider
    aiEnabled = snap.aiEnabled
    aiOpenAIEndpoint = snap.aiOpenAIEndpoint
    aiDefaultCorrectionPrompt = snap.aiDefaultCorrectionPrompt
    aiDefaultEnhancePrompt = snap.aiDefaultEnhancePrompt
    aiProviderModels = snap.aiProviderModels
    aiIncludeClipboardContext = snap.aiIncludeClipboardContext
    aiIncludeWindowContext = snap.aiIncludeWindowContext
    voiceToTextUsageTotalDuration = snap.voiceToTextUsageTotalDuration
    voiceToTextUsageSessionCount = snap.voiceToTextUsageSessionCount
    voiceToTextUsageTotalCharacters = snap.voiceToTextUsageTotalCharacters
    voiceToTextUsageTotalWords = snap.voiceToTextUsageTotalWords

    if let selectedAlign = alignModelVariant,
      !ModelVariant.alignerModels.contains(selectedAlign)
    {
      alignModelVariant = ModelVariant.alignerModels.first
    }

    normalizeModelSelections()
  }

  func resetToDefaults() {
    applySnapshot(Self.defaultSnapshot)
  }
}

// MARK: - Voice To Text Dictionary Helpers

extension AppConfiguration {
  nonisolated static func normalizeDictionaryEntries(_ entries: [String]) -> [String] {
    var seen: Set<String> = []
    var normalized: [String] = []
    for entry in entries {
      let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .lowercased()
      if seen.insert(key).inserted {
        normalized.append(trimmed)
      }
    }
    return normalized
  }

  var dictionaryContextText: String? {
    let entries = voiceToTextCustomDictionary
    guard !entries.isEmpty else { return nil }
    return entries.joined(separator: "\n")
  }

  func replaceDictionaryEntries(with entries: [String]) {
    let normalized = Self.normalizeDictionaryEntries(entries)
    guard normalized != voiceToTextCustomDictionary else { return }
    voiceToTextCustomDictionary = normalized
  }

  func appendDictionaryEntries(_ entries: [String]) {
    guard !entries.isEmpty else { return }
    replaceDictionaryEntries(with: voiceToTextCustomDictionary + entries)
  }

  func addDictionaryEntry(_ entry: String) {
    appendDictionaryEntries([entry])
  }

  func removeDictionaryEntry(_ entry: String) {
    guard !voiceToTextCustomDictionary.isEmpty else { return }
    let lowered = entry.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .lowercased()
    let filtered = voiceToTextCustomDictionary.filter { existing in
      existing.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .lowercased() != lowered
    }
    guard filtered != voiceToTextCustomDictionary else { return }
    voiceToTextCustomDictionary = filtered
  }

  func clearDictionaryEntries() {
    guard !voiceToTextCustomDictionary.isEmpty else { return }
    voiceToTextCustomDictionary = []
  }
}

// MARK: - FCPXML Helpers

extension AppConfiguration {
  func makeFCPXMLProjectName(
    additionalComponents: [String] = [],
    date: Date = Date()
  ) -> String {
    var parts: [String] = []

    let prefix = Self.sanitizeFCPXMLComponent(fcpxmlProjectName)
    if !prefix.isEmpty {
      parts.append(prefix)
    }

    for component in additionalComponents {
      let sanitized = Self.sanitizeFCPXMLComponent(component)
      if !sanitized.isEmpty {
        parts.append(sanitized)
      }
    }

    let dateString = Self.fcpxmlDateFormatter.string(from: date)
    parts.append(dateString)

    return parts.joined(separator: "_")
  }

  private static let fcpxmlDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  private static func sanitizeFCPXMLComponent(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>")
      .union(.newlines)
    let parts = trimmed.components(separatedBy: invalidCharacters).filter { !$0.isEmpty }
    let sanitized = parts.joined(separator: "_")
    let collapsed = sanitized.replacingOccurrences(of: " ", with: "_")
    return collapsed.replacingOccurrences(of: "__", with: "_")
  }
}
