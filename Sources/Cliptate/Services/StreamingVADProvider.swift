import Foundation

/// Abstracts the streaming VAD component injected into streaming ASR modules.
///
/// The protocol lets `TranscriptionPipelineFactory` create a concrete
/// `SortformerStreamingVADModule` and hand it to any streaming provider
/// without coupling the module implementations to the concrete type.
protocol StreamingVADProvider: Sendable {
  func start(model: ModelVariant) async throws
  func stop() async
  func feed(samples: [Float]) async throws -> SortformerSpeechActivity
}

/// `SortformerStreamingVADModule` is an actor whose method signatures
/// match the protocol exactly, so conformance requires no extra glue.
extension SortformerStreamingVADModule: StreamingVADProvider {}
