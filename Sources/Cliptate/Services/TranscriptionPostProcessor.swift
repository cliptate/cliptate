import CliptateCore
import Foundation

/// Unified post-ASR processing: dictionary bias → speaker annotation (graceful fallback).
struct TranscriptionPostProcessor {

  struct Result {
    let segments: [Segment]
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
    let speakerAnnotationApplied: Bool
  }

  let speakerPropagation: PlainASRSpeakerPropagation

  /// Post-processes raw ASR output: applies dictionary bias, then speaker annotation.
  /// Speaker annotation failure is gracefully handled — returns unannotated segments.
  func postProcess(
    asrResult: TranscriptionResult,
    sourceURL: URL,
    dictionaryEntries: [String]
  ) async -> Result {
    let biasedSegments = ASRDictionaryBiasService.apply(
      to: asrResult.segments,
      dictionaryEntries: dictionaryEntries
    )

    var finalSegments = biasedSegments
    var speakerApplied = false

    do {
      finalSegments = try await speakerPropagation.annotate(biasedSegments, for: sourceURL)
      speakerApplied = finalSegments.contains(where: { $0.speakerId != nil })
    } catch {
      print("⚠️ Speaker annotation skipped: \(error.localizedDescription)")
    }

    return Result(
      segments: finalSegments,
      audioDuration: asrResult.totalDuration,
      processingTime: asrResult.processingTime,
      speakerAnnotationApplied: speakerApplied
    )
  }

  func postProcess(
    asrResult: TranscriptionResult,
    audioSamples: [Float],
    dictionaryEntries: [String]
  ) async -> Result {
    let biasedSegments = ASRDictionaryBiasService.apply(
      to: asrResult.segments,
      dictionaryEntries: dictionaryEntries
    )

    var finalSegments = biasedSegments
    var speakerApplied = false

    do {
      finalSegments = try await speakerPropagation.annotate(biasedSegments, samples: audioSamples)
      speakerApplied = finalSegments.contains(where: { $0.speakerId != nil })
    } catch {
      print("⚠️ Speaker annotation skipped: \(error.localizedDescription)")
    }

    return Result(
      segments: finalSegments,
      audioDuration: asrResult.totalDuration,
      processingTime: asrResult.processingTime,
      speakerAnnotationApplied: speakerApplied
    )
  }
}
