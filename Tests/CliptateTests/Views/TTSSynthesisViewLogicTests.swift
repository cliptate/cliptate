import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("TTS synthesis view logic")
struct TTSSynthesisViewLogicTests {
  @Test("speech duration estimate counts CJK characters without whitespace")
  func speechDurationEstimateCountsCJKCharacters() {
    let estimate = TTSScriptMetrics.estimatedSpeechDuration(for: "这是一个中文测试")
    #expect(estimate > 1.0)
  }

  @Test("speech duration estimate combines Latin words and CJK characters")
  func speechDurationEstimateCombinesLatinAndCJK() {
    let mixed = TTSScriptMetrics.estimatedSpeechDuration(for: "Hello 世界 こんにちは")
    let latinOnly = TTSScriptMetrics.estimatedSpeechDuration(for: "Hello there")

    #expect(mixed > latinOnly)
  }

  @Test("dropped reference audio supports plain file paths")
  func droppedReferenceAudioSupportsPlainFilePaths() {
    let url = TTSSynthesisReferenceAudioDrop.fileURL(fromDroppedItem: "/tmp/reference.wav")

    #expect(url?.isFileURL == true)
    #expect(url?.path == "/tmp/reference.wav")
  }

  @Test("view source rebuilds playback from stored synthesized audio")
  func viewSourceRebuildsPlaybackFromStoredAudio() throws {
    let content = try ttsSynthesisViewSource()

    #expect(content.contains("if audioPlayer == nil, let data = synthesizedAudio"))
    #expect(content.contains("preparePlayback(with: data)"))
  }

  @Test("view source wires cancellable synthesis task")
  func viewSourceWiresCancellation() throws {
    let content = try ttsSynthesisViewSource()

    #expect(content.contains("@State private var generationTask"))
    #expect(content.contains("generationTask?.cancel()"))
    #expect(content.contains("private func cancelSynthesis()"))
  }

  @Test("voice clone section accepts dropped audio files")
  func voiceCloneSectionAcceptsDroppedAudioFiles() throws {
    let content = try ttsSynthesisViewSource()

    #expect(content.contains("handleDroppedReferenceAudio"))
    #expect(content.contains(".onDrop(of: [UTType.fileURL.identifier, UTType.audio.identifier]"))
    #expect(content.contains("loadInPlaceFileRepresentation(forTypeIdentifier: UTType.audio.identifier"))
  }

  @Test("view source keeps primary button width and adds cancel icon while synthesizing")
  func viewSourceKeepsPrimaryButtonWidthAndAddsCancelIcon() throws {
    let content = try ttsSynthesisViewSource()

    #expect(content.contains("Button(action: { isSynthesizing ? cancelSynthesis() : generateAudio(shouldExport: false) })"))
    #expect(content.contains("Image(systemName: isSynthesizing ? \"xmark\" : \"sparkles\")"))
    #expect(content.contains("isSynthesizing\n                             ? String(localized: \"Synthesizing…\""))
    #expect(content.contains(".frame(minWidth: 100)"))
    #expect(content.contains(".symbolEffect(.pulse.byLayer, options: isSynthesizing ? .repeating : .nonRepeating, value: isSynthesizing)"))
    #expect(content.contains(".tint(isSynthesizing ? .red : .accentColor)"))
  }

  @Test("view source saves TTS history off the main actor")
  func viewSourceSavesHistoryOffMainActor() throws {
    let content = try ttsSynthesisViewSource()

    #expect(content.contains("Task(priority: .utility)"))
    #expect(content.contains("await persistTTSSynthesisHistory"))
    #expect(!content.contains("saveTTSSynthesisToHistory(text: trimmed, audioData: audio)"))
  }

  private func ttsSynthesisViewSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent("Sources/Cliptate/Views/TTSSynthesisView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
