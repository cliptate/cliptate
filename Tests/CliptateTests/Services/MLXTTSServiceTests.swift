import Foundation
import Testing

@testable import Cliptate

@Suite("MLXTTSService")
struct MLXTTSServiceTests {
    @Test
    func voiceClonePromptAddsSentenceTerminatorWhenMissing() {
        #expect(
            MLXTTSService.effectivePromptText(
                for: "这是一个测试",
                language: "zh",
                isVoiceClone: true
            ) == "这是一个测试。"
        )
        #expect(
            MLXTTSService.effectivePromptText(
                for: "This is a test",
                language: "en",
                isVoiceClone: true
            ) == "This is a test."
        )
    }

    @Test
    func voiceClonePromptPreservesExistingSentenceTerminator() {
        #expect(
            MLXTTSService.effectivePromptText(
                for: "Already finished!",
                language: "en",
                isVoiceClone: true
            ) == "Already finished!"
        )
        #expect(
            MLXTTSService.effectivePromptText(
                for: "保持原样。",
                language: "zh",
                isVoiceClone: true
            ) == "保持原样。"
        )
    }

    @Test
    func voiceCloneUsesStableGenerationParameters() {
        let params = MLXTTSService.generationParameters(isVoiceClone: true)

        #expect(params.temperature == 0.5)
        #expect(params.topP == 0.85)
        #expect(params.repetitionPenalty == 1.05)
    }

    @Test
    func automaticShortTextKeepsStandardTokenBudget() {
        let plan = MLXTTSService.makeSynthesisPlan(
            text: "Short narration.",
            language: "en",
            isVoiceClone: false,
            variantPreference: .automatic
        )

        #expect(plan.generationParameters.maxTokens == 1024)
    }

    @Test
    func automaticLongChineseTextUsesExtendedTokenBudgetWithoutTruncatingText() {
        let longText = String(repeating: "这是一段需要完整生成的中文内容。", count: 12)
        let plan = MLXTTSService.makeSynthesisPlan(
            text: longText,
            language: "zh",
            isVoiceClone: false,
            variantPreference: .automatic
        )

        #expect(TTSScriptMetrics.estimatedSpeechDuration(for: longText) > TTSVariantPreference.automatic.maxRecommendedDuration)
        #expect(plan.generationParameters.maxTokens == 32768)
        #expect(plan.text == longText)
    }

    @Test
    func explicitExtendedAlwaysUsesExtendedTokenBudget() {
        let plan = MLXTTSService.makeSynthesisPlan(
            text: "Short narration.",
            language: "en",
            isVoiceClone: false,
            variantPreference: .extended
        )

        #expect(plan.generationParameters.maxTokens == 32768)
    }

    @Test
    func explicitShortKeepsShortTokenBudgetForLongText() {
        let longText = String(repeating: "这是一段需要完整生成的中文内容。", count: 12)
        let plan = MLXTTSService.makeSynthesisPlan(
            text: longText,
            language: "zh",
            isVoiceClone: false,
            variantPreference: .short
        )

        #expect(plan.generationParameters.maxTokens == 320)
        #expect(plan.text == longText)
    }

    @Test
    func voiceCloneAddsTrailingReleasePad() {
        let samples: [Float] = [0.2, -0.1, 0.3]
        let padded = MLXTTSService.finalizeOutputSamples(
            samples,
            sampleRate: 24_000,
            isVoiceClone: true
        )

        #expect(padded.count == samples.count + 7_200)
        #expect(Array(padded.prefix(samples.count)) == samples)
        #expect(padded.suffix(7_200).allSatisfy { $0 == 0 })
    }

    @Test
    func nonCloneLeavesOutputUnpadded() {
        let samples: [Float] = [0.2, -0.1, 0.3]
        let padded = MLXTTSService.finalizeOutputSamples(
            samples,
            sampleRate: 24_000,
            isVoiceClone: false
        )

        #expect(padded == samples)
    }

    @Test
    func voiceClonePlanPrefersStreamingOutput() {
        let plan = MLXTTSService.makeSynthesisPlan(
            text: "最后一个字",
            language: "zh",
            isVoiceClone: true,
            variantPreference: .automatic
        )

        #expect(plan.useStreamingOutput)
        #expect(plan.applyReleasePadding)
        #expect(plan.text == "最后一个字。")
    }

    @Test
    func voiceCloneResolveOutputSamplesUsesStreamingPathAndPadsTail() async throws {
        let plan = MLXTTSService.makeSynthesisPlan(
            text: "最后一个字",
            language: "zh",
            isVoiceClone: true,
            variantPreference: .automatic
        )
        let sampleRate = 24_000

        let resolved = try await MLXTTSService.resolveOutputSamples(
            using: plan,
            sampleRate: sampleRate,
            generateWhole: { _ in
                Issue.record("voice-clone path should not use whole-output generation")
                return [0.1, 0.2]
            },
            generateStreamed: { _ in
                [0.1, 0.2, 0.3]
            }
        )

        #expect(Array(resolved.prefix(3)) == [0.1, 0.2, 0.3])
        #expect(resolved.count == 3 + 7_200)
        #expect(resolved.suffix(7_200).allSatisfy { $0 == 0 })
    }

    @Test
    func nonCloneResolveOutputSamplesKeepsDirectPath() async throws {
        let plan = MLXTTSService.makeSynthesisPlan(
            text: "Plain narration",
            language: "en",
            isVoiceClone: false,
            variantPreference: .automatic
        )

        let resolved = try await MLXTTSService.resolveOutputSamples(
            using: plan,
            sampleRate: 24_000,
            generateWhole: { _ in
                [0.4, 0.5]
            },
            generateStreamed: { _ in
                Issue.record("non-clone path should not use streamed samples")
                return [0.9]
            }
        )

        #expect(resolved == [0.4, 0.5])
        #expect(!plan.useStreamingOutput)
        #expect(!plan.applyReleasePadding)
        #expect(plan.text == "Plain narration")
    }

    @Test
    func sharedSingletonHasStableIdentity() {
        let service = MLXTTSService.shared
        #expect(service === MLXTTSService.shared)
    }

    @Test
    func isModelLoadedReturnsFalseInitially() async {
        let service = MLXTTSService()
        let loaded = await service.isModelLoaded
        #expect(loaded == false)
    }

    @Test
    func createWAVDataProducesValidData() throws {
        let sampleRate = 22050
        let samples: [Float] = Array(repeating: 0.0, count: sampleRate)
        let data = try MLXTTSService.createWAVData(from: samples, sampleRate: sampleRate)
        // WAV header is 44 bytes; data should be larger
        #expect(data.count > 44)
    }

    /// Verifies that the WAV `data` subchunk size field is written correctly.
    ///
    /// AVAudioFormat(standardFormatWithSampleRate:channels:) produces Float32 LPCM, so each sample
    /// occupies 4 bytes. AVAudioFile writes a non-standard WAV layout with JUNK/FLLR padding
    /// chunks before the `data` chunk; the `data` chunk appears at the end of the file.
    ///
    /// If AVAudioFile has not been flushed (deallocated) before Data(contentsOf:) reads the file,
    /// the `data` chunk size field will be 0 and the audio bytes will be absent, producing an
    /// unplayable file.
    @Test
    func createWAVDataHasCorrectDataChunkSize() throws {
        let sampleRate = 24000
        let sampleCount = 24000  // 1 second of audio
        let samples: [Float] = Array(repeating: 0.5, count: sampleCount)
        let data = try MLXTTSService.createWAVData(from: samples, sampleRate: sampleRate)

        // AVAudioFile writes: RIFF header (12) + JUNK chunk (36) + fmt chunk (24) + FLLR chunk +
        // data chunk. The `data` chunk sits at the end; locate it by scanning for "data" FourCC.
        //
        // Float32 LPCM: 4 bytes per sample → expectedAudioBytes = sampleCount * 4
        let expectedAudioBytes = UInt32(sampleCount * 4)
        let expectedTotalSize = 44 + Int(expectedAudioBytes)  // at minimum

        #expect(data.count >= expectedTotalSize,
            "WAV data too small: \(data.count) < \(expectedTotalSize)")

        // Scan for the "data" chunk FourCC (0x64617461) and read its size field.
        // The chunk layout is: 4-byte FourCC + 4-byte little-endian size.
        var dataChunkSize: UInt32? = nil
        var offset = 12  // skip RIFF header
        while offset + 8 <= data.count {
            let fourCC = data[offset..<(offset + 4)]
            let chunkSize = data.withUnsafeBytes { ptr -> UInt32 in
                ptr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).littleEndian
            }
            if fourCC.elementsEqual("data".utf8) {
                dataChunkSize = chunkSize
                break
            }
            offset += 8 + Int(chunkSize)
        }

        let size = try #require(dataChunkSize, "No 'data' chunk found in WAV output")
        #expect(
            size == expectedAudioBytes,
            "WAV 'data' chunk size should be \(expectedAudioBytes) bytes but was \(size) — AVAudioFile was not flushed before reading"
        )
    }

    @Test
    func createWAVDataUsesCompactInMemoryLayout() throws {
        let samples: [Float] = [0.25, -0.5, 0.75]
        let data = try MLXTTSService.createWAVData(from: samples, sampleRate: 24_000)

        #expect(data.count == 44 + samples.count * MemoryLayout<Float>.size)
        #expect(data.prefix(4).elementsEqual("RIFF".utf8))
        #expect(data[8..<12].elementsEqual("WAVE".utf8))
        #expect(data[12..<16].elementsEqual("fmt ".utf8))
        #expect(data[36..<40].elementsEqual("data".utf8))
    }

    @Test
    func synthesizeThrowsWhenModelNotLoaded() async throws {
        let service = MLXTTSService()
        let definition = MLXTTSModelDefinition(
            id: "test-model",
            displayName: "Test",
            huggingFaceRepo: "nonexistent/repo",
            parameterSize: "1B",
            estimatedSizeMB: 100,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Test model",
            family: .voiceDesign,
            quantization: "4-bit",
            modelVariant: .qwen3TTS06BVoiceDesign4bit
        )
        await #expect(throws: Error.self) {
            try await service.synthesize(
                text: "Hello",
                modelDefinition: definition,
                voiceDescription: nil,
                referenceAudioURL: nil,
                referenceText: nil,
                language: nil
            )
        }
    }

    @Test
    func synthesizeThrowsOnEmptyInput() async throws {
        let service = MLXTTSService()
        let definition = MLXTTSModelDefinition(
            id: "test-model",
            displayName: "Test",
            huggingFaceRepo: "nonexistent/repo",
            parameterSize: "1B",
            estimatedSizeMB: 100,
            supportsVoiceDesign: true,
            supportsVoiceClone: false,
            description: "Test model",
            family: .voiceDesign,
            quantization: "4-bit",
            modelVariant: .qwen3TTS06BVoiceDesign4bit
        )
        await #expect(throws: MLXTTSError.self) {
            try await service.synthesize(
                text: "   ",
                modelDefinition: definition,
                voiceDescription: nil,
                referenceAudioURL: nil,
                referenceText: nil,
                language: nil
            )
        }
    }

    @Test
    func resetClearsModelState() async {
        let service = MLXTTSService()
        await service.reset()
        let loaded = await service.isModelLoaded
        let repo = await service.loadedModelRepo
        #expect(loaded == false)
        #expect(repo == nil)
    }
}
