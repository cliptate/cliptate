import CliptateCore
import Testing


/// Verifies that each Qwen3 TTS model family exposes the correct synthesis capabilities
/// through `MLXTTSModelDefinition`. These properties drive which voice-mode tabs are
/// shown in the synthesis UI and how the `voice:` parameter is composed for each family.
@Suite("MLXTTSModelDefinition – capabilities per family")
struct TTSModelDefinitionCapabilityTests {

    // MARK: - Base family

    @Test("Base models support voice clone and not emotion control or voice design")
    func baseFamilyCapabilities() {
        let baseModels = MLXTTSModelDefinition.availableModels.filter { $0.family == .base }
        #expect(!baseModels.isEmpty)
        for model in baseModels {
            #expect(model.supportsVoiceClone, "\(model.id) should support voice clone")
            #expect(!model.supportsEmotionControl, "\(model.id) should NOT support emotion control")
            #expect(!model.supportsVoiceDesign, "\(model.id) should NOT support voice design")
        }
    }

    // MARK: - CustomVoice family

    @Test("CustomVoice models support emotion control and NOT voice clone or voice design")
    func customVoiceFamilyCapabilities() {
        let cvModels = MLXTTSModelDefinition.availableModels.filter { $0.family == .customVoice }
        #expect(!cvModels.isEmpty)
        for model in cvModels {
            #expect(model.supportsEmotionControl, "\(model.id) should support emotion control")
            #expect(!model.supportsVoiceClone, "\(model.id) should NOT support voice clone")
            #expect(!model.supportsVoiceDesign, "\(model.id) should NOT support voice design")
        }
    }

    // MARK: - VoiceDesign family

    @Test("VoiceDesign models support voice design and not clone or emotion control")
    func voiceDesignFamilyCapabilities() {
        let vdModels = MLXTTSModelDefinition.availableModels.filter { $0.family == .voiceDesign }
        #expect(!vdModels.isEmpty)
        for model in vdModels {
            #expect(model.supportsVoiceDesign, "\(model.id) should support voice design")
            #expect(!model.supportsVoiceClone, "\(model.id) should NOT support voice clone")
            #expect(!model.supportsEmotionControl, "\(model.id) should NOT support emotion control")
        }
    }

    // MARK: - Model counts

    @Test("Available models contain 6 models per family (18 total)")
    func totalModelCount() {
        #expect(MLXTTSModelDefinition.availableModels.count == 18)
        #expect(MLXTTSModelDefinition.models(for: .base).count == 6)
        #expect(MLXTTSModelDefinition.models(for: .customVoice).count == 6)
        #expect(MLXTTSModelDefinition.models(for: .voiceDesign).count == 6)
    }

    // MARK: - Voice string composition for CustomVoice

    @Test("CustomVoice voice string with speaker and emotion is composed correctly")
    func customVoiceStringComposition() {
        let speaker = "Vivian"
        let emotion = "very happy and excited"
        let result = MLXTTSModelDefinition.customVoiceString(speaker: speaker, emotionPrompt: emotion)
        #expect(result == "Vivian, very happy and excited")
    }

    @Test("CustomVoice voice string with empty speaker returns emotion prompt only")
    func customVoiceStringCompositionNoSpeaker() {
        let result = MLXTTSModelDefinition.customVoiceString(speaker: "", emotionPrompt: "calm and warm")
        #expect(result == "calm and warm")
    }

    @Test("CustomVoice voice string with speaker and empty emotion returns speaker only")
    func customVoiceStringCompositionNoEmotion() {
        let result = MLXTTSModelDefinition.customVoiceString(speaker: "Ryan", emotionPrompt: "")
        #expect(result == "Ryan")
    }

    @Test("CustomVoice voice string with both empty returns nil")
    func customVoiceStringCompositionBothEmpty() {
        let result = MLXTTSModelDefinition.customVoiceString(speaker: "", emotionPrompt: "")
        #expect(result == nil)
    }
}
