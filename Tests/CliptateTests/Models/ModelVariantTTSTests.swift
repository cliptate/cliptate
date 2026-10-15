import CliptateCore
import Testing
@testable import Cliptate

@Suite("ModelVariant TTS cases")
struct ModelVariantTTSTests {
    @Test func isTTSModelTrueForTTSCases() {
        let ttsCases: [ModelVariant] = [
            // Base
            .qwen3TTS06B4bit, .qwen3TTS06B8bit, .qwen3TTS06Bbf16,
            .qwen3TTS17B4bit, .qwen3TTS17B8bit, .qwen3TTS17Bbf16,
            // CustomVoice
            .qwen3TTS06BCustomVoice4bit, .qwen3TTS06BCustomVoice8bit, .qwen3TTS06BCustomVoiceBf16,
            .qwen3TTS17BCustomVoice4bit, .qwen3TTS17BCustomVoice8bit, .qwen3TTS17BCustomVoiceBf16,
            // VoiceDesign
            .qwen3TTS06BVoiceDesign4bit, .qwen3TTS06BVoiceDesign8bit, .qwen3TTS06BVoiceDesignBf16,
            .qwen3TTS17BVoiceDesign4bit, .qwen3TTS17BVoiceDesign8bit, .qwen3TTS17BVoiceDesignBf16,
        ]
        for c in ttsCases {
            #expect(c.isTTSModel, "\(c) should be a TTS model")
        }
    }

    @Test func isTTSModelFalseForNonTTSCases() {
        #expect(!ModelVariant.parakeetV3.isTTSModel)
        #expect(!ModelVariant.qwen3ASR.isTTSModel)
        #expect(!ModelVariant.sortformerStreaming.isTTSModel)
        #expect(!ModelVariant.qwen3ForcedAligner.isTTSModel)
    }

    @Test func ttsModelsStaticGroupContainsEighteenModels() {
        #expect(ModelVariant.ttsModels.count == 18)
        #expect(ModelVariant.ttsModels.allSatisfy { $0.isTTSModel })
    }

    @Test func huggingFaceRepoIdCorrectForTTSCases() {
        #expect(ModelVariant.qwen3TTS06B4bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit")
        #expect(ModelVariant.qwen3TTS06B8bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")
        #expect(ModelVariant.qwen3TTS06Bbf16.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
        #expect(ModelVariant.qwen3TTS17B4bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit")
        #expect(ModelVariant.qwen3TTS17B8bit.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit")
        #expect(ModelVariant.qwen3TTS17Bbf16.huggingFaceRepoId == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    }

    @Test func displayNameNonEmptyForTTSCases() {
        for c in ModelVariant.ttsModels {
            #expect(!c.displayName.isEmpty)
        }
    }

    @Test func mlxTTSModelDefinitionHasCorrectModelVariant() {
        let models = MLXTTSModelDefinition.availableModels
        #expect(models.count == 18)
        // Base models
        #expect(models[0].modelVariant == .qwen3TTS06B4bit)
        #expect(models[1].modelVariant == .qwen3TTS06B8bit)
        #expect(models[2].modelVariant == .qwen3TTS06Bbf16)
        #expect(models[3].modelVariant == .qwen3TTS17B4bit)
        #expect(models[4].modelVariant == .qwen3TTS17B8bit)
        #expect(models[5].modelVariant == .qwen3TTS17Bbf16)
        // CustomVoice models
        #expect(models[6].modelVariant == .qwen3TTS06BCustomVoice4bit)
        #expect(models[7].modelVariant == .qwen3TTS06BCustomVoice8bit)
        #expect(models[8].modelVariant == .qwen3TTS06BCustomVoiceBf16)
        #expect(models[9].modelVariant == .qwen3TTS17BCustomVoice4bit)
        #expect(models[10].modelVariant == .qwen3TTS17BCustomVoice8bit)
        #expect(models[11].modelVariant == .qwen3TTS17BCustomVoiceBf16)
        // VoiceDesign models
        #expect(models[12].modelVariant == .qwen3TTS06BVoiceDesign4bit)
        #expect(models[13].modelVariant == .qwen3TTS06BVoiceDesign8bit)
        #expect(models[14].modelVariant == .qwen3TTS06BVoiceDesignBf16)
        #expect(models[15].modelVariant == .qwen3TTS17BVoiceDesign4bit)
        #expect(models[16].modelVariant == .qwen3TTS17BVoiceDesign8bit)
        #expect(models[17].modelVariant == .qwen3TTS17BVoiceDesignBf16)
        for model in models {
            #expect(model.modelVariant.isTTSModel)
            #expect(model.modelVariant.huggingFaceRepoId == model.huggingFaceRepo)
        }
    }
}
