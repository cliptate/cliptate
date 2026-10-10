import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.cliptate.dubbing", category: "DubbingService")

/// Orchestrates the audio dubbing pipeline: extract voice reference → per-segment TTS synthesis
/// with voice cloning → time alignment → audio composition → export.
public final class DubbingService {

    /// Progress phases reported during dubbing.
    public struct DubbingProgress: Sendable {
        public let phase: Phase
        public let currentSegment: Int
        public let totalSegments: Int
        public let generatedSamples: Int

        public init(phase: Phase, currentSegment: Int, totalSegments: Int, generatedSamples: Int = 0) {
            self.phase = phase
            self.currentSegment = currentSegment
            self.totalSegments = totalSegments
            self.generatedSamples = generatedSamples
        }

        public enum Phase: Sendable {
            case extractingReference
            case synthesizing
            case composing
            case exporting
        }
    }

    /// Result of a dubbing operation.
    public struct DubbingResult: Sendable {
        public let audioFileURL: URL
        public let segmentsDubbed: Int
        public let segmentsSkipped: Int
        public let totalDuration: TimeInterval
    }

    /// Errors specific to the dubbing pipeline.
    public enum DubbingError: LocalizedError {
        case noTranslations
        case noSegments
        case ttsLanguageUnsupported(String)
        case ttsModelNotAvailable
        case noAudioTrack
        case referenceExtractionFailed

        public var errorDescription: String? {
            switch self {
            case .noTranslations:
                return String(localized: "No translated segments available. Translate your content before dubbing.", comment: "Dubbing error: no translations")
            case .noSegments:
                return String(localized: "No segments to dub. Transcribe your content first.", comment: "Dubbing error: no segments")
            case .ttsLanguageUnsupported(let lang):
                return String(localized: "The target language '\(lang)' is not supported by the selected TTS model. Supported: en, zh, ja, ko.", comment: "Dubbing error: unsupported TTS language")
            case .ttsModelNotAvailable:
                return String(localized: "TTS model is not available. Download it from the Models page.", comment: "Dubbing error: TTS model unavailable")
            case .noAudioTrack:
                return String(localized: "The source media has no audio track.", comment: "Dubbing error: no audio track")
            case .referenceExtractionFailed:
                return String(localized: "Could not extract voice reference from the source media.", comment: "Dubbing error: reference extraction failed")
            }
        }
    }

    /// Languages supported by Qwen3 TTS for synthesis.
    public static let supportedTTSLanguages: Set<String> = ["en", "zh", "ja", "ko"]

    private let ttsService: MLXTTSService

    init(ttsService: MLXTTSService) {
        self.ttsService = ttsService
    }

    /// Generate a dubbed audio track from translated segments.
    ///
    /// - Parameters:
    ///   - sourceMediaURL: URL of the original video/audio file.
    ///   - segments: Processed segments with translations.
    ///   - totalDuration: Total duration of the source media.
    ///   - ttsModelDefinition: The MLX TTS model to use for synthesis.
    ///   - ttsLanguage: Target language code (e.g., "en", "zh", "ja", "ko").
    ///   - outputURL: Where to write the dubbed audio file.
    ///   - outputFormat: Audio export format (m4a or wav).
    ///   - presetSpeaker: Fallback preset speaker if reference extraction fails.
    ///   - customReferenceAudioURL: Optional custom reference audio URL for voice cloning (overrides auto-extraction).
    ///   - customReferenceText: Optional transcription of the custom reference audio.
    ///   - progress: Callback for progress updates.
    /// - Returns: A `DubbingResult` describing the output.
    public func generateDubbedAudio(
        sourceMediaURL: URL,
        segments: [Segment],
        totalDuration: TimeInterval,
        ttsModelDefinition: MLXTTSModelDefinition,
        ttsLanguage: String,
        outputURL: URL,
        outputFormat: AudioExportFormat,
        presetSpeaker: String?,
        customReferenceAudioURL: URL? = nil,
        customReferenceText: String? = nil,
        progress: @escaping @Sendable (DubbingProgress) -> Void
    ) async throws -> DubbingResult {
        // Preflight checks
        guard !segments.isEmpty else { throw DubbingError.noSegments }

        let translatedSegments = segments.filter { $0.translation != nil }
        guard !translatedSegments.isEmpty else { throw DubbingError.noTranslations }

        guard Self.supportedTTSLanguages.contains(ttsLanguage) else {
            throw DubbingError.ttsLanguageUnsupported(ttsLanguage)
        }

        // Step 1: Obtain voice reference (custom or auto-extracted)
        progress(DubbingProgress(phase: .extractingReference, currentSegment: 0, totalSegments: translatedSegments.count))

        let referenceURL: URL
        let referenceText: String
        var shouldCleanupReference = false

        if let customURL = customReferenceAudioURL, FileManager.default.fileExists(atPath: customURL.path) {
            referenceURL = customURL
            referenceText = customReferenceText ?? ""
            logger.info("Using custom voice reference: \(customURL.lastPathComponent)")
        } else {
            let extracted = try await extractVoiceReference(
                from: sourceMediaURL,
                segments: segments,
                presetSpeaker: presetSpeaker
            )
            referenceURL = extracted.referenceURL
            referenceText = extracted.referenceText
            shouldCleanupReference = true
        }
        defer { if shouldCleanupReference { try? FileManager.default.removeItem(at: referenceURL) } }

        // Step 2: Per-segment synthesis → temp file → global time adjustment.
        //
        // Strategy: synthesize each segment INDIVIDUALLY, append raw samples to a
        // temp file (instead of accumulating in memory), clear the MLX GPU cache
        // after each segment, then do a single-pass time adjustment and export.
        let sampleRate = 24000  // Qwen3 TTS output sample rate
        var segmentsDubbed = 0
        var segmentsSkipped = 0
        var totalGeneratedSamples = 0

        // Write synthesized audio to a temporary file to avoid accumulating all
        // segment samples in memory simultaneously.
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dubbing-\(UUID().uuidString).raw")
        FileManager.default.createFile(atPath: tempAudioURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tempAudioURL) }
        let tempHandle = try FileHandle(forWritingTo: tempAudioURL)
        defer { try? tempHandle.close() }

        for (index, segment) in translatedSegments.enumerated() {
            progress(DubbingProgress(
                phase: .synthesizing,
                currentSegment: index + 1,
                totalSegments: translatedSegments.count
            ))

            guard let translationText = segment.translation?.text,
                  !translationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                segmentsSkipped += 1
                continue
            }

            let text = Self.ensureSentenceTerminator(translationText, language: ttsLanguage)

            do {
                let rawSamples = try await ttsService.synthesizeSamples(
                    text: text,
                    modelDefinition: ttsModelDefinition,
                    voiceDescription: nil,
                    referenceAudioURL: referenceURL,
                    referenceText: referenceText,
                    language: ttsLanguage,
                    variantPreference: .automatic
                )

                guard !rawSamples.isEmpty else {
                    segmentsSkipped += 1
                    logger.warning("Dubbing: empty synthesis for segment \(index)")
                    continue
                }

                let segDuration = Double(rawSamples.count) / Double(sampleRate)
                let textPreview = text.count > 30 ? "\(text.prefix(30))…" : text
                logger.info("Dubbing[\(index)]: synthesized \(String(format: "%.2f", segDuration))s for '\(textPreview)'")

                // Append to temp file and release the samples array immediately.
                rawSamples.withUnsafeBufferPointer { buf in
                    tempHandle.write(Data(
                        bytesNoCopy: UnsafeMutableRawPointer(mutating: buf.baseAddress!),
                        count: buf.count * MemoryLayout<Float>.size,
                        deallocator: .none
                    ))
                }
                totalGeneratedSamples += rawSamples.count
                segmentsDubbed += 1
            } catch {
                segmentsSkipped += 1
                logger.error("Dubbing: synthesis failed for segment \(index): \(error.localizedDescription)")
            }

            // Flush MLX GPU buffer pool between segments so intermediate tensors
            // (KV cache, attention matrices, codec state) don't accumulate.
            await ttsService.clearMLXCache()
        }
        try tempHandle.close()

        // Step 3: Read concatenated audio, apply global time adjustment, compose output.
        progress(DubbingProgress(phase: .composing, currentSegment: segmentsDubbed, totalSegments: translatedSegments.count))

        let concatenatedDuration = Double(totalGeneratedSamples) / Double(sampleRate)
        let speechStart = translatedSegments.first!.startTime
        let availableTime = totalDuration - speechStart

        logger.info("Dubbing: total generated \(String(format: "%.2f", concatenatedDuration))s, available window \(String(format: "%.2f", availableTime))s (from \(String(format: "%.2f", speechStart))s)")

        // Read all concatenated samples back from the temp file.
        let rawData = try Data(contentsOf: tempAudioURL)
        var concatenated = [Float](repeating: 0, count: rawData.count / MemoryLayout<Float>.size)
        rawData.withUnsafeBytes { buf in
            _ = concatenated.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, buf.baseAddress!, rawData.count)
            }
        }

        let finalSamples: [Float]
        if concatenatedDuration > availableTime && availableTime > 0 {
            finalSamples = AudioTimeStretcher.stretchToFit(
                samples: concatenated,
                sampleRate: sampleRate,
                targetDuration: availableTime,
                maxSpeedup: 3.0
            )
            let resultDuration = Double(finalSamples.count) / Double(sampleRate)
            logger.info("Dubbing: compressed \(String(format: "%.2f", concatenatedDuration))s → \(String(format: "%.2f", resultDuration))s")
        } else {
            finalSamples = concatenated
        }
        // Release the concatenated buffer early — we only need finalSamples from here.
        // (Swift's ARC handles this when `concatenated` goes out of scope, but we can
        //  explicitly clear it in case finalSamples === concatenated.)

        // Build the full-duration output and write directly to the export file.
        // Instead of allocating a full-duration [Float] + WAV Data in memory,
        // we write the WAV header first, then stream silence + audio data.
        logger.info("Dubbing: \(segmentsDubbed) segments dubbed, \(segmentsSkipped) skipped")

        // Step 5: Export — stream directly to file to minimise peak memory.
        progress(DubbingProgress(phase: .exporting, currentSegment: segmentsDubbed, totalSegments: translatedSegments.count))

        let totalSamples = Int(totalDuration * Double(sampleRate))
        let startSample = Int(speechStart * Double(sampleRate))
        let copyCount = min(finalSamples.count, totalSamples - startSample)

        let wavURL: URL
        if outputFormat == .wav {
            wavURL = outputURL
        } else {
            wavURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dubbing-wav-\(UUID().uuidString).wav")
        }
        defer { if outputFormat != .wav { try? FileManager.default.removeItem(at: wavURL) } }

        try Self.writeWAVFile(
            to: wavURL,
            sampleRate: sampleRate,
            totalSamples: totalSamples,
            audioSamples: finalSamples,
            audioStartSample: startSample,
            audioCopyCount: copyCount
        )

        if outputFormat == .m4a {
            try await Self.convertWAVFileToM4A(wavURL: wavURL, outputURL: outputURL)
        }

        return DubbingResult(
            audioFileURL: outputURL,
            segmentsDubbed: segmentsDubbed,
            segmentsSkipped: segmentsSkipped,
            totalDuration: totalDuration
        )
    }

    // MARK: - Time Fitting

    /// Compute the available time window for each segment.
    ///
    /// The window extends from the segment's start time to a point that includes
    /// adjacent silence: specifically up to the next segment's start time (or
    /// totalDuration for the last segment). This lets dubbing audio naturally
    /// spill into silent gaps between segments.
    static func computeAvailableWindows(
        segments: [Segment],
        totalDuration: TimeInterval
    ) -> [TimeInterval] {
        var windows: [TimeInterval] = []
        for (i, segment) in segments.enumerated() {
            let nextStart: TimeInterval
            if i + 1 < segments.count {
                nextStart = segments[i + 1].startTime
            } else {
                nextStart = totalDuration
            }
            // Available window = from this segment's start to the next segment's start
            // (includes the silent gap after this segment ends)
            let available = max(0.1, nextStart - segment.startTime)
            windows.append(available)
        }
        return windows
    }

    /// Fit synthesized samples into the available time window.
    ///
    /// The AudioComposer allows clips to overflow by up to 300ms (defaultMaxOverflow) with
    /// crossfade, so we only time-stretch when audio significantly exceeds the window.
    /// Specifically: time-stretch only if the audio exceeds window + maxOverflow (300ms).
    static func fitSamplesToWindow(
        samples: [Float],
        sampleRate: Int,
        availableWindow: TimeInterval
    ) -> [Float] {
        let generatedDuration = Double(samples.count) / Double(sampleRate)
        // Only compress if audio exceeds the window + the overflow tolerance of AudioComposer
        let overflowAllowance = AudioComposer.defaultMaxOverflow
        guard generatedDuration > availableWindow + overflowAllowance else {
            return samples
        }

        // Target: fit within window + a small buffer so the natural ending is preserved
        let targetDuration = availableWindow + overflowAllowance * 0.5
        return AudioTimeStretcher.stretchToFit(
            samples: samples,
            sampleRate: sampleRate,
            targetDuration: targetDuration
        )
    }

    // MARK: - Batch Synthesis

    /// Group translated segments into batches for TTS generation.
    ///
    /// Strategy: merge short consecutive segments (combined original duration < `minBatchDuration`)
    /// into a single batch for joint synthesis, which produces better prosody and more natural
    /// speech flow. Only split into a new batch when:
    /// - Combined duration would exceed `minBatchDuration` AND character limit
    /// - There's a large time gap indicating a topic/speaker change
    static func createBatches(
        from segments: [Segment],
        maxCharsPerBatch: Int,
        minBatchDuration: TimeInterval = 5.0
    ) -> [[Segment]] {
        guard !segments.isEmpty else { return [] }

        var batches: [[Segment]] = []
        var current: [Segment] = []
        var currentChars = 0
        var currentDuration: TimeInterval = 0
        let gapThreshold: TimeInterval = 1.5  // Tighter gap threshold for merging

        for (i, segment) in segments.enumerated() {
            let textLen = segment.translation?.text.count ?? 0
            let segDuration = segment.duration

            // Start a new batch when:
            // - Combined duration >= minBatchDuration AND adding exceeds char limit
            // - There's a large time gap from the previous segment
            let exceedsLimit = !current.isEmpty
                && currentDuration >= minBatchDuration
                && (currentChars + textLen) > maxCharsPerBatch
            let hasLargeGap: Bool = {
                guard i > 0 else { return false }
                return segment.startTime - segments[i - 1].endTime > gapThreshold
            }()

            if exceedsLimit || hasLargeGap {
                if !current.isEmpty {
                    batches.append(current)
                }
                current = [segment]
                currentChars = textLen
                currentDuration = segDuration
            } else {
                current.append(segment)
                currentChars += textLen
                currentDuration += segDuration
            }
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    /// Synthesize a batch of segments for dubbing.
    ///
    /// - Single segment: synthesize individually for clean endings.
    /// - Multiple segments (merged short phrases): synthesize as one joined text for better
    ///   prosody and natural flow, then split using energy-based boundary detection.
    private func synthesizeBatchStreaming(
        batch: [Segment],
        ttsModelDefinition: MLXTTSModelDefinition,
        ttsLanguage: String,
        referenceURL: URL,
        referenceText: String,
        sampleRate: Int,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> [[Float]] {
        // Single segment: synthesize standalone for clean endings
        if batch.count == 1 {
            guard let translation = batch[0].translation else { return [[]] }
            let samples = try await ttsService.synthesizeStreaming(
                text: Self.ensureSentenceTerminator(translation.text, language: ttsLanguage),
                modelDefinition: ttsModelDefinition,
                voiceDescription: nil,
                referenceAudioURL: referenceURL,
                referenceText: referenceText,
                language: ttsLanguage,
                variantPreference: .extended,
                onChunk: progress
            )
            let trimmed = Self.trimTrailingSilence(
                samples: samples,
                sampleRate: sampleRate,
                keepTailSeconds: 0.15
            )
            return [trimmed]
        }

        // Multiple segments (merged short phrases): join and synthesize as one utterance
        // for continuous prosody, then split by energy boundaries.
        let separator = Self.sentenceSeparator(for: ttsLanguage)
        let texts = batch.compactMap { $0.translation?.text }
        let terminatedTexts = texts.map { text in
            Self.ensureSentenceTerminator(text, language: ttsLanguage)
        }
        let fullText = terminatedTexts.joined(separator: separator)

        let allSamples = try await ttsService.synthesizeStreaming(
            text: fullText,
            modelDefinition: ttsModelDefinition,
            voiceDescription: nil,
            referenceAudioURL: referenceURL,
            referenceText: referenceText,
            language: ttsLanguage,
            variantPreference: .extended,
            onChunk: progress
        )

        // Trim the final trailing silence on the whole batch
        let trimmed = Self.trimTrailingSilence(
            samples: allSamples,
            sampleRate: sampleRate,
            keepTailSeconds: 0.15
        )

        // Split using energy-based boundary detection
        return Self.splitAudioByEnergyBoundaries(
            samples: trimmed,
            sampleRate: sampleRate,
            segmentTexts: texts,
            segmentDurations: batch.map(\.duration)
        )
    }

    /// Trim excess trailing silence while preserving a natural speech tail.
    ///
    /// Scans from the end of the audio backward to find where actual speech content ends,
    /// then keeps `keepTailSeconds` of buffer after the last audible sample.
    static func trimTrailingSilence(
        samples: [Float],
        sampleRate: Int,
        keepTailSeconds: TimeInterval
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }

        let keepTailSamples = Int(keepTailSeconds * Double(sampleRate))
        let windowSize = Int(0.02 * Double(sampleRate))  // 20ms analysis window
        let silenceThreshold: Float = 0.005  // RMS below this is considered silence

        // Scan backward to find the last non-silent window
        var lastAudibleIdx = samples.count - 1
        var pos = samples.count - windowSize
        while pos >= 0 {
            var energy: Float = 0
            for i in pos..<min(pos + windowSize, samples.count) {
                energy += samples[i] * samples[i]
            }
            let rms = (energy / Float(windowSize)).squareRoot()
            if rms > silenceThreshold {
                lastAudibleIdx = pos + windowSize
                break
            }
            pos -= windowSize
        }

        // Keep the tail buffer after the last audible content
        let trimPoint = min(lastAudibleIdx + keepTailSamples, samples.count)
        if trimPoint >= samples.count - keepTailSamples {
            // Not much to trim; keep as-is to avoid cutting content
            return samples
        }
        return Array(samples.prefix(trimPoint))
    }

    /// Choose a natural sentence separator based on TTS language.
    static func sentenceSeparator(for language: String) -> String {
        switch language {
        case "zh", "ja": return "。"
        default: return ". "
        }
    }

    /// Ensure text ends with a sentence terminator for proper TTS prosody.
    static func ensureSentenceTerminator(_ text: String, language: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "…", "；"]
        let trailingClosers: Set<Character> = ["\u{22}", "\u{27}", "\u{2019}", "\u{201D}", ")", "]", "}", "〉", "》", "」", "』", "】"]
        // Check if the text already ends with a terminator (possibly followed by closing quotes)
        for char in trimmed.reversed() {
            if trailingClosers.contains(char) { continue }
            if terminators.contains(char) { return trimmed }
            break
        }
        // Append appropriate terminator
        switch language {
        case "zh", "ja":
            return trimmed + "。"
        default:
            return trimmed + "."
        }
    }

    /// Split continuous audio into per-segment chunks using energy-based boundary detection.
    ///
    /// 1. Estimate initial boundaries using a weighted blend of text length and original duration.
    /// 2. Search for a low-energy minimum within ±300ms of each estimated boundary.
    /// 3. Snap the split point to that minimum.
    static func splitAudioByEnergyBoundaries(
        samples: [Float],
        sampleRate: Int,
        segmentTexts: [String],
        segmentDurations: [TimeInterval]
    ) -> [[Float]] {
        let count = segmentTexts.count
        guard count > 1, !samples.isEmpty else {
            return [samples]
        }

        // Compute weights: blend of text length (0.4) and original duration (0.6)
        let textLengths = segmentTexts.map { Double($0.count) }
        let totalTextLen = textLengths.reduce(0, +)
        let totalDuration = segmentDurations.reduce(0, +)

        var weights: [Double] = []
        for i in 0..<count {
            let textWeight = totalTextLen > 0 ? textLengths[i] / totalTextLen : 1.0 / Double(count)
            let durWeight = totalDuration > 0 ? segmentDurations[i] / totalDuration : 1.0 / Double(count)
            weights.append(0.4 * textWeight + 0.6 * durWeight)
        }

        // Normalize weights
        let wSum = weights.reduce(0, +)
        if wSum > 0 { weights = weights.map { $0 / wSum } }

        // Compute cumulative boundary positions (in samples)
        var boundaries = [0]
        var cumulative = 0.0
        for i in 0..<(count - 1) {
            cumulative += weights[i]
            let estimatedSample = Int(cumulative * Double(samples.count))

            // Search ±300ms for energy minimum
            let searchWindow = Int(0.3 * Double(sampleRate))
            let lo = max(0, estimatedSample - searchWindow)
            let hi = min(samples.count, estimatedSample + searchWindow)

            let snapped = findMinEnergySample(in: samples, from: lo, to: hi, windowSize: Int(0.01 * Double(sampleRate)))
            boundaries.append(snapped)
        }
        boundaries.append(samples.count)

        // Ensure boundaries are monotonically increasing
        for i in 1..<boundaries.count {
            if boundaries[i] <= boundaries[i - 1] {
                boundaries[i] = boundaries[i - 1] + 1
            }
        }

        // Extract segments
        var result: [[Float]] = []
        for i in 0..<count {
            let start = min(boundaries[i], samples.count)
            let end = min(boundaries[i + 1], samples.count)
            if start < end {
                result.append(Array(samples[start..<end]))
            } else {
                result.append([])
            }
        }
        return result
    }

    /// Find the sample index with minimum RMS energy within a range.
    static func findMinEnergySample(
        in samples: [Float],
        from lo: Int,
        to hi: Int,
        windowSize: Int
    ) -> Int {
        guard lo < hi, windowSize > 0 else { return lo }

        let halfWindow = windowSize / 2
        var bestIdx = lo
        var bestEnergy = Double.infinity

        // Step by half-window for efficiency
        let step = max(1, halfWindow)
        var pos = lo
        while pos < hi {
            let wStart = max(0, pos - halfWindow)
            let wEnd = min(samples.count, pos + halfWindow)
            var energy = 0.0
            for j in wStart..<wEnd {
                energy += Double(samples[j] * samples[j])
            }
            energy /= Double(wEnd - wStart)

            if energy < bestEnergy {
                bestEnergy = energy
                bestIdx = pos
            }
            pos += step
        }
        return bestIdx
    }

    // MARK: - Voice Reference Extraction

    /// Extract a voice reference from the source media using the longest speech segments.
    private func extractVoiceReference(
        from sourceURL: URL,
        segments: [Segment],
        presetSpeaker: String?
    ) async throws -> (referenceURL: URL, referenceText: String) {
        let allSamples: [Float]
        do {
            allSamples = try await AudioProcessor.loadAndConvertAudio(url: sourceURL)
        } catch {
            throw DubbingError.noAudioTrack
        }

        // Find the most frequent speaker for multi-speaker content
        let primarySpeakerId = Self.primarySpeaker(from: segments)

        // Filter to primary speaker's segments, sorted by duration (longest first)
        let candidateSegments = segments
            .filter { seg in
                if let primary = primarySpeakerId {
                    return seg.speakerId == primary
                }
                return true
            }
            .sorted { $0.duration > $1.duration }

        // Accumulate segments until we have ≥5 seconds of speech
        var selectedSegments: [Segment] = []
        var accumulatedDuration: TimeInterval = 0
        let targetDuration: TimeInterval = 5.0

        for seg in candidateSegments {
            selectedSegments.append(seg)
            accumulatedDuration += seg.duration
            if accumulatedDuration >= targetDuration { break }
        }

        // If we have less than 1 second, reference quality will be poor
        if accumulatedDuration < 1.0 {
            if selectedSegments.isEmpty, let first = segments.first {
                selectedSegments = [first]
            }
            guard !selectedSegments.isEmpty else {
                throw DubbingError.referenceExtractionFailed
            }
        }

        // Extract and concatenate audio samples from selected segments
        var referenceSamples: [Float] = []
        var referenceTexts: [String] = []

        for seg in selectedSegments.sorted(by: { $0.startTime < $1.startTime }) {
            let segSamples = AudioProcessor.extractSamples(
                samples: allSamples,
                startTime: seg.startTime,
                endTime: seg.endTime
            )
            referenceSamples.append(contentsOf: segSamples)
            referenceTexts.append(seg.text)
        }

        let referenceText = referenceTexts.joined(separator: " ")

        // Save to temporary file
        let referenceURL = try AudioProcessor.saveSegmentToTemporaryFile(samples: referenceSamples)

        logger.info("Voice reference extracted: \(String(format: "%.1f", accumulatedDuration))s from \(selectedSegments.count) segment(s)")

        return (referenceURL, referenceText)
    }

    /// Find the most frequent speakerId from segments.
    static func primarySpeaker(from segments: [Segment]) -> Int? {
        var counts: [Int: Int] = [:]
        for seg in segments {
            if let id = seg.speakerId {
                counts[id, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Audio Utilities

    /// Parse float samples from WAV data.
    static func samplesFromWAVData(_ data: Data) throws -> [Float] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let file = try AVAudioFile(forReading: tempURL)
        let format = AVAudioFormat(standardFormatWithSampleRate: file.fileFormat.sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw MLXTTSError.audioConversionFailed
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw MLXTTSError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }

    /// Write a WAV file with silence-padded audio placed at a given sample
    /// offset.  Streams output in chunks to avoid allocating a full-duration
    /// in-memory buffer.
    private static func writeWAVFile(
        to url: URL,
        sampleRate: Int,
        totalSamples: Int,
        audioSamples: [Float],
        audioStartSample: Int,
        audioCopyCount: Int
    ) throws {
        let bytesPerSample = MemoryLayout<Float>.size
        let dataSize = totalSamples * bytesPerSample
        let riffChunkSize = 36 + dataSize

        // Write WAV header
        var header = Data(capacity: 44)
        header.append("RIFF".data(using: .ascii)!)
        Self.appendLE(UInt32(riffChunkSize), to: &header)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        Self.appendLE(UInt32(16), to: &header)
        Self.appendLE(UInt16(3), to: &header)       // IEEE float
        Self.appendLE(UInt16(1), to: &header)       // mono
        Self.appendLE(UInt32(sampleRate), to: &header)
        Self.appendLE(UInt32(sampleRate * bytesPerSample), to: &header)
        Self.appendLE(UInt16(bytesPerSample), to: &header)
        Self.appendLE(UInt16(32), to: &header)
        header.append("data".data(using: .ascii)!)
        Self.appendLE(UInt32(dataSize), to: &header)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }

        fh.write(header)

        let chunkSize = 24000  // write 1 second at a time
        let silence = [Float](repeating: 0, count: chunkSize)
        var written = 0

        while written < totalSamples {
            let remaining = totalSamples - written
            let count = min(chunkSize, remaining)

            // Determine overlap with the audio region [audioStartSample ..< audioStartSample + audioCopyCount]
            let regionEnd = audioStartSample + audioCopyCount
            let chunkStart = written
            let chunkEnd = written + count

            if chunkEnd <= audioStartSample || chunkStart >= regionEnd {
                // Entirely silence
                silence.withUnsafeBufferPointer { buf in
                    fh.write(Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: buf.baseAddress!),
                                  count: count * bytesPerSample, deallocator: .none))
                }
            } else {
                // Partial or full overlap — build chunk
                var chunk = [Float](repeating: 0, count: count)
                let overlapStart = max(chunkStart, audioStartSample)
                let overlapEnd = min(chunkEnd, regionEnd)
                let srcOffset = overlapStart - audioStartSample
                let dstOffset = overlapStart - chunkStart
                let copyLen = overlapEnd - overlapStart
                for i in 0..<copyLen {
                    chunk[dstOffset + i] = audioSamples[srcOffset + i]
                }
                chunk.withUnsafeBufferPointer { buf in
                    fh.write(Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: buf.baseAddress!),
                                  count: count * bytesPerSample, deallocator: .none))
                }
            }
            written += count
        }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Convert WAV data to M4A format.
    private static func convertWAVToM4A(wavData: Data, outputURL: URL) async throws {
        let tempWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try wavData.write(to: tempWAV)
        defer { try? FileManager.default.removeItem(at: tempWAV) }
        try await convertWAVFileToM4A(wavURL: tempWAV, outputURL: outputURL)
    }

    /// Convert a WAV file on disk to M4A format without loading it into memory.
    private static func convertWAVFileToM4A(wavURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: wavURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioExporterError.exportSessionUnavailable
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw AudioExporterError.exportFailed(error.localizedDescription)
        }
    }
}
