import Foundation

import CliptateCore
import SwiftUI

// MARK: - ConfigPreset Models
struct ConfigPreset: Identifiable, Codable, Equatable {
  struct Payload: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
      case analyticsCollectionEnabled
      case transcriberType
      case modelVariant
      case language
      case leftPadMs
      case rightPadMs
      case splitBySentence
      case maxCharsPerSegment
      case filterSilent
      case fcpxmlProjectName
      case fcpxmlEnabled
      case fcpxmlFrameRate
      case fcpxmlIncludeSubtitles
      case fcpxmlIsResolveCompatible
      case fcpxmlSpeed
      case exportMode
      case legacyFCPXMLExportMode = "fcpxmlExportMode"
      case videoExportEnabled
      case videoExportFormat
      case videoExportBurnInSubtitles
      case keepPunctuationOnExport
      case videoExportQuality
      case audioExportEnabled
      case audioExportFormat
      case effectExtractHighlights
      case effectEnableScaling
      case effectScaleMultiplier
      case effectEnableZoom
      case effectZoomMultiplier
      case effectFilterFillerWords
      case effectFillerWords
      case translationPlacement
      case translationTargetLanguage
      case subtitleStyles
      case subtitleExportFormats
      case aiProviderKeys
      case selectedAIProvider
      case aiEnabled
      case aiOpenAIEndpoint
      case aiDefaultCorrectionPrompt
      case aiDefaultEnhancePrompt
      case aiProviderModels
      case ttsEngine
      case ttsVariantPreference
      case ttsSpeakingRate
      case micIndicatorStyle
      case voiceToTextCustomDictionary
    }

    var analyticsCollectionEnabled: Bool?
    var transcriberType: TranscriberType
    var modelVariant: ModelVariant
    var language: Language
    var leftPadMs: Int
    var rightPadMs: Int
    var splitBySentence: Bool
    var maxCharsPerSegment: Int
    var filterSilent: Bool
    var ttsEngine: TTSEngine
    var ttsVariantPreference: TTSVariantPreference
    var ttsSpeakingRate: Double
    var fcpxmlProjectName: String
    var fcpxmlEnabled: Bool
    var fcpxmlFrameRate: Double
    var fcpxmlIncludeSubtitles: Bool
    var fcpxmlIsResolveCompatible: Bool
    var fcpxmlSpeed: Double
    var exportMode: ExportMode
    var videoExportEnabled: Bool
    var videoExportFormat: VideoExportFormat
    var videoExportBurnInSubtitles: Bool
    var keepPunctuationOnExport: Bool
    var videoExportQuality: VideoExportQuality
    var audioExportEnabled: Bool
    var audioExportFormat: AudioExportFormat
    var effectExtractHighlights: Bool
    var effectEnableScaling: Bool
    var effectScaleMultiplier: Double
    var effectEnableZoom: Bool
    var effectZoomMultiplier: Double
    var effectFilterFillerWords: Bool
    var effectFillerWords: [String]
    var translationPlacement: SubtitleTranslationPlacement
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
    var micIndicatorStyle: MicIndicatorStyle
    var voiceToTextCustomDictionary: [String]

    init(
      analyticsCollectionEnabled: Bool? = nil,
      transcriberType: TranscriberType,
      modelVariant: ModelVariant,
      language: Language,
      leftPadMs: Int,
      rightPadMs: Int,
      splitBySentence: Bool,
      maxCharsPerSegment: Int,
      filterSilent: Bool,
      ttsEngine: TTSEngine,
      ttsVariantPreference: TTSVariantPreference,
      ttsSpeakingRate: Double,
      fcpxmlProjectName: String,
      fcpxmlEnabled: Bool,
      fcpxmlFrameRate: Double,
      fcpxmlIncludeSubtitles: Bool,
      fcpxmlIsResolveCompatible: Bool,
      fcpxmlSpeed: Double = 1.0,
      exportMode: ExportMode,
      videoExportEnabled: Bool,
      videoExportFormat: VideoExportFormat,
      videoExportBurnInSubtitles: Bool,
      keepPunctuationOnExport: Bool = true,
      videoExportQuality: VideoExportQuality = .original,
      audioExportEnabled: Bool = false,
      audioExportFormat: AudioExportFormat = .m4a,
      effectExtractHighlights: Bool,
      effectEnableScaling: Bool,
      effectScaleMultiplier: Double,
      effectEnableZoom: Bool,
      effectZoomMultiplier: Double,
      effectFilterFillerWords: Bool,
      effectFillerWords: [String],
      translationPlacement: SubtitleTranslationPlacement,
      translationTargetLanguage: Language,
      subtitleStyles: SubtitleStylesConfiguration,
      subtitleExportFormats: Set<SubtitleExportFormat>,
      aiProviderKeys: [AIProvider: String],
      selectedAIProvider: AIProvider,
      aiEnabled: Bool,
      aiOpenAIEndpoint: String = "https://api.openai.com/v1",
      aiDefaultCorrectionPrompt: String = "",
      aiDefaultEnhancePrompt: String = "",
      aiProviderModels: [AIProvider: String] = AIProvider.defaultModelMap,
      micIndicatorStyle: MicIndicatorStyle = .pulseBlue,
      voiceToTextCustomDictionary: [String] = []
    ) {
      self.analyticsCollectionEnabled = analyticsCollectionEnabled
      self.transcriberType = transcriberType
      self.modelVariant = modelVariant
      self.language = language
      self.leftPadMs = leftPadMs
      self.rightPadMs = rightPadMs
      self.splitBySentence = splitBySentence
      self.maxCharsPerSegment = maxCharsPerSegment
      self.filterSilent = filterSilent
      self.ttsEngine = ttsEngine
      self.ttsVariantPreference = ttsVariantPreference
      self.ttsSpeakingRate = ttsSpeakingRate
      self.fcpxmlProjectName = fcpxmlProjectName
      self.fcpxmlEnabled = fcpxmlEnabled
      self.fcpxmlFrameRate = fcpxmlFrameRate
      self.fcpxmlIncludeSubtitles = fcpxmlIncludeSubtitles
      self.fcpxmlIsResolveCompatible = fcpxmlIsResolveCompatible
      self.fcpxmlSpeed = fcpxmlSpeed
      self.exportMode = exportMode
      self.videoExportEnabled = videoExportEnabled
      self.videoExportFormat = videoExportFormat
      self.videoExportBurnInSubtitles = videoExportBurnInSubtitles
      self.keepPunctuationOnExport = keepPunctuationOnExport
      self.videoExportQuality = videoExportQuality
      self.audioExportEnabled = audioExportEnabled
      self.audioExportFormat = audioExportFormat
      self.effectExtractHighlights = effectExtractHighlights
      self.effectEnableScaling = effectEnableScaling
      self.effectScaleMultiplier = effectScaleMultiplier
      self.effectEnableZoom = effectEnableZoom
      self.effectZoomMultiplier = effectZoomMultiplier
      self.effectFilterFillerWords = effectFilterFillerWords
      self.effectFillerWords = SegmentEffectConfiguration.normalizeFillerWords(effectFillerWords)
      self.translationPlacement = translationPlacement
      self.translationTargetLanguage = translationTargetLanguage
      self.subtitleStyles = subtitleStyles
      self.subtitleExportFormats = subtitleExportFormats
      self.aiProviderKeys = aiProviderKeys
      self.selectedAIProvider = selectedAIProvider
      self.aiEnabled = aiEnabled
      self.aiOpenAIEndpoint = aiOpenAIEndpoint
      self.aiDefaultCorrectionPrompt = aiDefaultCorrectionPrompt
      self.aiDefaultEnhancePrompt = aiDefaultEnhancePrompt
      self.aiProviderModels = aiProviderModels
      self.micIndicatorStyle = micIndicatorStyle
      self.voiceToTextCustomDictionary =
        AppConfiguration.normalizeDictionaryEntries(voiceToTextCustomDictionary)
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      analyticsCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .analyticsCollectionEnabled)
      transcriberType = try container.decode(TranscriberType.self, forKey: .transcriberType)
      modelVariant = try container.decode(ModelVariant.self, forKey: .modelVariant)
      language = try container.decode(Language.self, forKey: .language)
      leftPadMs = try container.decode(Int.self, forKey: .leftPadMs)
      rightPadMs = try container.decode(Int.self, forKey: .rightPadMs)
      splitBySentence = try container.decodeIfPresent(Bool.self, forKey: .splitBySentence) ?? false
      maxCharsPerSegment = try container.decode(Int.self, forKey: .maxCharsPerSegment)
      filterSilent = try container.decode(Bool.self, forKey: .filterSilent)
      ttsEngine = try container.decodeIfPresent(TTSEngine.self, forKey: .ttsEngine) ?? .qwen3TTS
      ttsVariantPreference =
        try container.decodeIfPresent(
          TTSVariantPreference.self,
          forKey: .ttsVariantPreference
        ) ?? .automatic
      ttsSpeakingRate = try container.decodeIfPresent(Double.self, forKey: .ttsSpeakingRate) ?? 1.0
      fcpxmlProjectName = try container.decode(String.self, forKey: .fcpxmlProjectName)
      fcpxmlEnabled = try container.decodeIfPresent(Bool.self, forKey: .fcpxmlEnabled) ?? true
      fcpxmlFrameRate = try container.decode(Double.self, forKey: .fcpxmlFrameRate)
      fcpxmlIncludeSubtitles = try container.decode(Bool.self, forKey: .fcpxmlIncludeSubtitles)
      fcpxmlIsResolveCompatible = try container.decode(
        Bool.self, forKey: .fcpxmlIsResolveCompatible)
      fcpxmlSpeed = try container.decodeIfPresent(Double.self, forKey: .fcpxmlSpeed) ?? 1.0
      if let newMode = try container.decodeIfPresent(ExportMode.self, forKey: .exportMode) {
        exportMode = newMode
      } else if let legacy = try container.decodeIfPresent(
        ExportMode.self,
        forKey: .legacyFCPXMLExportMode
      ) {
        exportMode = legacy
      } else {
        exportMode = .merge
      }
      videoExportEnabled =
        try container.decodeIfPresent(Bool.self, forKey: .videoExportEnabled) ?? false
      videoExportFormat =
        try container.decodeIfPresent(VideoExportFormat.self, forKey: .videoExportFormat) ?? .mp4
      videoExportBurnInSubtitles =
        try container.decodeIfPresent(Bool.self, forKey: .videoExportBurnInSubtitles) ?? true
      keepPunctuationOnExport =
        try container.decodeIfPresent(Bool.self, forKey: .keepPunctuationOnExport) ?? true
      videoExportQuality =
        try container.decodeIfPresent(VideoExportQuality.self, forKey: .videoExportQuality)
        ?? .original
      audioExportEnabled =
        try container.decodeIfPresent(Bool.self, forKey: .audioExportEnabled) ?? false
      audioExportFormat =
        try container.decodeIfPresent(AudioExportFormat.self, forKey: .audioExportFormat) ?? .m4a
      effectExtractHighlights =
        try container.decodeIfPresent(Bool.self, forKey: .effectExtractHighlights) ?? true
      effectEnableScaling =
        try container.decodeIfPresent(Bool.self, forKey: .effectEnableScaling) ?? false
      effectScaleMultiplier =
        try container.decodeIfPresent(Double.self, forKey: .effectScaleMultiplier) ?? 1.2
      effectEnableZoom =
        try container.decodeIfPresent(Bool.self, forKey: .effectEnableZoom) ?? false
      effectZoomMultiplier =
        try container.decodeIfPresent(Double.self, forKey: .effectZoomMultiplier) ?? 1.3
      effectFilterFillerWords =
        try container.decodeIfPresent(Bool.self, forKey: .effectFilterFillerWords) ?? true
      let rawFillerWords =
        try container.decodeIfPresent([String].self, forKey: .effectFillerWords)
        ?? SegmentEffectConfiguration.defaultFillerWords
      effectFillerWords = SegmentEffectConfiguration.normalizeFillerWords(rawFillerWords)
      translationPlacement =
        try container.decodeIfPresent(
          SubtitleTranslationPlacement.self, forKey: .translationPlacement) ?? .below
      translationTargetLanguage =
        try container.decodeIfPresent(Language.self, forKey: .translationTargetLanguage) ?? .chinese
      subtitleStyles =
        try container.decodeIfPresent(SubtitleStylesConfiguration.self, forKey: .subtitleStyles)
        ?? defaultSubtitleStyles
      subtitleExportFormats =
        try container.decodeIfPresent(
          Set<SubtitleExportFormat>.self, forKey: .subtitleExportFormats)
        ?? [.srt, .ass]
      aiProviderKeys =
        try container.decodeIfPresent([AIProvider: String].self, forKey: .aiProviderKeys) ?? [:]
      selectedAIProvider =
        try container.decodeIfPresent(AIProvider.self, forKey: .selectedAIProvider) ?? .gemini
      aiEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
      aiOpenAIEndpoint =
        try container.decodeIfPresent(String.self, forKey: .aiOpenAIEndpoint)
        ?? "https://api.openai.com/v1"
      aiDefaultCorrectionPrompt =
        try container.decodeIfPresent(String.self, forKey: .aiDefaultCorrectionPrompt) ?? ""
      aiDefaultEnhancePrompt =
        try container.decodeIfPresent(String.self, forKey: .aiDefaultEnhancePrompt) ?? ""
      aiProviderModels =
        try container.decodeIfPresent([AIProvider: String].self, forKey: .aiProviderModels)
        ?? AIProvider.defaultModelMap
      micIndicatorStyle = try container.decodeIfPresent(MicIndicatorStyle.self, forKey: .micIndicatorStyle) ?? .pulseBlue
      voiceToTextCustomDictionary = AppConfiguration.normalizeDictionaryEntries(
        try container.decodeIfPresent([String].self, forKey: .voiceToTextCustomDictionary)
          ?? []
      )
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(analyticsCollectionEnabled, forKey: .analyticsCollectionEnabled)
      try container.encode(transcriberType, forKey: .transcriberType)
      try container.encode(modelVariant, forKey: .modelVariant)
      try container.encode(language, forKey: .language)
      try container.encode(leftPadMs, forKey: .leftPadMs)
      try container.encode(rightPadMs, forKey: .rightPadMs)
      try container.encode(splitBySentence, forKey: .splitBySentence)
      try container.encode(maxCharsPerSegment, forKey: .maxCharsPerSegment)
      try container.encode(filterSilent, forKey: .filterSilent)
      try container.encode(ttsEngine, forKey: .ttsEngine)
      try container.encode(ttsVariantPreference, forKey: .ttsVariantPreference)
      try container.encode(ttsSpeakingRate, forKey: .ttsSpeakingRate)
      try container.encode(fcpxmlProjectName, forKey: .fcpxmlProjectName)
      try container.encode(fcpxmlEnabled, forKey: .fcpxmlEnabled)
      try container.encode(fcpxmlFrameRate, forKey: .fcpxmlFrameRate)
      try container.encode(fcpxmlIncludeSubtitles, forKey: .fcpxmlIncludeSubtitles)
      try container.encode(fcpxmlIsResolveCompatible, forKey: .fcpxmlIsResolveCompatible)
      try container.encode(fcpxmlSpeed, forKey: .fcpxmlSpeed)
      try container.encode(exportMode, forKey: .exportMode)
      try container.encode(videoExportEnabled, forKey: .videoExportEnabled)
      try container.encode(videoExportFormat, forKey: .videoExportFormat)
      try container.encode(videoExportBurnInSubtitles, forKey: .videoExportBurnInSubtitles)
      try container.encode(keepPunctuationOnExport, forKey: .keepPunctuationOnExport)
      try container.encode(videoExportQuality, forKey: .videoExportQuality)
      try container.encode(audioExportEnabled, forKey: .audioExportEnabled)
      try container.encode(audioExportFormat, forKey: .audioExportFormat)
      try container.encode(effectExtractHighlights, forKey: .effectExtractHighlights)
      try container.encode(effectEnableScaling, forKey: .effectEnableScaling)
      try container.encode(effectScaleMultiplier, forKey: .effectScaleMultiplier)
      try container.encode(effectEnableZoom, forKey: .effectEnableZoom)
      try container.encode(effectZoomMultiplier, forKey: .effectZoomMultiplier)
      try container.encode(effectFilterFillerWords, forKey: .effectFilterFillerWords)
      try container.encode(
        SegmentEffectConfiguration.normalizeFillerWords(effectFillerWords),
        forKey: .effectFillerWords)
      try container.encode(translationPlacement, forKey: .translationPlacement)
      try container.encode(translationTargetLanguage, forKey: .translationTargetLanguage)
      try container.encode(subtitleStyles, forKey: .subtitleStyles)
      try container.encode(subtitleExportFormats, forKey: .subtitleExportFormats)
      try container.encode(aiProviderKeys, forKey: .aiProviderKeys)
      try container.encode(selectedAIProvider, forKey: .selectedAIProvider)
      try container.encode(aiEnabled, forKey: .aiEnabled)
      try container.encode(aiOpenAIEndpoint, forKey: .aiOpenAIEndpoint)
      try container.encode(aiDefaultCorrectionPrompt, forKey: .aiDefaultCorrectionPrompt)
      try container.encode(aiDefaultEnhancePrompt, forKey: .aiDefaultEnhancePrompt)
      try container.encode(aiProviderModels, forKey: .aiProviderModels)
      try container.encode(micIndicatorStyle, forKey: .micIndicatorStyle)
      try container.encode(voiceToTextCustomDictionary, forKey: .voiceToTextCustomDictionary)
    }
  }

  let id: UUID
  var name: String
  var createdAt: Date
  var updatedAt: Date
  var isDefault: Bool
  var payload: Payload
}

// Root persistence container
private struct ConfigPresetFile: Codable {
  var version: Int
  var presets: [ConfigPreset]
}

enum ConfigPresetError: Error, LocalizedError {
  case notFound
  case ioFailure(String)
  case encodeFailure
  case decodeFailure

  var errorDescription: String? {
    switch self {
    case .notFound: return "Preset not found"
    case .ioFailure(let msg): return "IO failure: \(msg)"
    case .encodeFailure: return "Failed to encode presets"
    case .decodeFailure: return "Failed to decode presets"
    }
  }
}

// MARK: - Store Protocol
@MainActor
protocol ConfigPresetStoreProtocol: AnyObject {
  var presets: [ConfigPreset] { get }
  func load() throws
  func save() throws
  @discardableResult func create(from config: AppConfiguration, name: String, makeDefault: Bool)
    throws -> ConfigPreset
  func update(id: UUID, mutate: (inout ConfigPreset) -> Void) throws
  func delete(id: UUID) throws
  func apply(id: UUID, to config: AppConfiguration) throws
  func setDefault(id: UUID) throws
  func payload(from config: AppConfiguration) -> ConfigPreset.Payload
  func applyPayload(_ payload: ConfigPreset.Payload, to config: AppConfiguration)
}

// MARK: - Store Implementation
@MainActor
final class ConfigPresetStore: ObservableObject, ConfigPresetStoreProtocol {
  static let shared = ConfigPresetStore()

  @Published private(set) var presets: [ConfigPreset] = []

  private let fileName = "presets.json"
  private let fileVersion = 2
  private let queue = DispatchQueue(label: "config-preset-store-io", qos: .utility)

  private init() {}

  // MARK: - Paths
  private func fileURL() throws -> URL {
    let fm = FileManager.default

    #if os(macOS)
      if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let dir = appSupport.appendingPathComponent(AppIdentity.current.dataDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
          try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
      }
    #endif
    // Fallback to documents directory
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw ConfigPresetError.ioFailure("No writable directory")
    }
    let directory = AppIdentity.current == .development
      ? docs.appendingPathComponent(AppIdentity.current.dataDirectoryName, isDirectory: true) : docs
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(fileName)
  }

  // MARK: - Public API
  func load() throws {
    let url = try fileURL()
    if !FileManager.default.fileExists(atPath: url.path) {
      self.presets = []
      return
    }
    let data: Data
    do { data = try Data(contentsOf: url) } catch {
      throw ConfigPresetError.ioFailure(error.localizedDescription)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      let container = try decoder.decode(ConfigPresetFile.self, from: data)
      // Basic version check (can add migration later)
      var loadedPresets = container.presets
      if container.version < 2 {
        for index in loadedPresets.indices {
          loadedPresets[index].payload.keepPunctuationOnExport = true
        }
      }
      self.presets = loadedPresets
      enforceSingleDefault()
      if container.version < fileVersion {
        try? save()
      }
    } catch {
      throw ConfigPresetError.decodeFailure
    }
  }

  func save() throws {
    let url = try fileURL()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let container = ConfigPresetFile(version: fileVersion, presets: presets)
    do {
      let data = try encoder.encode(container)
      // Atomic write
      let tmp = url.appendingPathExtension("tmp")
      try data.write(to: tmp, options: .atomic)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      try FileManager.default.moveItem(at: tmp, to: url)
    } catch {
      throw ConfigPresetError.encodeFailure
    }
  }

  @discardableResult
  func create(from config: AppConfiguration, name: String, makeDefault: Bool) throws -> ConfigPreset
  {
    var finalName = sanitizedName(name)
    if finalName.isEmpty { finalName = defaultGeneratedName() }
    finalName = uniqueName(basename: finalName)
    let now = Date()
    let preset = ConfigPreset(
      id: UUID(), name: finalName, createdAt: now, updatedAt: now, isDefault: makeDefault,
      payload: payload(from: config))
    if makeDefault { clearDefaultFlag() }
    presets.append(preset)
    enforceSingleDefault()
    try save()
    return preset
  }

  func update(id: UUID, mutate: (inout ConfigPreset) -> Void) throws {
    guard let idx = presets.firstIndex(where: { $0.id == id }) else {
      throw ConfigPresetError.notFound
    }
    var copy = presets[idx]
    mutate(&copy)
    copy.updatedAt = Date()
    // Name uniqueness if changed
    if copy.name != presets[idx].name {
      copy.name = uniqueName(basename: sanitizedName(copy.name))
    }
    presets[idx] = copy
    enforceSingleDefault()
    try save()
  }

  func delete(id: UUID) throws {
    guard let idx = presets.firstIndex(where: { $0.id == id }) else {
      throw ConfigPresetError.notFound
    }
    let wasDefault = presets[idx].isDefault
    presets.remove(at: idx)
    if wasDefault, let first = presets.first {
      // Promote first as default
      if !presets.contains(where: { $0.isDefault }) {
        if let idx2 = presets.firstIndex(where: { $0.id == first.id }) {
          presets[idx2].isDefault = true
        }
      }
    }
    enforceSingleDefault()
    try save()
  }

  func apply(id: UUID, to config: AppConfiguration) throws {
    guard let preset = presets.first(where: { $0.id == id }) else {
      throw ConfigPresetError.notFound
    }
    applyPayload(preset.payload, to: config)
  }

  func setDefault(id: UUID) throws {
    guard let idx = presets.firstIndex(where: { $0.id == id }) else {
      throw ConfigPresetError.notFound
    }
    clearDefaultFlag()
    presets[idx].isDefault = true
    try save()
  }

  // MARK: - Payload helpers
  func payload(from config: AppConfiguration) -> ConfigPreset.Payload {
    ConfigPreset.Payload(
      analyticsCollectionEnabled: config.analyticsCollectionEnabled,
      transcriberType: config.transcriberType,
      modelVariant: config.modelVariant,
      language: config.language,
      leftPadMs: config.leftPadMs,
      rightPadMs: config.rightPadMs,
      splitBySentence: config.splitBySentence,
      maxCharsPerSegment: config.maxCharsPerSegment,
      filterSilent: config.filterSilent,
      ttsEngine: config.ttsEngine,
      ttsVariantPreference: config.ttsVariantPreference,
      ttsSpeakingRate: config.ttsSpeakingRate,
      fcpxmlProjectName: config.fcpxmlProjectName,
      fcpxmlEnabled: config.fcpxmlEnabled,
      fcpxmlFrameRate: config.fcpxmlFrameRate,
      fcpxmlIncludeSubtitles: config.fcpxmlIncludeSubtitles,
      fcpxmlIsResolveCompatible: config.fcpxmlIsResolveCompatible,
      exportMode: config.exportMode,
      videoExportEnabled: config.videoExportEnabled,
      videoExportFormat: config.videoExportFormat,
      videoExportBurnInSubtitles: config.videoExportBurnInSubtitles,
      keepPunctuationOnExport: config.keepPunctuationOnExport,
      videoExportQuality: config.videoExportQuality,
      audioExportEnabled: config.audioExportEnabled,
      audioExportFormat: config.audioExportFormat,
      effectExtractHighlights: config.effectExtractHighlights,
      effectEnableScaling: config.effectEnableScaling,
      effectScaleMultiplier: config.effectScaleMultiplier,
      effectEnableZoom: config.effectEnableZoom,
      effectZoomMultiplier: config.effectZoomMultiplier,
      effectFilterFillerWords: config.effectFilterFillerWords,
      effectFillerWords: config.effectFillerWords,
      translationPlacement: config.translationPlacement,
      translationTargetLanguage: config.translationTargetLanguage,
      subtitleStyles: config.subtitleStyles,
      subtitleExportFormats: config.subtitleExportFormats,
      aiProviderKeys: config.aiProviderKeys,
      selectedAIProvider: config.selectedAIProvider,
      aiEnabled: config.aiEnabled,
      aiOpenAIEndpoint: config.aiOpenAIEndpoint,
      aiDefaultCorrectionPrompt: config.aiDefaultCorrectionPrompt,
      aiDefaultEnhancePrompt: config.aiDefaultEnhancePrompt,
      aiProviderModels: config.aiProviderModels,
      micIndicatorStyle: config.micIndicatorStyle,
      voiceToTextCustomDictionary: config.voiceToTextCustomDictionary
    )
  }

  func applyPayload(_ payload: ConfigPreset.Payload, to config: AppConfiguration) {
    if let enabled = payload.analyticsCollectionEnabled {
      config.analyticsCollectionEnabled = enabled
    }
    config.transcriberType = payload.transcriberType
    config.modelVariant = payload.modelVariant
    config.language = payload.language
    config.leftPadMs = payload.leftPadMs
    config.rightPadMs = payload.rightPadMs
    config.splitBySentence = payload.splitBySentence
    config.maxCharsPerSegment = payload.maxCharsPerSegment
    config.filterSilent = payload.filterSilent
    config.ttsEngine = payload.ttsEngine
    config.ttsVariantPreference = payload.ttsVariantPreference
    config.ttsSpeakingRate = payload.ttsSpeakingRate
    config.fcpxmlProjectName = payload.fcpxmlProjectName
    config.fcpxmlEnabled = payload.fcpxmlEnabled
    config.fcpxmlFrameRate = payload.fcpxmlFrameRate
    config.fcpxmlIncludeSubtitles = payload.fcpxmlIncludeSubtitles
    config.fcpxmlIsResolveCompatible = payload.fcpxmlIsResolveCompatible
    config.exportMode = payload.exportMode
    config.videoExportEnabled = payload.videoExportEnabled
    config.videoExportFormat = payload.videoExportFormat
    config.videoExportBurnInSubtitles = payload.videoExportBurnInSubtitles
    config.keepPunctuationOnExport = payload.keepPunctuationOnExport
    config.videoExportQuality = payload.videoExportQuality
    config.audioExportEnabled = payload.audioExportEnabled
    config.audioExportFormat = payload.audioExportFormat
    config.effectExtractHighlights = payload.effectExtractHighlights
    config.effectEnableScaling = payload.effectEnableScaling
    config.effectScaleMultiplier = payload.effectScaleMultiplier
    config.effectEnableZoom = payload.effectEnableZoom
    config.effectZoomMultiplier = payload.effectZoomMultiplier
    config.effectFilterFillerWords = payload.effectFilterFillerWords
    config.effectFillerWords = payload.effectFillerWords
    config.translationPlacement = payload.translationPlacement
    config.translationTargetLanguage = payload.translationTargetLanguage
    config.subtitleStyles = payload.subtitleStyles
    config.subtitleExportFormats = payload.subtitleExportFormats
    config.aiProviderKeys = payload.aiProviderKeys
    config.selectedAIProvider = payload.selectedAIProvider
    config.aiEnabled = payload.aiEnabled
    config.aiOpenAIEndpoint = payload.aiOpenAIEndpoint
    config.aiDefaultCorrectionPrompt = payload.aiDefaultCorrectionPrompt
    config.aiDefaultEnhancePrompt = payload.aiDefaultEnhancePrompt
    config.aiProviderModels = payload.aiProviderModels
    config.micIndicatorStyle = payload.micIndicatorStyle
    config.replaceDictionaryEntries(with: payload.voiceToTextCustomDictionary)
  }

  /// Ensure there is at least one preset (and a default). If none exist, create one from current config.
  @discardableResult
  func ensureDefaultPreset(using config: AppConfiguration) throws -> ConfigPreset {
    if let existingDefault = presets.first(where: { $0.isDefault }) {
      return existingDefault
    }
    if let first = presets.first {  // No default flagged but have presets; mark first
      try update(id: first.id) { p in p.isDefault = true }
      return presets.first(where: { $0.id == first.id }) ?? first
    }
    // Create brand new default preset
    let created = try create(from: config, name: "Default", makeDefault: true)
    return created
  }

  // MARK: - Utilities
  private func sanitizedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func uniqueName(basename: String) -> String {
    if !presets.contains(where: { $0.name.caseInsensitiveCompare(basename) == .orderedSame }) {
      return basename
    }
    var i = 2
    while true {
      let candidate = "\(basename) (\(i))"
      if !presets.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
        return candidate
      }
      i += 1
    }
  }

  private func defaultGeneratedName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return "Preset \(formatter.string(from: Date()))"
  }

  private func clearDefaultFlag() {
    for idx in presets.indices { presets[idx].isDefault = false }
  }

  private func enforceSingleDefault() {
    let defaults = presets.enumerated().filter { $0.element.isDefault }
    if defaults.count > 1 {
      // Keep first, unset others
      for pair in defaults.dropFirst() { presets[pair.offset].isDefault = false }
    }
    if defaults.isEmpty, let first = presets.first {
      if let idx = presets.firstIndex(where: { $0.id == first.id }) {
        presets[idx].isDefault = true
      }
    }
  }
}
