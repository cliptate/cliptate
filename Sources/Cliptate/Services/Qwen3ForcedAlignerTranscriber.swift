import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import os.log

/// Transcriber that performs forced alignment using a Qwen3ForcedAlignerModel.
///
/// All ASR functionality lives in `Qwen3ASRTranscriber`. This class is the
/// sole owner of the aligner model and exposes the alignment API consumed by
/// `Qwen3AlignChunkProvider` and the segmented-alignment pipeline in AICutView.
public final class Qwen3ForcedAlignerTranscriber: @unchecked Sendable, Transcriber {
  private static let alignmentChunkDuration: Float = 3.0

  private var forcedAlignerModel: Qwen3ForcedAlignerModel?
  private let modelVariant: ModelVariant
  private var isModelReady: Bool = false

  public var model: ModelVariant { modelVariant }

  private let logger = Logger(
    subsystem: "com.cliptate.app", category: "Qwen3ForcedAlignerTranscriber")

  init(model: ModelVariant) {
    self.modelVariant = model
  }

  // MARK: - Lifecycle

  func unload() {
    forcedAlignerModel = nil
    isModelReady = false
  }

  // MARK: - Transcriber Protocol

  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    if isModelReady { return }

    let startTime = Date()
    let modelName = modelVariant.displayName

    do {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Checking \(modelName) availability...",
            progress: 0.05
          ))
      }

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Loading \(modelName) from HuggingFace...",
            progress: 0.2
          ))
      }

      try await ensureMergesFile(for: modelVariant)

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Initializing Qwen3 ForcedAligner model...",
            progress: 0.4
          ))
      }

      let model = try await Qwen3ForcedAlignerModel.fromPretrained(
        modelVariant.huggingFaceRepoId
      )
      forcedAlignerModel = model

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Model weights loaded, preparing for inference...",
            progress: 0.7
          ))
      }

      isModelReady = true
      ModelArtifactStatusNotifier.postChange(for: modelVariant)
      let totalTime = Date().timeIntervalSince(startTime)

      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "\(modelName) ready (\(String(format: "%.1f", totalTime))s)",
            progress: 1.0
          ))
      }

      logger.notice(
        "🤖 ForcedAligner model \(modelName) loaded in \(String(format: "%.1f", totalTime))s")

    } catch {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Failed to load \(modelName): \(error.localizedDescription)",
            progress: 0.0
          ))
      }
      logger.error("🤖 Failed to load ForcedAligner model: \(error.localizedDescription)")
      throw error
    }
  }

  /// Not applicable to a forced-aligner; always throws. Use `alignWithText` instead.
  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    throw NSError(
        domain: "Qwen3ForcedAlignerTranscriber", code: 99,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Use alignWithText instead of transcribeWithProgress on a forced-aligner."
        ])
  }

  // MARK: - Per-Chunk Alignment

  /// Aligns pre-extracted audio samples (16 kHz mono) with provided text.
  ///
  /// Returns word-level timings with 0-based offsets relative to the provided
  /// samples, with punctuation applied. Caller is responsible for rebasing
  /// timings to absolute positions with `rebaseAndBuildSegment`.
  public func alignChunk(samples: [Float], text: String, language: Language) throws -> [WordTiming]
  {
    guard forcedAlignerModel != nil else {
      throw NSError(
        domain: "Qwen3ForcedAligner", code: 8,
        userInfo: [
          NSLocalizedDescriptionKey:
            "ForcedAligner model not initialized. Warm up the model before alignment."
        ])
    }
    let raw = try alignSamples(samples, text: text, language: language)
    return applyPunctuation(from: text, to: raw)
  }

  /// Rebases local (0-based) word timings from a segment audio slice into the
  /// global timeline and builds a Segment. Returns nil if localWords is empty.
  static func rebaseAndBuildSegment(
    asrSegment: Segment,
    localWords: [WordTiming]
  ) -> Segment? {
    guard !localWords.isEmpty else { return nil }
    let rebased = localWords.map { word in
      WordTiming(
        word: word.word,
        startTime: asrSegment.startTime + word.startTime,
        endTime: asrSegment.startTime + word.endTime,
        confidence: word.confidence,
        punctuation: word.punctuation
      )
    }
    guard let first = rebased.first, let last = rebased.last else { return nil }
    let text = WordTimingTextComposer.composeText(from: rebased)
    return Segment(
      startTime: first.startTime,
      endTime: last.endTime,
      text: text.isEmpty ? asrSegment.text : text,
      words: rebased,
      confidence: asrSegment.confidence
    )
  }

  // MARK: - Full-File Alignment

  /// Aligns existing text with audio timestamps using the ForcedAligner model.
  public func alignWithText(
    audioPath: String,
    text: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try Task.checkCancellation()

    guard modelVariant.isQwen3AlignerModel else {
      throw NSError(
        domain: "Qwen3ForcedAligner", code: 6,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Forced alignment requires a Qwen3 ForcedAligner model. Current model: \(modelVariant.displayName)"
        ])
    }

    if !isModelReady {
      try await warmUpModelWithProgress { _ in }
    }

    guard let alignerModel = forcedAlignerModel else {
      throw NSError(
        domain: "Qwen3ForcedAligner", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "ForcedAligner model not initialized. Please warm up the model first."
        ])
    }

    let startTime = Date()
    let audioURL = URL(fileURLWithPath: audioPath)

    let needsStop = audioURL.startAccessingSecurityScopedResource()
    defer { if needsStop { audioURL.stopAccessingSecurityScopedResource() } }

    let asset = AVURLAsset(url: audioURL)
    let assetDuration = try await asset.load(.duration)
    let audioDuration = max(assetDuration.seconds, 0.001)

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [], progress: 0.0,
          statusMessage: "Preparing audio for alignment...", estimatedTimeRemaining: nil))
    }

    let audioSamples = try await AudioProcessor.loadAndConvertAudio(url: audioURL)
    try Task.checkCancellation()

    guard !audioSamples.isEmpty else {
      throw NSError(
        domain: "Qwen3ForcedAligner", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid audio data - empty audio"])
    }

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [], progress: 0.3,
          statusMessage: "Running forced alignment...", estimatedTimeRemaining: nil))
    }

    let audioArray = MLXArray(audioSamples)
    let languageName = language.qwen3LanguageName
    logger.notice("🤖 Starting forced alignment with language: \(languageName)")

    let result = alignerModel.generate(audio: audioArray, text: text, language: languageName)

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [], progress: 0.7,
          statusMessage: "Processing alignment results...", estimatedTimeRemaining: nil))
    }

    var wordTimings: [WordTiming] = []
    for item in result.items {
      wordTimings.append(
        WordTiming(
          word: item.text, startTime: item.startTime, endTime: item.endTime, confidence: nil))
    }
    let punctuatedWordTimings = applyPunctuation(from: text, to: wordTimings)
    let reconstructedText = WordTimingTextComposer.composeText(from: punctuatedWordTimings)

    let singleSegment = Segment(
      startTime: punctuatedWordTimings.first?.startTime ?? 0,
      endTime: punctuatedWordTimings.last?.endTime ?? 0,
      text: reconstructedText.isEmpty ? text : reconstructedText,
      words: punctuatedWordTimings,
      confidence: nil
    )

    let processingTime = Date().timeIntervalSince(startTime)
    logger.notice(
      "🤖 Forced alignment complete: 1 segment, \(punctuatedWordTimings.count) words")

    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [singleSegment], progress: 1.0,
          statusMessage: "Alignment completed", estimatedTimeRemaining: 0))
    }

    return TranscriptionResult(
      segments: [singleSegment],
      totalDuration: audioDuration,
      processingTime: processingTime,
      modelUsed: modelVariant.rawValue
    )
  }

  // MARK: - Private Alignment Helpers

  private func alignSamples(
    _ samples: [Float],
    text: String,
    language: Language
  ) throws -> [WordTiming] {
    guard let alignerModel = forcedAlignerModel else {
      throw NSError(
        domain: "Qwen3ForcedAligner", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "ForcedAligner model not initialized."])
    }
    let audioArray = MLXArray(samples)
    let languageName = language.qwen3LanguageName
    let result = alignerModel.generate(audio: audioArray, text: text, language: languageName)
    return result.items.map { item in
      WordTiming(word: item.text, startTime: item.startTime, endTime: item.endTime, confidence: nil)
    }
  }

  private struct SourceSignificantCharacter {
    let index: String.Index
  }

  private func applyPunctuation(from sourceText: String, to words: [WordTiming]) -> [WordTiming] {
    guard !words.isEmpty else { return [] }

    var sourceSignificant: [SourceSignificantCharacter] = []
    sourceSignificant.reserveCapacity(sourceText.count)
    var currentIndex = sourceText.startIndex
    while currentIndex < sourceText.endIndex {
      let character = sourceText[currentIndex]
      if isAlignmentSignificantCharacter(character) {
        sourceSignificant.append(SourceSignificantCharacter(index: currentIndex))
      }
      currentIndex = sourceText.index(after: currentIndex)
    }

    var tokenRanges: [(start: Int, end: Int)?] = []
    tokenRanges.reserveCapacity(words.count)
    var consumed = 0

    for word in words {
      let tokenLength = word.word.reduce(into: 0) { count, ch in
        if isAlignmentSignificantCharacter(ch) { count += 1 }
      }
      guard tokenLength > 0, consumed < sourceSignificant.count else {
        tokenRanges.append(nil)
        continue
      }
      let start = consumed
      let end = min(sourceSignificant.count - 1, consumed + tokenLength - 1)
      tokenRanges.append((start, end))
      consumed += tokenLength
    }

    func nextTokenStart(after index: Int) -> Int? {
      guard index + 1 < tokenRanges.count else { return nil }
      for idx in (index + 1)..<tokenRanges.count {
        if let range = tokenRanges[idx] { return range.start }
      }
      return nil
    }

    var updated: [WordTiming] = []
    updated.reserveCapacity(words.count)

    for idx in words.indices {
      let word = words[idx]
      var punctuation = ""

      if let range = tokenRanges[idx], range.end < sourceSignificant.count {
        let start = sourceText.index(after: sourceSignificant[range.end].index)
        let end: String.Index
        if let nextStart = nextTokenStart(after: idx), nextStart < sourceSignificant.count {
          end = sourceSignificant[nextStart].index
        } else {
          end = sourceText.endIndex
        }
        if start <= end {
          let between = sourceText[start..<end]
          punctuation = String(
            between.filter { ch in !ch.isWhitespace && !isAlignmentSignificantCharacter(ch) })
        }
      }

      updated.append(
        WordTiming(
          word: word.word, startTime: word.startTime, endTime: word.endTime,
          confidence: word.confidence, punctuation: punctuation))
    }

    return updated
  }

  private func isAlignmentSignificantCharacter(_ character: Character) -> Bool {
    isKeptAlignmentCharacter(character) || isCJKCharacter(character)
  }

  private func isKeptAlignmentCharacter(_ character: Character) -> Bool {
    if character == "'" { return true }
    return character.isLetter || character.isNumber
  }

  private func isCJKCharacter(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    let code = scalar.value
    return (0x4E00...0x9FFF).contains(code)
      || (0x3400...0x4DBF).contains(code)
      || (0x20000...0x2A6DF).contains(code)
      || (0x2A700...0x2B73F).contains(code)
      || (0x2B740...0x2B81F).contains(code)
      || (0x2B820...0x2CEAF).contains(code)
      || (0xF900...0xFAFF).contains(code)
  }

  // MARK: - Model File Fixup

  /// Ensures merges.txt exists in the mlx-audio cache directory.
  ///
  /// mlx-audio's ModelUtils.resolveOrDownloadModel only downloads files matching
  /// `["*.safetensors", "*.json"]`, so `merges.txt` is never downloaded.
  private func ensureMergesFile(for model: ModelVariant) async throws {
    let repoId = model.huggingFaceRepoId
    let modelDir =
      await ModelDownloadManager.shared.getModelDirectory(for: model)
      ?? model.storagePaths().primaryMLXAudioDirectory
      ?? ModelDownloadManager.shared.mlxAudioDirectory(forRepo: repoId)

    let mergesPath = modelDir.appendingPathComponent("merges.txt")
    if FileManager.default.fileExists(atPath: mergesPath.path) {
      logger.debug("🤖 merges.txt already exists at \(mergesPath.path)")
      return
    }

    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    logger.notice("🤖 Downloading missing merges.txt for \(model.displayName) from HuggingFace")

    let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/merges.txt")!
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw NSError(
        domain: "Qwen3ForcedAligner", code: 11,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Failed to download merges.txt for tokenizer generation (HTTP \(statusCode))."
        ])
    }

    try data.write(to: mergesPath)
    logger.notice("🤖 merges.txt written to \(mergesPath.path)")
  }
}
