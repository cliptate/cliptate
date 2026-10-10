import AVFoundation
import Foundation
import Testing

@testable import Cliptate

@Suite("TranscriptionPipelineFactory")
struct TranscriptionPipelineFactoryTests {

  // MARK: - makeVADProvider

  @Test("makeVADProvider returns SortformerVADProvider by default (no vadModel)")
  func makeVADProviderReturnsSortformerProvider() {
    let provider = TranscriptionPipelineFactory.makeVADProvider()
    #expect(provider is SortformerVADProvider)
  }

  @Test("makeVADProvider returns SileroVADProvider when Silero model is specified")
  func makeVADProviderReturnsSileroProvider() {
    let provider = TranscriptionPipelineFactory.makeVADProvider(vadModel: .sileroVAD)
    #expect(provider is SileroVADProvider)
  }

  @Test("makeVADProvider returns SortformerVADProvider when Sortformer model is specified")
  func makeVADProviderReturnsSortformerForSortformerModel() {
    let provider = TranscriptionPipelineFactory.makeVADProvider(vadModel: .sortformerStreaming)
    #expect(provider is SortformerVADProvider)
  }

  // MARK: - makeASRChunkProvider

  @Test("makeASRChunkProvider returns Qwen3 provider for Qwen3 transcriber")
  func makeASRChunkProviderReturnsQwen3ForQwen3Transcriber() {
    let transcriber = Qwen3ASRTranscriber(model: .qwen3ASR)
    let provider = TranscriptionPipelineFactory.makeASRChunkProvider(
      transcriber: transcriber, dictionaryContext: "custom")
    #expect(provider is Qwen3ASRChunkProvider)
  }

  @Test("makeASRChunkProvider returns Parakeet provider for Parakeet transcriber")
  func makeASRChunkProviderReturnsParakeetForParakeetTranscriber() {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let provider = TranscriptionPipelineFactory.makeASRChunkProvider(transcriber: transcriber)
    #expect(provider is ParakeetASRChunkProvider)
  }

  @Test("makeASRChunkProvider returns Fallback provider for FireRed transcriber")
  func makeASRChunkProviderReturnsFallbackForFireRedTranscriber() {
    let transcriber = FireRedASRTranscriber()
    let provider = TranscriptionPipelineFactory.makeASRChunkProvider(transcriber: transcriber)
    #expect(provider is FallbackASRChunkProvider)
  }

  // MARK: - makeBatchPipeline

  @Test("makeBatchPipeline wires correct provider types")
  func makeBatchPipelineCreatesCorrectProviders() {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let aligner = Qwen3ForcedAlignerTranscriber(model: .qwen3ForcedAligner)
    let pipeline = TranscriptionPipelineFactory.makeBatchPipeline(
      transcriber: transcriber, aligner: aligner)
    #expect(pipeline.vad is SortformerVADProvider)
    #expect(pipeline.asr is ParakeetASRChunkProvider)
    #expect(pipeline.align is Qwen3AlignChunkProvider)
  }

  @Test("makeBatchPipeline uses SileroVADProvider when silero vadModel is given")
  func makeBatchPipelineUsesSileroWhenSpecified() {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let aligner = Qwen3ForcedAlignerTranscriber(model: .qwen3ForcedAligner)
    let pipeline = TranscriptionPipelineFactory.makeBatchPipeline(
      transcriber: transcriber, aligner: aligner, vadModel: .sileroVAD)
    #expect(pipeline.vad is SileroVADProvider)
  }

  @Test("makeBatchPipeline passes dictionary context to Qwen3 ASR provider")
  func makeBatchPipelinePassesDictionaryContextToQwen3() {
    let transcriber = Qwen3ASRTranscriber(model: .qwen3ASR)
    let aligner = Qwen3ForcedAlignerTranscriber(model: .qwen3ForcedAligner)
    let pipeline = TranscriptionPipelineFactory.makeBatchPipeline(
      transcriber: transcriber, aligner: aligner, dictionaryContext: "ctx")
    guard let qwen3Provider = pipeline.asr as? Qwen3ASRChunkProvider else {
      Issue.record("Expected Qwen3ASRChunkProvider")
      return
    }
    #expect(qwen3Provider.dictionaryContext == "ctx")
  }

  @Test("makeBatchPlan omits align stage when no aligner is provided")
  func makeBatchPlanOmitsAlignWhenUnavailable() {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let plan = TranscriptionPipelineFactory.makeBatchPlan(
      transcriber: transcriber,
      aligner: nil,
      dictionaryContext: nil,
      vadModel: .sileroVAD
    )
    #expect(plan.vad is SileroVADProvider)
    #expect(plan.asr is ParakeetASRChunkProvider)
    #expect(plan.align == nil)
  }

  @Test("dictation workflows disable alignment explicitly")
  func dictationWorkflowDisablesAlignment() {
    #expect(BatchTranscriptionWorkflow.fileTranscription.usesAlignment)
    #expect(BatchTranscriptionWorkflow.dictationFinalization.usesAlignment == false)
    #expect(BatchTranscriptionWorkflow.dictationHistoryReprocessing.usesAlignment == false)
  }

  // MARK: - makeStreamingProvider

  @MainActor
  @Test("makeStreamingProvider returns UnifiedStreamingProvider for FireRed")
  func makeStreamingProviderReturnsProviderForFireRed() throws {
    let transcriber = FireRedASRTranscriber()
    let module = makeStreamingModule()
      let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
        type: .fireRed,
        transcriber: transcriber,
        streamingModule: module,
        vadModel: .sileroVAD
      )
    #expect(provider is UnifiedStreamingProvider)
  }

  @MainActor
  @Test("makeStreamingProvider throws typeMismatch when Qwen3 type receives Parakeet transcriber")
  func makeStreamingProviderThrowsTypeMismatchForWrongType() throws {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let module = makeStreamingModule()
    #expect(throws: (any Error).self) {
        _ = try TranscriptionPipelineFactory.makeStreamingProvider(
          type: .qwen3,
          transcriber: transcriber,
          streamingModule: module,
          vadModel: .sileroVAD
        )
    }
  }

  @MainActor
  @Test("makeStreamingProvider returns UnifiedStreamingProvider for Parakeet")
  func makeStreamingProviderReturnsProviderForParakeet() throws {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let module = makeStreamingModule()
      let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
        type: .parakeet,
        transcriber: transcriber,
        streamingModule: module,
        vadModel: .sileroVAD
      )
    #expect(provider is UnifiedStreamingProvider)
  }

  @MainActor
  @Test("makeStreamingProvider returns UnifiedStreamingProvider for Qwen3")
  func makeStreamingProviderReturnsProviderForQwen3() throws {
    let transcriber = Qwen3ASRTranscriber(model: .qwen3ASR)
    let module = makeStreamingModule()
      let provider = try TranscriptionPipelineFactory.makeStreamingProvider(
        type: .qwen3,
        transcriber: transcriber,
        streamingModule: module,
        vadModel: .sileroVAD
      )
    #expect(provider is UnifiedStreamingProvider)
  }

  @MainActor
  @Test("makeStreamingProvider reuses streaming VAD instance for the same model variant")
  func makeStreamingProviderReusesStreamingVADForSameVariant() throws {
    let first = try #require(
      TranscriptionPipelineFactory.makeStreamingProvider(
        type: .qwen3,
        transcriber: Qwen3ASRTranscriber(model: .qwen3ASR),
        streamingModule: makeStreamingModule(),
        vadModel: .sileroVAD
      ) as? UnifiedStreamingProvider
    )
    let second = try #require(
      TranscriptionPipelineFactory.makeStreamingProvider(
        type: .qwen3,
        transcriber: Qwen3ASRTranscriber(model: .qwen3ASR),
        streamingModule: makeStreamingModule(),
        vadModel: .sileroVAD
      ) as? UnifiedStreamingProvider
    )

    #expect(first.testStreamingVADIdentifier == second.testStreamingVADIdentifier)
  }

  // MARK: - Helpers

  @MainActor
  private func makeStreamingModule() -> StreamingAudioCaptureModule {
    StreamingAudioCaptureModule(
      logger: .init(subsystem: "test", category: "streaming"),
      configuration: .init(chunkDuration: 2.0, levelCalculator: { _ in 0 }),
      callbacks: .init(onAudioLevel: { _ in }, onInterimText: { _ in })
    )
  }
}
