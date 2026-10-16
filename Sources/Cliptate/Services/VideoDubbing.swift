import AVFoundation
import CliptateCore
import CryptoKit
import Foundation

struct DubbingAudio: Sendable {
  let samples: [Float]
  let sampleRate: Int

  var containsSpeech: Bool {
    guard sampleRate > 0, !samples.isEmpty else { return false }
    let window = max(1, sampleRate / 50)
    let minimumAudible = min(Int(Double(sampleRate) * 0.12), max(1, samples.count / 2))
    var audible = 0
    var start = 0
    while start < samples.count {
      let end = min(start + window, samples.count)
      var energy: Double = 0
      for index in start..<end { energy += Double(samples[index]) * Double(samples[index]) }
      if energy / Double(end - start) >= 0.002 * 0.002 { audible += end - start }
      if audible >= minimumAudible { return true }
      start = end
    }
    return false
  }

  func trimmingDecoderSilence() -> Self {
    guard sampleRate > 0 else { return self }
    let window = max(1, sampleRate / 50)
    var audible: [Range<Int>] = []
    var start = 0
    while start < samples.count {
      let end = min(start + window, samples.count)
      var energy: Double = 0
      for index in start..<end { energy += Double(samples[index]) * Double(samples[index]) }
      if energy / Double(end - start) >= 0.002 * 0.002 { audible.append(start..<end) }
      start = end
    }
    guard !audible.isEmpty else { return self }
    var first = 0
    // A decoder startup click can precede speech by seconds. Keep normal speech pauses.
    if audible[0].lowerBound < sampleRate / 10 {
      for index in audible.indices.dropFirst() {
        guard index * window <= Int(Double(sampleRate) * 0.12) else { break }
        if audible[index].lowerBound - audible[index - 1].upperBound
          > Int(Double(sampleRate) * 0.75)
        {
          first = index
          break
        }
      }
    }
    let lower = max(0, audible[first].lowerBound - sampleRate / 50)
    let upper = min(
      samples.count, audible[audible.count - 1].upperBound + Int(Double(sampleRate) * 0.12))
    return Self(samples: Array(samples[lower..<upper]), sampleRate: sampleRate)
  }

  static func read(from url: URL) throws -> Self {
    let file = try AVAudioFile(forReading: url)
    guard file.processingFormat.channelCount == 1, file.length > 0,
      file.length <= Int64(UInt32.max)
    else { throw MLXTTSError.audioConversionFailed }
    var samples: [Float] = []
    samples.reserveCapacity(Int(file.length))
    while file.framePosition < file.length {
      try Task.checkCancellation()
      let count = AVAudioFrameCount(min(24_000, file.length - file.framePosition))
      guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)
      else {
        throw MLXTTSError.audioConversionFailed
      }
      try file.read(into: buffer, frameCount: count)
      guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else {
        throw MLXTTSError.audioConversionFailed
      }
      samples.append(
        contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
    return Self(samples: samples, sampleRate: Int(file.fileFormat.sampleRate))
  }
}

struct DubbingSynthesisRequest {
  let model: MLXTTSModelDefinition
  let language: String

  init(model: MLXTTSModelDefinition, languageCode: String) {
    self.model = model
    self.language =
      ["en": "english", "zh": "chinese", "ja": "japanese", "ko": "korean"][languageCode]
      ?? languageCode
  }
}

struct VideoDubbingRequest {
  let sourceMediaURL: URL
  let segments: [Segment]
  let totalDuration: TimeInterval
  let filterSilentSegments: Bool
  let model: MLXTTSModelDefinition
  let language: String
  var referenceAudioURL: URL? = nil
  var referenceText: String? = nil
  let assetDirectory: URL
  var referenceSegments: [Segment] = []

  var voiceReferenceSegment: Segment? {
    (referenceSegments.isEmpty ? segments : referenceSegments)
      .filter {
        $0.duration >= 1 && $0.duration <= 12
          && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      .sorted {
        $0.duration == $1.duration ? $0.startTime < $1.startTime : $0.duration > $1.duration
      }
      .first
  }
}

struct DubbingPreparation {
  struct Placement {
    let clip: DubbedClip
    let startTime: TimeInterval
    let availableDuration: TimeInterval
  }
  let placements: [Placement]
  let totalDuration: TimeInterval
  var issues: [DubbingIssue] = []
  var clips: [DubbedClip] { placements.map(\.clip) }
}

struct DubbingIssue: Equatable {
  enum Kind: Equatable {
    case overlong, missingTranslation, notGenerated, outdated
    case failed(String)
  }
  let segmentIdentifier: SegmentIdentifier
  let kind: Kind

  var message: String {
    switch kind {
    case .overlong:
      String(localized: "Translation is too long. Shorten it and regenerate this segment.")
    case .missingTranslation: String(localized: "Translate this segment before generating speech.")
    case .notGenerated: String(localized: "Generate this segment to prepare the dubbed video.")
    case .outdated: String(localized: "Speech is out of date. Regenerate this segment.")
    case .failed(let message): message
    }
  }
}

enum VideoDubbingError: LocalizedError {
  case incomplete
  case referenceUnavailable
  case busy
  case noSpeech

  var errorDescription: String? {
    switch self {
    case .incomplete: String(localized: "Resolve the marked dubbing segments before exporting.")
    case .referenceUnavailable:
      String(
        localized:
          "No suitable voice reference was found. Select custom reference audio in Dubbing settings."
      )
    case .busy:
      String(
        localized: "Another dubbing task is running. Wait for it to finish or cancel it first.")
    case .noSpeech:
      String(
        localized:
          "The model produced no audible speech. Regenerate or choose another model or voice reference."
      )
    }
  }
}

extension DubbingRuntime {
  func prepareClips(
    request: VideoDubbingRequest, cachedClips: [DubbedClip],
    generating: Set<SegmentIdentifier>?,
    beforeSynthesis: () async throws -> Void,
    onClip: (DubbedClip) -> Void
  ) async throws -> DubbingPreparation {
    try Task.checkCancellation()
    guard !request.segments.isEmpty else { throw DubbingService.DubbingError.noSegments }
    guard request.totalDuration.isFinite, request.totalDuration > 0,
      request.segments.allSatisfy({
        $0.startTime.isFinite && $0.endTime.isFinite && $0.startTime >= 0
          && $0.endTime > $0.startTime && $0.endTime <= request.totalDuration + 0.001
      })
    else { throw VideoDubbingError.incomplete }
    guard DubbingService.supportedTTSLanguages.contains(request.language) else {
      throw DubbingService.DubbingError.ttsLanguageUnsupported(request.language)
    }
    let sourceSegments = request.segments.sorted { $0.startTime < $1.startTime }
    let synthesisRequest = DubbingSynthesisRequest(
      model: request.model, languageCode: request.language)
    guard Set(sourceSegments.map { SegmentIdentifier(segment: $0) }).count == sourceSegments.count
    else {
      throw VideoDubbingError.incomplete
    }
    let timeline = SegmentTimeline.prepare(
      segments: sourceSegments, filterSilentSegments: request.filterSilentSegments)
    let duration =
      request.filterSilentSegments
      ? (timeline.segments.last?.endTime ?? 0) : request.totalDuration
    try FileManager.default.createDirectory(
      at: request.assetDirectory, withIntermediateDirectories: true)
    var placements: [DubbingPreparation.Placement] = []
    var issues: [DubbingIssue] = []
    var referenceURL = request.referenceAudioURL
    var referenceText = request.referenceText
    var extractedReferenceURL: URL?
    defer {
      if let extractedReferenceURL {
        try? FileManager.default.removeItem(at: extractedReferenceURL)
      }
    }
    let sourceAccess = request.sourceMediaURL.startAccessingSecurityScopedResource()
    let referenceAccess = referenceURL?.startAccessingSecurityScopedResource() ?? false
    defer {
      if sourceAccess { request.sourceMediaURL.stopAccessingSecurityScopedResource() }
      if referenceAccess { request.referenceAudioURL?.stopAccessingSecurityScopedResource() }
    }
    for (index, segment) in timeline.segments.enumerated() {
      try Task.checkCancellation()
      let identifier = SegmentIdentifier(segment: sourceSegments[index])
      guard segment.translation?.language.rawValue == request.language,
        let text = segment.translation?.text,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        issues.append(.init(segmentIdentifier: identifier, kind: .missingTranslation))
        continue
      }
      let fingerprint = try fingerprint(for: sourceSegments[index], request: request)
      let clip: DubbedClip
      let matchingClips = cachedClips.filter {
        $0.fingerprint == fingerprint && FileManager.default.fileExists(atPath: $0.audioURL.path)
      }
      if let cached = matchingClips.first(where: { $0.segmentIdentifier == identifier })
        ?? matchingClips.first,
        generating?.contains(identifier) != true
      {
        clip = DubbedClip(
          segmentIdentifier: identifier, fingerprint: fingerprint,
          audioURL: cached.audioURL, duration: cached.duration, sampleRate: cached.sampleRate)
      } else {
        if let generating, !generating.contains(identifier) {
          let kind: DubbingIssue.Kind =
            cachedClips.contains { $0.segmentIdentifier == identifier } ? .outdated : .notGenerated
          issues.append(.init(segmentIdentifier: identifier, kind: kind))
          continue
        }
        do {
          if referenceURL == nil {
            guard let segment = request.voiceReferenceSegment else {
              throw VideoDubbingError.referenceUnavailable
            }
            let range = CMTimeRange(
              start: CMTime(seconds: segment.startTime, preferredTimescale: 60_000),
              duration: CMTime(seconds: segment.duration, preferredTimescale: 60_000))
            let samples = try await AudioProcessor.loadAndConvertAudio(
              url: request.sourceMediaURL, timeRange: range)
            guard !samples.isEmpty else { throw VideoDubbingError.referenceUnavailable }
            let url = try AudioProcessor.saveSegmentToTemporaryFile(samples: samples)
            referenceURL = url
            extractedReferenceURL = url
            referenceText = segment.text
          }
          try await beforeSynthesis()
          try Task.checkCancellation()
          let generated = try await synthesize(text, synthesisRequest, referenceURL, referenceText)
          try Task.checkCancellation()
          guard !generated.samples.isEmpty, generated.sampleRate > 0,
            generated.samples.allSatisfy(\.isFinite)
          else { throw MLXTTSError.audioConversionFailed }
          guard generated.containsSpeech else { throw VideoDubbingError.noSpeech }
          let audio = generated.trimmingDecoderSilence()
          let url = request.assetDirectory.appendingPathComponent("\(UUID().uuidString).wav")
          try MLXTTSService.createWAVData(from: audio.samples, sampleRate: audio.sampleRate).write(
            to: url, options: .atomic)
          clip = DubbedClip(
            segmentIdentifier: identifier, fingerprint: fingerprint,
            audioURL: url, duration: Double(audio.samples.count) / Double(audio.sampleRate),
            sampleRate: audio.sampleRate)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          try Task.checkCancellation()
          issues.append(
            .init(segmentIdentifier: identifier, kind: .failed(error.localizedDescription)))
          continue
        }
      }
      onClip(clip)
      let nextStart =
        index + 1 < timeline.segments.count ? timeline.segments[index + 1].startTime : duration
      placements.append(
        .init(
          clip: clip, startTime: segment.startTime, availableDuration: nextStart - segment.startTime
        ))
    }
    for placement in placements {
      if placement.clip.duration > placement.availableDuration
        * Double(AudioTimeStretcher.maxSpeedupFactor)
      {
        issues.append(.init(segmentIdentifier: placement.clip.segmentIdentifier, kind: .overlong))
      }
    }
    return DubbingPreparation(placements: placements, totalDuration: duration, issues: issues)
  }

  func fingerprint(for segment: Segment, request: VideoDubbingRequest) throws -> String {
    func fileIdentity(_ url: URL) -> String {
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return
        "\(url.standardizedFileURL.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }
    let reference =
      request.referenceAudioURL.map(fileIdentity)
      ?? request.voiceReferenceSegment.map { "\($0.startTime)|\($0.endTime)|\($0.text)" } ?? ""
    let fields = [
      "video-dubbing-v4-mlx-audio-0.1.5", fileIdentity(request.sourceMediaURL),
      segment.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      request.language, request.model.huggingFaceRepo, reference, request.referenceText ?? "",
    ]
    return SHA256.hash(data: try JSONEncoder().encode(fields)).map { String(format: "%02x", $0) }
      .joined()
  }

  func exportAudio(_ preparation: DubbingPreparation, to outputURL: URL, format: AudioExportFormat)
    async throws
  {
    try Task.checkCancellation()
    guard preparation.issues.isEmpty, !preparation.placements.isEmpty else {
      throw VideoDubbingError.incomplete
    }
    guard preparation.totalDuration.isFinite, preparation.totalDuration > 0,
      preparation.placements.allSatisfy({
        $0.startTime.isFinite && $0.startTime >= 0 && $0.availableDuration.isFinite
          && $0.availableDuration > 0
          && $0.startTime + $0.availableDuration <= preparation.totalDuration + 0.001
          && $0.clip.duration <= $0.availableDuration * Double(AudioTimeStretcher.maxSpeedupFactor)
      })
    else { throw VideoDubbingError.incomplete }
    let staging = outputURL.deletingLastPathComponent().appendingPathComponent(
      "\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: staging) }
    let sampleRate = preparation.clips[0].sampleRate
    guard preparation.clips.allSatisfy({ $0.sampleRate == sampleRate }),
      let audioFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)
    else { throw MLXTTSError.audioConversionFailed }
    do {
      let file = try AVAudioFile(forWriting: staging, settings: audioFormat.settings)
      var cursor = 0
      func write(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        let buffer = AVAudioPCMBuffer(
          pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
          buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        cursor += samples.count
      }
      func silence(until target: Int) throws {
        while cursor < target {
          try Task.checkCancellation()
          try write([Float](repeating: 0, count: min(24_000, target - cursor)))
        }
      }
      for placement in preparation.placements {
        try Task.checkCancellation()
        try silence(until: Int((placement.startTime * Double(sampleRate)).rounded()))
        let audio = try DubbingAudio.read(from: placement.clip.audioURL)
        guard audio.sampleRate == sampleRate,
          abs(Double(audio.samples.count) / Double(sampleRate) - placement.clip.duration) < 0.001
        else { throw MLXTTSError.audioConversionFailed }
        try write(
          AudioTimeStretcher.stretchToFit(
            samples: audio.samples, sampleRate: sampleRate,
            targetDuration: placement.availableDuration))
      }
      try silence(until: Int((preparation.totalDuration * Double(sampleRate)).rounded()))
    }
    try Task.checkCancellation()
    if format == .wav {
      try FileManager.default.replaceOrMoveFile(at: staging, to: outputURL)
    } else {
      let asset = AVURLAsset(url: staging)
      guard
        let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
      else {
        throw MLXTTSError.audioConversionFailed
      }
      let encoded = outputURL.deletingLastPathComponent().appendingPathComponent(
        "\(UUID().uuidString).m4a")
      defer { try? FileManager.default.removeItem(at: encoded) }
      try await session.export(to: encoded, as: .m4a)
      try Task.checkCancellation()
      try FileManager.default.replaceOrMoveFile(at: encoded, to: outputURL)
    }
  }
}

extension FileManager {
  func replaceOrMoveFile(at source: URL, to destination: URL) throws {
    if fileExists(atPath: destination.path) {
      _ = try replaceItemAt(destination, withItemAt: source)
    } else {
      try moveItem(at: source, to: destination)
    }
  }
}
