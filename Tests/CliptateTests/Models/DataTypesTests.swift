import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("ModelVariant catalog")
struct ModelVariantCatalogTests {
    @Test
    func sortformerModelsAreExposedAsVADOnlyModels() {
        #expect(ModelVariant.vadModels.contains(.sortformerStreaming))
        #expect(ModelVariant.vadModels.contains(.sileroVAD))
        #expect(ModelVariant.sortformerStreaming.isSortformerVADModel)
        #expect(ModelVariant.sortformerOffline.isSortformerVADModel)
        #expect(ModelVariant.sortformerOffline.isHiddenFromSelection)
        #expect(ModelVariant.sortformerStreaming.isQwen3Model == false)
        #expect(ModelVariant.sortformerOffline.isQwen3Model == false)
    }

    @Test("sileroVAD is a VAD model but not a Sortformer model")
    func sileroVADIsVADModelNotSortformer() {
        #expect(ModelVariant.sileroVAD.isVADModel)
        #expect(ModelVariant.sileroVAD.isSileroVADModel)
        #expect(ModelVariant.sileroVAD.isSortformerVADModel == false)
        #expect(ModelVariant.sileroVAD.isHiddenFromSelection == false)
    }

    @Test("sileroVAD downloads the stable v5 repository")
    func sileroVADUsesStableV5Repository() {
        #expect(ModelVariant.sileroVAD.huggingFaceRepoId == "mlx-community/silero-vad")
    }

    @Test("Silero VAD exposes the v5 identifier and no v6 label")
    func sileroVariantUsesV5Naming() {
        let sileroVariant = ModelVariant.vadModels.first(where: \.isSileroVADModel)
        #expect(sileroVariant?.rawValue == "silero-vad")
        #expect(sileroVariant?.displayName == "Silero VAD")
        #expect(sileroVariant?.huggingFaceRepoId == "mlx-community/silero-vad")
    }

    @Test("Legacy silero-vad-v6 snapshots decode to the current Silero variant")
    func sileroLegacyRawValueDecodesToCurrentVariant() throws {
        let decoded = try JSONDecoder().decode(ModelVariant.self, from: Data(#""silero-vad-v6""#.utf8))
        #expect(decoded.rawValue == "silero-vad")
        #expect(decoded.isSileroVADModel)
    }
}

@Suite("TranscriberType user-selectability")
struct TranscriberTypeSelectabilityTests {
    @Test("Whisper is selectable by user")
    func whisperSelectable() {
        #expect(TranscriberType.whisper.isSelectableByUser)
    }

    @Test("Parakeet, Qwen3, FireRed are selectable")
    func otherEnginesSelectable() {
        #expect(TranscriberType.parakeet.isSelectableByUser == true)
        #expect(TranscriberType.qwen3.isSelectableByUser == true)
        #expect(TranscriberType.fireRed.isSelectableByUser == true)
    }

    @Test("selectableCases includes Whisper")
    func selectableCasesFiltered() {
        let selectable = TranscriberType.selectableCases
        #expect(selectable.contains(.whisper))
        #expect(selectable.contains(.parakeet))
        #expect(selectable.contains(.qwen3))
        #expect(selectable.contains(.fireRed))
    }

    @Test("Cohere is selectable and exposes the expected model family")
    func cohereSelectable() throws {
        let cohere = try #require(TranscriberType(rawValue: "cohere"))
        let expectedModels = Set([
            "cohere-transcribe-03-2026-mlx-fp16",
            "cohere-transcribe-03-2026-mlx-8bit",
            "cohere-transcribe-03-2026-mlx-4bit",
        ])

        #expect(cohere.isSelectableByUser)
        #expect(TranscriberType.selectableCases.contains(cohere))
        #expect(Set(cohere.supportedModels.map(\.rawValue)) == expectedModels)

        let defaultModel = try #require(cohere.supportedModels.first)
        let transcriber = cohere.createTranscriber(model: defaultModel)
        #expect(String(describing: type(of: transcriber)).contains("Cohere"))
    }
}

@Suite("ModelVariant language filtering")
struct ModelVariantLanguageFilteringTests {
    @Test("Parakeet v2 supports only English")
    func parakeetV2EnglishOnly() {
        #expect(ModelVariant.parakeetV2.supportedLanguages == [.english])
    }

    @Test("Parakeet v3 supports multiple languages but not all")
    func parakeetV3Multilingual() {
        let langs = ModelVariant.parakeetV3.supportedLanguages
        #expect(langs.contains(.english))
        #expect(langs.contains(.french))
        #expect(!langs.contains(.auto))
        #expect(!langs.contains(.chinese))
    }

    @Test("Qwen3 ASR supports auto and multilingual")
    func qwen3ASRMultilingual() {
        let langs = ModelVariant.qwen3ASR.supportedLanguages
        #expect(langs.contains(.auto))
        #expect(langs.contains(.chinese))
        #expect(langs.contains(.english))
        #expect(langs.contains(.japanese))
    }

    @Test("FireRed supports auto, Chinese, English")
  func fireRedLanguages() {
    #expect(ModelVariant.fireRedASR2.supportedLanguages == [.auto, .chinese, .english])
  }

    @Test("Cohere supports the documented 14 languages plus auto detect")
    func cohereLanguages() throws {
        let variant = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-fp16"))
        let expected = Set<Language>([
            .auto, .english, .french, .german, .italian, .spanish, .portuguese,
            .greek, .dutch, .polish, .chinese, .japanese, .korean, .vietnamese,
            .arabic,
        ])

        #expect(Set(variant.supportedLanguages) == expected)
        #expect(variant.languageSummary == "14 supported languages")
        #expect(variant.supportedLanguages.contains(.auto))
        #expect(variant.supportedLanguages.contains(.arabic))
        #expect(variant.supportedLanguages.contains(.vietnamese))
        #expect(!variant.supportedLanguages.contains(.russian))
    }

    @Test("Cohere repositories map to the requested paid checkpoints")
    func cohereRepositoryMapping() throws {
        let fp16 = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-fp16"))
        let eightBit = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-8bit"))
        let fourBit = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-4bit"))

        #expect(fp16.huggingFaceRepoId == "beshkenadze/cohere-transcribe-03-2026-mlx-fp16")
        #expect(eightBit.huggingFaceRepoId == "beshkenadze/cohere-transcribe-03-2026-mlx-8bit")
        #expect(fourBit.huggingFaceRepoId == "beshkenadze/cohere-transcribe-03-2026-mlx-4bit")
    }
}

@Suite("ModelVariant storage metadata")
struct ModelVariantStorageMetadataTests {
    @Test("model variants expose their own download backend classification")
    func variantsExposeDownloadBackends() {
        #expect(ModelVariant.parakeetV3.downloadBackend == .resolver)
        #expect(ModelVariant.qwen3ASR.downloadBackend == .qwen3ASR)
        #expect(ModelVariant.qwen3ForcedAligner.downloadBackend == .qwen3Aligner)
        #expect(ModelVariant.fireRedASR2.downloadBackend == .fireRedASR)
        #expect(ModelVariant.cohereTranscribe03FP16.downloadBackend == .cohereASR)
        #expect(ModelVariant.sortformerStreaming.downloadBackend == .sortformerVAD)
        #expect(ModelVariant.sileroVAD.downloadBackend == .sileroVAD)
        #expect(ModelVariant.qwen3TTS06B4bit.downloadBackend == .resolver)
    }

    @Test("model variants expose repo-specific cache directory candidates")
    func variantsExposeCacheDirectoryCandidates() {
        let hubRoot = URL(fileURLWithPath: "/mock/home/.cache/huggingface/hub", isDirectory: true)
        let legacyBase = URL(fileURLWithPath: "/mock/Library/Caches/huggingface/hub/mlx-audio", isDirectory: true)

        let qwen3Paths = ModelVariant.qwen3ASR.storagePaths(
            hubRoot: hubRoot,
            legacyMLXAudioBase: legacyBase
        )
        #expect(qwen3Paths.mlxAudioDirectories.map(\.path) == [
            "/mock/home/.cache/huggingface/hub/mlx-audio/mlx-community_Qwen3-ASR-0.6B-8bit",
            "/mock/Library/Caches/huggingface/hub/mlx-audio/mlx-community_Qwen3-ASR-0.6B-8bit",
        ])
        #expect(qwen3Paths.huggingFaceRepositoryDirectories.map(\.path) == [
            "/mock/home/.cache/huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-8bit",
            "/mock/Library/Caches/huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-8bit",
        ])

        let coherePaths = ModelVariant.cohereTranscribe038bit.storagePaths(
            hubRoot: hubRoot,
            legacyMLXAudioBase: legacyBase
        )
        #expect(coherePaths.mlxAudioDirectories.map(\.path) == [
            "/mock/home/.cache/huggingface/hub/mlx-audio/beshkenadze_cohere-transcribe-03-2026-mlx-8bit",
            "/mock/Library/Caches/huggingface/hub/mlx-audio/beshkenadze_cohere-transcribe-03-2026-mlx-8bit",
        ])
        #expect(coherePaths.huggingFaceRepositoryDirectories.map(\.path) == [
            "/mock/home/.cache/huggingface/hub/models--beshkenadze--cohere-transcribe-03-2026-mlx-8bit",
            "/mock/Library/Caches/huggingface/hub/models--beshkenadze--cohere-transcribe-03-2026-mlx-8bit",
        ])
    }
}
