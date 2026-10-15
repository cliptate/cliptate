import CliptateCore
import AVFoundation
import Foundation
import os

@preconcurrency import MLX
@preconcurrency import MLXAudioCore
@preconcurrency import MLXAudioTTS
@preconcurrency import MLXLMCommon

private let logger = Logger(subsystem: "com.cliptate.tts", category: "MLXTTSService")

actor MLXTTSService {
    static let shared = MLXTTSService()
    private static let voiceCloneReleasePaddingSeconds = 0.30

    struct SynthesisPlan: Sendable {
        let text: String
        let generationParameters: GenerateParameters
        let useStreamingOutput: Bool
        let applyReleasePadding: Bool
    }

    private final class SpeechGenerationModelBox: @unchecked Sendable {
        let value: any SpeechGenerationModel

        init(_ value: any SpeechGenerationModel) {
            self.value = value
        }
    }

    private var currentModel: SpeechGenerationModelBox?
    private var currentModelRepo: String?
    private var loadTask: Task<Void, Error>?

    var isModelLoaded: Bool { currentModel != nil }
    var loadedModelRepo: String? { currentModelRepo }

    /// Load a TTS model from HuggingFace.
    func loadModel(definition: MLXTTSModelDefinition) async throws {
        logger.debug("Checking model: \(definition.huggingFaceRepo)")
        logger.debug("Current model repo: \(String(describing: self.currentModelRepo))")
        logger.debug("Current model loaded: \(self.currentModel != nil)")

        if currentModelRepo == definition.huggingFaceRepo, currentModel != nil {
            logger.debug("Model already loaded, skipping")
            return
        }

        loadTask?.cancel()
        let task = Task {
            logger.debug("Loading model from: \(definition.huggingFaceRepo)")
            let model = try await TTS.loadModel(modelRepo: definition.huggingFaceRepo)
            logger.debug("Model loaded successfully")
            self.currentModel = SpeechGenerationModelBox(model)
            self.currentModelRepo = definition.huggingFaceRepo
        }
        loadTask = task
        do {
            try await task.value
            logger.debug("Load task completed")
        } catch {
            logger.error("Failed to load model: \(error)")
            logger.error("Error details: \(error.localizedDescription)")
            throw error
        }
        loadTask = nil
    }

    /// Synthesize speech. Supports VoiceDesign (voiceDescription) and VoiceClone (referenceAudioURL + referenceText).
    func synthesize(
        text: String,
        modelDefinition: MLXTTSModelDefinition,
        voiceDescription: String?,
        referenceAudioURL: URL?,
        referenceText: String?,
        language: String?,
        variantPreference: TTSVariantPreference = .automatic
    ) async throws -> Data {
        logger.debug("synthesize START")
        logger.debug("Text: \(text)")
        logger.debug("Model: \(modelDefinition.displayName)")
        logger.debug("Voice description: \(String(describing: voiceDescription))")
        logger.debug("Reference audio URL: \(String(describing: referenceAudioURL))")
        logger.debug("Reference text: \(String(describing: referenceText))")
        logger.debug("Language: \(String(describing: language))")

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.error("Empty input")
            throw MLXTTSError.emptyInput
        }
        logger.debug("Checking if model needs to be loaded...")
        if currentModelRepo != modelDefinition.huggingFaceRepo || currentModel == nil {
            logger.debug("Loading model...")
            try await loadModel(definition: modelDefinition)
        }

        logger.debug("Verifying model is loaded...")
        guard let modelBox = currentModel else {
            logger.error("Model not loaded")
            throw MLXTTSError.modelNotLoaded
        }
        logger.debug("Model verified: \(String(describing: type(of: modelBox.value)))")

        // Prepare reference audio for voice cloning
        var refAudio: MLXArray?
        var refText: String?
        if let audioURL = referenceAudioURL {
            logger.debug("Reference audio URL: \(audioURL)")
            logger.debug("URL path: \(audioURL.path)")
            logger.debug("File exists: \(FileManager.default.fileExists(atPath: audioURL.path))")

            // For security-scoped bookmark-resolved URLs, startAccessingSecurityScopedResource()
            // must return true before any file I/O. For same-session Open Panel URLs the call
            // is harmless (returns false) and the sandbox grant from the panel interaction is
            // already active — so we only fail fast when the URL *is* security-scoped and
            // access could not be obtained.
            let isSecurityScoped = audioURL.startAccessingSecurityScopedResource()
            logger.debug("Security scoped access started: \(isSecurityScoped) for: \(audioURL.lastPathComponent)")
            defer {
                if isSecurityScoped {
                    audioURL.stopAccessingSecurityScopedResource()
                    logger.debug("Released security scoped resource")
                }
            }

            // Verify the file is actually readable before attempting to decode it.
            // A plain URL that was reconstructed from a saved path string (no bookmark)
            // will fail here with -54 (kAudioFilePermissionsError) in the sandbox.
            guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
                logger.error("Reference audio file is not readable in sandbox: \(audioURL.path)")
                throw MLXTTSError.referenceAudioNotAccessible
            }

            logger.debug("Attempting to load audio array...")
            do {
                let targetRate = modelBox.value.sampleRate
                let (sampleRate, audioData) = try loadAudioArray(from: audioURL, sampleRate: targetRate)
                logger.debug("Successfully loaded audio: sample rate=\(sampleRate), data count=\(audioData.size)")
                refAudio = audioData
                // Treat empty reference text as nil to avoid ICL path with no text context
                let trimmedRef = referenceText?.trimmingCharacters(in: .whitespacesAndNewlines)
                refText = (trimmedRef?.isEmpty == false) ? trimmedRef : nil
            } catch {
                logger.error("Failed to load audio array: \(error)")
                logger.error("Error details: \(error.localizedDescription)")
                throw error
            }
        } else {
            logger.warning("No reference audio URL provided")
        }
        let isVoiceClone = refAudio != nil
        let plan = Self.makeSynthesisPlan(
            text: trimmed,
            language: language,
            isVoiceClone: isVoiceClone,
            variantPreference: variantPreference
        )

        let repetitionPenaltyDescription = plan.generationParameters.repetitionPenalty.map { String(describing: $0) } ?? "nil"
        logger.debug("Generation parameters: temp=\(plan.generationParameters.temperature), topP=\(plan.generationParameters.topP), repPenalty=\(repetitionPenaltyDescription)")

        logger.debug("Calling synthesis execution plan...")
        do {
            let sampleRate = modelBox.value.sampleRate
            let samples = try await Self.resolveOutputSamples(
                using: plan,
                sampleRate: sampleRate,
                refAudio: refAudio,
                generateWhole: { audio in
                    let audioArray = try await modelBox.value.generate(
                        text: plan.text,
                        voice: voiceDescription,
                        refAudio: audio,
                        refText: refText,
                        language: language,
                        generationParameters: plan.generationParameters
                    )
                    return audioArray.asArray(Float.self)
                },
                generateStreamed: { audio in
                    try await Self.collectStreamedSamples(
                        from: modelBox.value,
                        text: plan.text,
                        voiceDescription: voiceDescription,
                        refAudio: audio,
                        refText: refText,
                        language: language,
                        generationParameters: plan.generationParameters
                    )
                }
            )
            logger.debug("Samples extracted: \(samples.count) samples")

            logger.debug("Creating WAV data...")
            let wavData = try Self.createWAVData(from: samples, sampleRate: sampleRate)
            logger.debug("WAV data created: \(wavData.count) bytes")

            return wavData
        } catch {
            logger.error("Generation failed: \(error)")
            logger.error("Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                logger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
                logger.error("User info: \(String(describing: nsError.userInfo))")
            }
            throw error
        }
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentModel = nil
        currentModelRepo = nil
    }

    /// Flush the MLX GPU buffer pool so intermediate tensors are returned to the
    /// system. Call between synthesis iterations to prevent memory accumulation.
    func clearMLXCache() {
        MLX.Memory.clearCache()
    }

    /// Synthesize speech returning raw float samples directly, without creating
    /// intermediate WAV Data. Uses the same synthesis plan and model path as
    /// `synthesize()` but skips the WAV encoding/decoding round-trip, reducing
    /// peak memory by ~2× per call.
    func synthesizeSamples(
        text: String,
        modelDefinition: MLXTTSModelDefinition,
        voiceDescription: String?,
        referenceAudioURL: URL?,
        referenceText: String?,
        language: String?,
        variantPreference: TTSVariantPreference = .automatic
    ) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MLXTTSError.emptyInput }

        if currentModelRepo != modelDefinition.huggingFaceRepo || currentModel == nil {
            try await loadModel(definition: modelDefinition)
        }
        guard let modelBox = currentModel else { throw MLXTTSError.modelNotLoaded }

        // Prepare reference audio for voice cloning
        var refAudio: MLXArray?
        var refText: String?
        if let audioURL = referenceAudioURL {
            let isSecurityScoped = audioURL.startAccessingSecurityScopedResource()
            defer { if isSecurityScoped { audioURL.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
                throw MLXTTSError.referenceAudioNotAccessible
            }
            let (_, audioData) = try loadAudioArray(from: audioURL, sampleRate: modelBox.value.sampleRate)
            refAudio = audioData
            let trimmedRef = referenceText?.trimmingCharacters(in: .whitespacesAndNewlines)
            refText = (trimmedRef?.isEmpty == false) ? trimmedRef : nil
        }

        let isVoiceClone = refAudio != nil
        let plan = Self.makeSynthesisPlan(
            text: trimmed, language: language,
            isVoiceClone: isVoiceClone, variantPreference: variantPreference
        )

        let sampleRate = modelBox.value.sampleRate
        let samples = try await Self.resolveOutputSamples(
            using: plan,
            sampleRate: sampleRate,
            refAudio: refAudio,
            generateWhole: { audio in
                let audioArray = try await modelBox.value.generate(
                    text: plan.text, voice: voiceDescription,
                    refAudio: audio, refText: refText,
                    language: language, generationParameters: plan.generationParameters
                )
                return audioArray.asArray(Float.self)
            },
            generateStreamed: { audio in
                try await Self.collectStreamedSamples(
                    from: modelBox.value, text: plan.text,
                    voiceDescription: voiceDescription,
                    refAudio: audio, refText: refText,
                    language: language, generationParameters: plan.generationParameters
                )
            }
        )
        logger.info("synthesizeSamples: \(samples.count) samples (\(String(format: "%.2f", Double(samples.count) / Double(sampleRate)))s)")
        return samples
    }

    /// Streaming synthesize: yields accumulated sample count as chunks arrive.
    /// Returns the final complete float samples array.
    func synthesizeStreaming(
        text: String,
        modelDefinition: MLXTTSModelDefinition,
        voiceDescription: String?,
        referenceAudioURL: URL?,
        referenceText: String?,
        language: String?,
        variantPreference: TTSVariantPreference = .automatic,
        onChunk: @escaping @Sendable (Int) -> Void
    ) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MLXTTSError.emptyInput }

        if currentModelRepo != modelDefinition.huggingFaceRepo || currentModel == nil {
            try await loadModel(definition: modelDefinition)
        }
        guard let modelBox = currentModel else { throw MLXTTSError.modelNotLoaded }

        // Prepare reference audio
        var refAudio: MLXArray?
        var refText: String?
        if let audioURL = referenceAudioURL {
            let isSecurityScoped = audioURL.startAccessingSecurityScopedResource()
            defer { if isSecurityScoped { audioURL.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
                throw MLXTTSError.referenceAudioNotAccessible
            }
            let (_, audioData) = try loadAudioArray(from: audioURL, sampleRate: modelBox.value.sampleRate)
            refAudio = audioData
            // Treat empty reference text as nil to avoid ICL path with no text context
            let trimmedRef = referenceText?.trimmingCharacters(in: .whitespacesAndNewlines)
            refText = (trimmedRef?.isEmpty == false) ? trimmedRef : nil
        }
        let plan = Self.makeSynthesisPlan(
            text: trimmed,
            language: language,
            isVoiceClone: refAudio != nil,
            variantPreference: variantPreference
        )

        // Use streaming generation
        let capturedRefAudio = refAudio
        let capturedRefText = refText
        var allSamples: [Float] = []

        let stream = modelBox.value.generateSamplesStream(
            text: plan.text,
            voice: voiceDescription,
            refAudio: capturedRefAudio,
            refText: capturedRefText,
            language: language,
            generationParameters: plan.generationParameters
        )

        for try await chunk in stream {
            allSamples.append(contentsOf: chunk)
            onChunk(allSamples.count)
        }

        // Apply release padding for voice clone to prevent abrupt endings
        let sampleRate = modelBox.value.sampleRate
        allSamples = Self.finalizeOutputSamples(
            allSamples,
            sampleRate: sampleRate,
            isVoiceClone: plan.applyReleasePadding
        )

        logger.info("Streaming synthesis complete: \(allSamples.count) samples")
        return allSamples
    }

    static func makeSynthesisPlan(
        text: String,
        language: String?,
        isVoiceClone: Bool,
        variantPreference: TTSVariantPreference
    ) -> SynthesisPlan {
        let effectiveText = effectivePromptText(for: text, language: language, isVoiceClone: isVoiceClone)
        return SynthesisPlan(
            text: effectiveText,
            generationParameters: generationParameters(
                isVoiceClone: isVoiceClone,
                variantPreference: variantPreference,
                text: effectiveText
            ),
            // Work around the upstream Qwen3 non-streaming decoder's valid-length trimming.
            useStreamingOutput: isVoiceClone,
            applyReleasePadding: isVoiceClone
        )
    }

    /// Transfer the reference tensor only to the selected generation path.
    static func resolveOutputSamples(
        using plan: SynthesisPlan,
        sampleRate: Int,
        refAudio: sending MLXArray? = nil,
        generateWhole: (sending MLXArray?) async throws -> [Float],
        generateStreamed: (sending MLXArray?) async throws -> [Float]
    ) async throws -> [Float] {
        let samples = if plan.useStreamingOutput {
            try await generateStreamed(refAudio)
        } else {
            try await generateWhole(refAudio)
        }
        return finalizeOutputSamples(
            samples,
            sampleRate: sampleRate,
            isVoiceClone: plan.applyReleasePadding
        )
    }

    private static func collectStreamedSamples(
        from model: any SpeechGenerationModel,
        text: String,
        voiceDescription: String?,
        refAudio: sending MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters
    ) async throws -> [Float] {
        var allSamples: [Float] = []
        let stream = model.generateSamplesStream(
            text: text,
            voice: voiceDescription,
            refAudio: refAudio,
            refText: refText,
            language: language,
            generationParameters: generationParameters
        )
        for try await chunk in stream {
            allSamples.append(contentsOf: chunk)
        }
        return allSamples
    }

    static func generationParameters(
        isVoiceClone: Bool,
        variantPreference: TTSVariantPreference = .automatic,
        text: String = ""
    ) -> GenerateParameters {
        let maxTokens = generationTokenBudget(for: variantPreference, text: text)
        if isVoiceClone {
            return GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0.5,
                topP: 0.85,
                repetitionPenalty: 1.05
            )
        }
        return GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0.9,
            topP: 0.95,
            repetitionPenalty: 1.05
        )
    }

    static func effectivePromptText(for text: String, language: String?, isVoiceClone: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isVoiceClone, !trimmed.isEmpty else { return trimmed }
        guard !trimmed.hasTerminalSentencePunctuation else {
            return trimmed
        }
        return trimmed + Self.defaultSentenceTerminator(for: language)
    }

    static func finalizeOutputSamples(_ samples: [Float], sampleRate: Int, isVoiceClone: Bool) -> [Float] {
        guard isVoiceClone, sampleRate > 0, !samples.isEmpty else { return samples }
        let paddingCount = max(1, Int((Self.voiceCloneReleasePaddingSeconds * Double(sampleRate)).rounded()))
        return samples + [Float](repeating: 0, count: paddingCount)
    }

    private static func defaultSentenceTerminator(for language: String?) -> String {
        switch language {
        case "zh", "ja":
            return "。"
        default:
            return "."
        }
    }

    private static func generationTokenBudget(
        for variantPreference: TTSVariantPreference,
        text: String
    ) -> Int {
        switch variantPreference {
        case .automatic:
            let estimatedDuration = TTSScriptMetrics.estimatedSpeechDuration(for: text)
            if estimatedDuration > TTSVariantPreference.automatic.maxRecommendedDuration {
                return generationTokenBudget(for: .extended, text: text)
            }
            return 1024
        case .short:
            return 320
        case .extended:
            // Set very high so the upstream model's own text-based formula
            // (max(75, targetTokenCount * 6)) is never capped by our budget.
            // This ensures long dubbing texts can generate their full audio.
            return 32768
        }
    }

    /// Convert float samples to WAV Data.
    static func createWAVData(from samples: [Float], sampleRate: Int) throws -> Data {
        guard sampleRate > 0 else {
            throw MLXTTSError.audioConversionFailed
        }

        let bytesPerSample = MemoryLayout<Float>.size
        let dataSize = samples.count * bytesPerSample
        let riffChunkSize = 36 + dataSize
        var data = Data(capacity: 44 + dataSize)

        data.append("RIFF".data(using: .ascii)!)
        appendLittleEndian(UInt32(riffChunkSize), to: &data)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        appendLittleEndian(UInt32(16), to: &data)  // PCM fmt chunk size
        appendLittleEndian(UInt16(3), to: &data)   // IEEE float
        appendLittleEndian(UInt16(1), to: &data)   // mono
        appendLittleEndian(UInt32(sampleRate), to: &data)
        appendLittleEndian(UInt32(sampleRate * bytesPerSample), to: &data)
        appendLittleEndian(UInt16(bytesPerSample), to: &data)
        appendLittleEndian(UInt16(8 * bytesPerSample), to: &data)

        data.append("data".data(using: .ascii)!)
        appendLittleEndian(UInt32(dataSize), to: &data)

        for sample in samples {
            appendLittleEndian(sample.bitPattern, to: &data)
        }
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

private extension String {
    var hasTerminalSentencePunctuation: Bool {
        let trailingClosers = CharacterSet(charactersIn: "\"'”’)]}〉》」』】」")
        let sentenceTerminators = CharacterSet(charactersIn: ".!?:;…。！？．｡")

        for scalar in unicodeScalars.reversed() {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || trailingClosers.contains(scalar) {
                continue
            }
            return sentenceTerminators.contains(scalar)
        }
        return false
    }
}

enum MLXTTSError: LocalizedError {
    case emptyInput
    case modelNotLoaded
    case audioConversionFailed
    case downloadFailed(String)
    case referenceAudioNotAccessible

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "Please enter text before synthesizing."
        case .modelNotLoaded: return "TTS model is not loaded. Download it from the Models page."
        case .audioConversionFailed: return "Failed to convert audio to WAV format."
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .referenceAudioNotAccessible:
            return "Cannot read the reference audio file. Please re-select it — sandbox access is lost after app restart."
        }
    }
}
