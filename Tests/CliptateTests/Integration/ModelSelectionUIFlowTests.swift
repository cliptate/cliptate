import SwiftUI
import Testing

@testable import Cliptate

#if os(macOS)
  import AppKit
#endif

@Suite("Model selection UI integration flow")
@MainActor
struct ModelSelectionUIFlowTests {
  @Test("unsupported language falls back when model context changes")
  func languageSelectionFallsBackOnModelSwitch() async throws {
    let ttsLanguages = await ModelCacheManager.shared.filteredLanguages(
      for: .tts(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
      )
    )
    #expect(ttsLanguages.contains(.chinese))

    let asrLanguages = await ModelCacheManager.shared.filteredLanguages(
      for: .asr(type: .parakeet, model: .parakeetV2)
    )
    #expect(!asrLanguages.contains(.chinese))
    #expect(asrLanguages.first == .english)
  }

  @Test("compatible language is preserved across model context change")
  func compatibleLanguageIsPreservedOnModelSwitch() async throws {
    let ttsLanguages = await ModelCacheManager.shared.filteredLanguages(
      for: .tts(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
      )
    )
    #expect(ttsLanguages.contains(.english))

    let asrLanguages = await ModelCacheManager.shared.filteredLanguages(
      for: .asr(type: .parakeet, model: .parakeetV2)
    )
    #expect(asrLanguages.contains(.english))
  }

  @Test("fireRed appears in model selection engines")
  func fireRedEngineSelectionExists() throws {
    #expect(TranscriberType.allCases.contains(.fireRed))
    #expect(TranscriberType.fireRed.supportedModels == [.fireRedASR2])
    #expect(ModelsView.ASRProvider.allCases.contains(.fireRed))
    #expect(ModelsView.asrModels(for: .fireRed) == [.fireRedASR2])
    #expect(ModelsView.asrModels(for: .all).contains(.fireRedASR2))
  }

  @Test("cohere appears in model selection engines")
  func cohereEngineSelectionExists() throws {
    let cohereType = try #require(TranscriberType(rawValue: "cohere"))
    let cohereProvider = try #require(ModelsView.ASRProvider(rawValue: "cohere"))
    let expectedModels = [
      "cohere-transcribe-03-2026-mlx-fp16",
      "cohere-transcribe-03-2026-mlx-8bit",
      "cohere-transcribe-03-2026-mlx-4bit",
    ]

    #expect(TranscriberType.allCases.contains(cohereType))
    #expect(cohereType.supportedModels.map(\.rawValue) == expectedModels)
    #expect(ModelsView.ASRProvider.allCases.contains(cohereProvider))
    #expect(ModelsView.asrModels(for: cohereProvider).map(\.rawValue) == expectedModels)
    #expect(ModelsView.asrModels(for: .all).map(\.rawValue).contains(expectedModels[0]))
  }

  @Test("premium shortcuts expose locked models for the selected engine")
  func premiumShortcutsMatchLockedModels() throws {
    let parakeetStatuses: [ModelVariant: ModelDownloadStatus] = [
      .parakeetV2: .downloaded,
      .parakeetV3: .notDownloaded,
    ]
    let parakeetPermissions: [ModelVariant: ModelDownloadPermission] = [
      .parakeetV3: ModelDownloadPermission(
        model: .parakeetV3,
        isAllowed: false,
        reason: .requiresProSubscription
      )
    ]
    let parakeetShortcuts = ModelSelectionView.premiumShortcutModels(
      for: .parakeet,
      downloadStatuses: parakeetStatuses,
      permissions: parakeetPermissions
    )
    #expect(parakeetShortcuts == [ModelVariant.parakeetV3])

    let qwenStatuses: [ModelVariant: ModelDownloadStatus] = [
      .qwen3ASR: .downloaded,
      .qwen3ASR17B4bit: .notDownloaded,
      .qwen3ASR17B8bit: .notDownloaded,
      .qwen3ASR17Bbf16: .downloaded,
    ]
    let qwenPermissions: [ModelVariant: ModelDownloadPermission] = [
      .qwen3ASR17B4bit: ModelDownloadPermission(
        model: .qwen3ASR17B4bit,
        isAllowed: false,
        reason: .requiresProSubscription
      ),
      .qwen3ASR17B8bit: ModelDownloadPermission(
        model: .qwen3ASR17B8bit,
        isAllowed: false,
        reason: .requiresProSubscription
      ),
    ]
    let qwenShortcuts = ModelSelectionView.premiumShortcutModels(
      for: .qwen3,
      downloadStatuses: qwenStatuses,
      permissions: qwenPermissions
    )
    #expect(qwenShortcuts == [ModelVariant.qwen3ASR17B4bit, .qwen3ASR17B8bit])

    let fireRedStatuses: [ModelVariant: ModelDownloadStatus] = [
      .fireRedASR2: .notDownloaded
    ]
    let fireRedPermissions: [ModelVariant: ModelDownloadPermission] = [
      .fireRedASR2: ModelDownloadPermission(
        model: .fireRedASR2,
        isAllowed: false,
        reason: .requiresProSubscription
      )
    ]
    let fireRedShortcuts = ModelSelectionView.premiumShortcutModels(
      for: .fireRed,
      downloadStatuses: fireRedStatuses,
      permissions: fireRedPermissions
    )
    #expect(fireRedShortcuts == [ModelVariant.fireRedASR2])

    let cohereType = try #require(TranscriberType(rawValue: "cohere"))
    let cohereFP16 = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-fp16"))
    let cohere8Bit = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-8bit"))
    let cohereStatuses: [ModelVariant: ModelDownloadStatus] = [
      cohereFP16: .notDownloaded,
      cohere8Bit: .notDownloaded,
    ]
    let coherePermissions: [ModelVariant: ModelDownloadPermission] = [
      cohereFP16: ModelDownloadPermission(
        model: cohereFP16,
        isAllowed: false,
        reason: .requiresProSubscription
      ),
      cohere8Bit: ModelDownloadPermission(
        model: cohere8Bit,
        isAllowed: false,
        reason: .requiresProSubscription
      ),
    ]
    let cohereShortcuts = ModelSelectionView.premiumShortcutModels(
      for: cohereType,
      downloadStatuses: cohereStatuses,
      permissions: coherePermissions
    )
    #expect(cohereShortcuts == [cohereFP16, cohere8Bit])
  }

  @Test("models header demotes cache memory to secondary stat below downloaded and disk usage")
  func modelsHeaderKeepsCacheMemoryAsPrimaryStat() {
    let metrics = ModelsView.headerMetrics(
      downloadedCount: 6,
      totalDiskUsageMB: 4200,
      cacheMemoryMB: 1536
    )

    #expect(metrics.count == 3)
    #expect(metrics[0] == .init(title: "Downloaded", value: "6", emphasis: .primary))
    #expect(metrics[1] == .init(title: "Disk Usage", value: "4200 MB", emphasis: .primary))
    #expect(metrics[2] == .init(title: "Cache Memory", value: "1536 MB", emphasis: .secondary))
  }

  @Test("dense model rows keep one primary action and move file actions into overflow")
  func denseModelRowsPreferPrimaryPlusOverflow() {
    let presentation = ModelsView.denseRowPresentation(
      for: .qwen3ASR17B8bit,
      isDownloaded: true,
      progress: nil,
      permission: ModelDownloadPermission(
        model: .qwen3ASR17B8bit,
        isAllowed: true,
        reason: nil
      ),
      isDefaultSelection: false,
      isAlignSelection: false,
      isVADSelection: false
    )

    #expect(presentation.status == "Downloaded")
    #expect(presentation.metadata == ["800 MB", "52 supported languages"])
    #expect(presentation.primaryAction == .setActive)
    #expect(presentation.overflowActions == [.openFolder, .remove])
  }

  @Test("model catalog styling uses one shared accent while keeping semantic status colors")
  func modelCatalogStylingUsesSharedAccentAndSemanticStatuses() {
    let asr = ModelsView.categoryStyle(for: .asr)
    let align = ModelsView.categoryStyle(for: .align)
    let vad = ModelsView.categoryStyle(for: .vad)
    let tts = ModelsView.categoryStyle(for: .tts)

    #expect(asr.usesNeutralSurface)
    #expect(align.usesNeutralSurface)
    #expect(vad.usesNeutralSurface)
    #expect(tts.usesNeutralSurface)
    #expect(asr.accent == align.accent)
    #expect(asr.accent == vad.accent)
    #expect(asr.accent == tts.accent)

    #expect(ModelsView.statusStyle(for: .active).tone == .success)
    #expect(ModelsView.statusStyle(for: .downloaded).tone == .neutral)
    #expect(ModelsView.statusStyle(for: .pro).tone == .warning)
    #expect(ModelsView.statusStyle(for: .error).tone == .danger)
  }

  @Test("active row presentations use one shared active status across categories")
  func activeRowPresentationsUseSharedSemanticStatus() {
    let activeAlign = ModelsView.denseRowPresentation(
      for: .qwen3ForcedAligner,
      isDownloaded: true,
      progress: nil,
      permission: nil,
      isDefaultSelection: false,
      isAlignSelection: true,
      isVADSelection: false
    )
    let activeVAD = ModelsView.denseRowPresentation(
      for: .sileroVAD,
      isDownloaded: true,
      progress: nil,
      permission: nil,
      isDefaultSelection: false,
      isAlignSelection: false,
      isVADSelection: true
    )

    #expect(activeAlign.status == "Active")
    #expect(activeVAD.status == "Active")
  }

  @Test("tts catalog can narrow to downloaded models while keeping search")
  func ttsCatalogSupportsDownloadedOnlyBrowsing() {
    let downloaded = MLXTTSModelDefinition.availableModels[0]
    let notDownloaded = MLXTTSModelDefinition.availableModels[1]

    let results = ModelsView.filteredTTSModels(
      from: [downloaded, notDownloaded],
      searchText: "4-bit",
      showDownloadedOnly: true,
      downloadedModelVariants: [downloaded.modelVariant]
    )

    #expect(results == [downloaded])
  }
}
