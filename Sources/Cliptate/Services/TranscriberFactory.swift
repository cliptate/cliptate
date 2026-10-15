import CliptateCore

/// Concrete inference adapters are owned by the application runtime.
extension TranscriberType {
  public func createTranscriber(model: ModelVariant = .parakeetV3) -> Transcriber {
    switch self {
    case .whisper:
      let whisperModel = model.isWhisperModel ? model : .whisperLargeV3Turbo
      return MLXWhisperTranscriber(model: whisperModel)
    case .parakeet:
      let parakeetModel = model.isParakeetModel ? model : .parakeetV2
      return MLXParakeetTranscriber(model: parakeetModel)
    case .qwen3:
      let qwenModel = model.isQwen3Model ? model : .qwen3ASR
      return Qwen3ASRTranscriber(model: qwenModel)
    case .fireRed:
      let fireRedModel = model.isFireRedASRModel ? model : .fireRedASR2
      return FireRedASRTranscriber(model: fireRedModel)
    case .nemotron:
      return NemotronASRTranscriber(model: model.isNemotronASRModel ? model : .nemotronASR358bit)
    case .cohere:
      let cohereModel = model.isCohereTranscribeModel ? model : .cohereTranscribe03FP16
      return CohereTranscribeASRTranscriber(model: cohereModel)
    }
  }
}
