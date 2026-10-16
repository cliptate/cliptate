import AVFoundation
import AVKit
import AppKit
import CliptateCore
import SwiftUI
import UniformTypeIdentifiers

struct VideoDubbingEditor: View {
  @EnvironmentObject private var config: AppConfiguration
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var videoState: VideoState
  let sourceURL: URL
  let isTranslating: Bool
  let translationStatus: String
  let onTranslate: () -> Void
  let onSegmentDelete: (Segment) -> Void
  let onChanged: () -> Void

  @State private var preparation: DubbingPreparation?
  @State private var operation: Task<Void, Never>?
  @State private var activity: String?
  @State private var errorMessage: String?
  @State private var notice: String?
  @State private var generationErrors: [SegmentIdentifier: String] = [:]
  @State private var player: AVPlayer?
  @State private var previewIsAudioOnly = false
  @State private var previewFiles: [URL] = []
  @State private var settingsExpanded = false
  @State private var showTranslationStatus = false
  private let runtime = DubbingRuntime.shared

  private var segments: [Segment] {
    SegmentComputer.compute(
      .init(
        segments: videoState.segments,
        totalDuration: videoState.audioDuration ?? videoState.segments.last?.endTime ?? 0,
        filterSilent: config.filterSilent, splitBySentence: config.splitBySentence,
        maxCharsPerSegment: config.maxCharsPerSegment, leftPadMs: config.leftPadMs,
        rightPadMs: config.rightPadMs,
        effectFilterFillerWords: config.effectFilterFillerWords,
        fillerWords: config.effectFillerWords,
        dictionaryEntries: config.voiceToTextCustomDictionary,
        removedSegmentIDs: videoState.removedProcessedSegmentIDs,
        processedTranslations: videoState.processedTranslations)
    ).sorted { $0.startTime < $1.startTime }
  }

  private var settingsSignature: String {
    "\(config.ttsMLXModelId)|\(config.translationTargetLanguage.rawValue)|\(config.dubbingVoiceReferenceMode.rawValue)|\(config.ttsReferenceAudioPath)|\(config.ttsReferenceText)|\(config.ttsReferenceAudioBookmark?.hashValue ?? 0)|\(config.filterSilent)"
  }

  private var segmentSignature: String {
    segments.map { "\($0.id)|\($0.startTime)|\($0.endTime)|\($0.translation?.text ?? "")" }.joined(
      separator: "\n")
  }

  private var inspectionSignature: String {
    settingsSignature + segmentSignature
      + videoState.dubbedClips.map { "\($0.fingerprint)|\($0.audioURL)|\($0.duration)" }.joined()
  }

  private var isBusy: Bool { operation != nil || isTranslating }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Video Dubbing").font(.title2.weight(.semibold))
          Text(sourceURL.lastPathComponent).lineLimit(1).truncationMode(.middle)
        }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }

      Toggle("Use dubbing for video and audio exports", isOn: $config.audioDubbingEnabled)
      Text("Dubbing replaces all original audio, including music and background sound.")
        .font(.callout)

      HStack {
        Picker(
          "Model",
          selection: Binding(
            get: {
              runtime.resolveVoiceCloneModel(preferredRepo: config.ttsMLXModelId)?.huggingFaceRepo
                ?? config.ttsMLXModelId
            },
            set: { config.ttsMLXModelId = $0 })
        ) {
          ForEach(
            MLXTTSModelDefinition.availableModels.filter(\.supportsVoiceClone),
            id: \.huggingFaceRepo
          ) { model in
            Text(model.displayName).tag(model.huggingFaceRepo)
          }
        }
        .frame(maxWidth: 430)
        Spacer()
        Picker("Target Language", selection: $config.translationTargetLanguage) {
          ForEach(
            Language.translationSupported.filter {
              DubbingService.supportedTTSLanguages.contains($0.rawValue)
            }
          ) { language in
            Text(language.displayName).tag(language)
          }
          if !DubbingService.supportedTTSLanguages.contains(
            config.translationTargetLanguage.rawValue)
          {
            Text(config.translationTargetLanguage.displayName).tag(config.translationTargetLanguage)
          }
        }
        .frame(maxWidth: 230)
      }
      .disabled(isBusy)

      DisclosureGroup("Dubbing settings", isExpanded: $settingsExpanded) {
        ScrollView { EditorDubbingOptions(showEnableToggle: false).padding(.vertical, 8) }
          .frame(maxHeight: 190)
          .disabled(isBusy)
      }

      if let player {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            previewIsAudioOnly
              ? String(localized: "Audio preview") : String(localized: "Dubbed video preview")
          )
          .font(.caption)
          VideoPlayer(player: player).frame(height: previewIsAudioOnly ? 70 : 200)
        }
      }

      HStack {
        Button("Translate") {
          showTranslationStatus = true
          onTranslate()
        }.disabled(isBusy)
        Button("Generate missing or changed segments") { generate() }.disabled(
          isBusy || segments.isEmpty)
        Spacer()
        if let activity { Text(activity).font(.callout) }
        if operation != nil || isTranslating {
          ProgressView().controlSize(.small)
        }
        if operation != nil {
          Button("Cancel") { operation?.cancel() }
        }
      }

      if showTranslationStatus { Text(translationStatus).font(.callout).textSelection(.enabled) }

      if let errorMessage {
        Text(errorMessage).foregroundStyle(.primary).textSelection(.enabled)
          .accessibilityLabel(String(localized: "Dubbing error") + ": " + errorMessage)
      }
      if let notice { Text(notice).font(.callout) }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if segments.isEmpty {
            Text("Transcribe the video before preparing dubbing.")
          }
          ForEach(segments) { segment in
            segmentRow(segment)
            Divider()
          }
        }
        .padding(.vertical, 4)
      }
      .frame(minHeight: 180)

      HStack {
        Text("Shorten marked translations to fit the video. Speech is never cut off to fit.")
          .font(.callout).fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button("Export dubbed video…") { chooseExport() }
          .disabled(isBusy || preparation == nil || preparation?.issues.isEmpty != true)
      }
    }
    .padding(20)
    .frame(minWidth: 720, idealWidth: 820, maxWidth: 1_000, minHeight: 600, idealHeight: 780)
    .task(id: inspectionSignature) {
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      do {
        preparation = try await runtime.prepare(
          request: makeRequest(), cachedClips: videoState.dubbedClips, generating: [])
      } catch is CancellationError {
      } catch {
        preparation = nil
        errorMessage = error.localizedDescription
      }
      onChanged()
    }
    .onChange(of: settingsSignature) { _, _ in invalidatePreview() }
    .onChange(of: segmentSignature) { _, _ in invalidatePreview() }
    .onDisappear {
      operation?.cancel()
      player?.pause()
      player?.replaceCurrentItem(with: nil)
      for url in previewFiles { try? FileManager.default.removeItem(at: url) }
      onChanged()
    }
  }

  private func segmentRow(_ segment: Segment) -> some View {
    let identifier = SegmentIdentifier(segment: segment)
    let placement = preparation?.placements.first { $0.clip.segmentIdentifier == identifier }
    let issue = preparation?.issues.first { $0.segmentIdentifier == identifier }
    let hasRetainedAudio = videoState.dubbedClips.contains { $0.segmentIdentifier == identifier }
    return VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: String(format: "%.2f – %.2f", segment.startTime, segment.endTime))
        .font(.caption.monospacedDigit())
      Text(segment.text).font(.callout).textSelection(.enabled)
      TextField(
        "Translation",
        text: Binding(
          get: {
            videoState.processedTranslations[segment.id]?.text ?? segment.translation?.text ?? ""
          },
          set: { text in
            videoState.processedTranslations[segment.id] = SegmentTranslation(
              text: text, language: config.translationTargetLanguage)
            videoState.lastTranslatedLanguage = config.translationTargetLanguage
          }), axis: .vertical
      )
      .textFieldStyle(.roundedBorder).lineLimit(1...5).disabled(isBusy)
      .accessibilityLabel(String(localized: "Translation") + ": " + segment.text)
      .accessibilityIdentifier("dubbing.translation.\(segment.id)")
      HStack {
        Button(hasRetainedAudio ? String(localized: "Regenerate") : String(localized: "Generate")) {
          generate(only: identifier)
        }
        .accessibilityIdentifier("dubbing.generate.\(segment.id)")
        .accessibilityLabel(
          (hasRetainedAudio ? String(localized: "Regenerate") : String(localized: "Generate"))
            + ": " + segment.text
        )
        .disabled(
          isBusy
            || segment.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              != false
        )
        Button("Preview") { preview(segment) }.disabled(isBusy || placement == nil)
          .accessibilityIdentifier("dubbing.preview.\(segment.id)")
          .accessibilityLabel(String(localized: "Preview") + ": " + segment.text)
        Button("Delete", role: .destructive) { onSegmentDelete(segment) }
          .disabled(isBusy)
          .accessibilityIdentifier("dubbing.delete.\(segment.id)")
          .accessibilityLabel(String(localized: "Delete") + ": " + segment.text)
        if let message = generationErrors[identifier] ?? issue?.message {
          Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
        } else if placement != nil {
          Text("Ready to preview").font(.callout)
        }
      }
    }
  }

  private func makeRequest() throws -> VideoDubbingRequest {
    try .make(sourceURL: sourceURL, state: videoState, segments: segments, configuration: config)
  }

  private func invalidatePreview() {
    operation?.cancel()
    player?.pause()
    player = nil
    preparation = nil
    generationErrors = [:]
    errorMessage = nil
    notice = nil
  }

  private func generate(only identifier: SegmentIdentifier? = nil) {
    guard !isBusy else { return }
    operation = Task { @MainActor in
      activity = String(localized: "Preparing dubbing…")
      showTranslationStatus = false
      errorMessage = nil
      notice = nil
      defer {
        operation = nil
        activity = nil
      }
      do {
        let request = try makeRequest()
        let result = try await runtime.prepare(
          request: request, cachedClips: videoState.dubbedClips,
          generating: identifier.map { Set([$0]) },
          onClip: { clip in
            videoState.retainDubbedClip(clip)
            onChanged()
          })
        try Task.checkCancellation()
        preparation = result
        generationErrors = Dictionary(
          uniqueKeysWithValues: result.issues.compactMap { issue in
            if case .failed = issue.kind { return (issue.segmentIdentifier, issue.message) }
            return nil
          })
      } catch is CancellationError {
        errorMessage = String(localized: "Dubbing cancelled. Completed segments are retained.")
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func preview(_ segment: Segment) {
    guard
      let placement = preparation?.placements.first(where: {
        $0.clip.segmentIdentifier == SegmentIdentifier(segment: segment)
      })
    else { return }
    operation = Task { @MainActor in
      defer {
        operation = nil
        activity = nil
      }
      do {
        player?.pause()
        if placement.clip.duration > placement.availableDuration
          * Double(AudioTimeStretcher.maxSpeedupFactor)
        {
          player = AVPlayer(url: placement.clip.audioURL)
          previewIsAudioOnly = true
        } else {
          let duration = min(
            placement.availableDuration, max(segment.duration, placement.clip.duration) + 0.5)
          let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).wav")
          previewFiles.append(url)
          let excerpt = DubbingPreparation(
            placements: [.init(clip: placement.clip, startTime: 0, availableDuration: duration)],
            totalDuration: duration)
          try await runtime.exportAudio(excerpt, to: url, format: .wav)
          let (asset, _) = try await VideoCompositionBuilder.build(
            asset: AVURLAsset(url: sourceURL), ass: nil, filterSilentSegments: true,
            segments: [
              Segment(
                startTime: segment.startTime, endTime: segment.startTime + duration,
                text: segment.text)
            ],
            dubbedAudioURL: url)
          try Task.checkCancellation()
          player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
          previewIsAudioOnly = false
        }
        player?.play()
      } catch is CancellationError {
      } catch { errorMessage = error.localizedDescription }
    }
  }

  private func chooseExport() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.mpeg4Movie]
    panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + "_dubbed.mp4"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      operation = Task { @MainActor in
        activity = String(localized: "Exporting dubbed video…")
        defer {
          operation = nil
          activity = nil
        }
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(
          "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        do {
          let request = try makeRequest()
          let prepared = try await runtime.prepare(
            request: request, cachedClips: videoState.dubbedClips, generating: [])
          try await runtime.exportAudio(prepared, to: audioURL, format: .wav)
          try await VideoExporter().exportVideoWithSubtitles(
            videoURL: sourceURL,
            segments: ExportTextNormalizer.normalize(
              segments: request.segments, keepPunctuation: config.keepPunctuationOnExport),
            outputURL: url, filterSilentSegments: request.filterSilentSegments,
            effects: videoState.segmentEffects.adjusted(for: config.effectConfiguration),
            translationPlacement: config.translationPlacement,
            styleConfiguration: config.subtitleStyles,
            dubbedAudioURL: audioURL, burnInSubtitles: config.videoExportBurnInSubtitles,
            quality: config.videoExportQuality)
          notice = String(localized: "Dubbed video exported.")
          NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch is CancellationError {
          errorMessage = String(localized: "Export cancelled")
        } catch { errorMessage = error.localizedDescription }
      }
    }
  }
}
