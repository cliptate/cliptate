import Foundation
import Testing

@testable import Cliptate

@Suite("TextToSpeechModels Tests")
struct TextToSpeechModelsTests {

    @Test("TTSEngine has expected cases")
    func testTTSEngineCases() {
        let engines = TTSEngine.allCases
        #expect(engines.count == 1)
        #expect(engines.contains(.qwen3TTS))
    }

    @Test("TTSEngine display names are non-empty")
    func testTTSEngineDisplayNames() {
        for engine in TTSEngine.allCases {
            #expect(!engine.displayName.isEmpty)
        }
    }

    @Test("MLXTTSModelDefinition has curated base models only")
    func testAvailableModelsCount() {
        #expect(MLXTTSModelDefinition.availableModels.count == 6)
    }

    @Test("All models have unique ids")
    func testUniqueModelIds() {
        let ids = MLXTTSModelDefinition.availableModels.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All models have unique repos")
    func testUniqueModelRepos() {
        let repos = MLXTTSModelDefinition.availableModels.map(\.huggingFaceRepo)
        #expect(Set(repos).count == repos.count)
    }

    @Test("Models filter by family correctly")
    func testFilterByFamily() {
        let base = MLXTTSModelDefinition.models(for: .base)
        let custom = MLXTTSModelDefinition.models(for: .customVoice)
        let design = MLXTTSModelDefinition.models(for: .voiceDesign)
        #expect(base.count == 6)
        #expect(custom.count == 0)
        #expect(design.count == 0)
        #expect(base.allSatisfy { $0.supportsVoiceClone })
        #expect(base.allSatisfy { !$0.supportsVoiceDesign })
    }

    @Test("TTSModelFamily has all cases")
    func testTTSModelFamilyCases() {
        #expect(TTSModelFamily.allCases.count == 3)
    }

    @Test("All models have family and quantization")
    func testModelProperties() {
        for model in MLXTTSModelDefinition.availableModels {
            #expect(!model.quantization.isEmpty)
            #expect(!model.parameterSize.isEmpty)
        }
    }
}
