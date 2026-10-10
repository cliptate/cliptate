import AVFoundation

// AVFoundation types cross actor boundaries for export and streaming workflows.
// Mark them as unchecked Sendable because the framework internally manages thread safety.
extension AVAudioPCMBuffer: @retroactive @unchecked Sendable {}
extension AVAssetReader: @retroactive @unchecked Sendable {}
extension AVAssetReaderTrackOutput: @retroactive @unchecked Sendable {}
extension AVAssetWriter: @retroactive @unchecked Sendable {}
extension AVAssetWriterInput: @retroactive @unchecked Sendable {}
