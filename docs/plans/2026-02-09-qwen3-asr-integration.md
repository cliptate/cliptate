# Qwen3 ASR Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate mlx-audio-swift library to support Qwen3ASR model for speech-to-text with optional ForcedAligner functionality for timestamp alignment.

**Architecture:** 
- Add MLXAudioSTT as a Swift Package dependency
- Create new `Qwen3ASRTranscriber` implementing the existing `Transcriber` protocol
- Add Qwen3ASR model variants to `ModelVariant` enum and `TranscriberType` enum
- Extend `ModelDownloadManager` to handle MLXAudio model downloads
- Support both normal transcription and forced alignment modes

**Tech Stack:** Swift 6.2, SwiftUI, MLXAudioSTT (mlx-audio-swift), HuggingFace models

**Available Models:**
- `mlx-community/Qwen3-ASR-0.6B-8bit` - Normal ASR (~600MB)
- `mlx-community/Qwen3-ForcedAligner-0.6B-4bit` - Forced Alignment (~400MB)

---

## Task 1: Add mlx-audio-swift Dependency

**Files:**
- Modify: `Package.swift`

**Step 1: Add the mlx-audio-swift package dependency**

```swift
// In dependencies array, add:
.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
```

**Step 2: Add MLXAudioSTT product to target dependencies**

```swift
// In target dependencies array, add:
.product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
.product(name: "MLXAudioCore", package: "mlx-audio-swift"),
```

**Step 3: Verify package resolution**

Run: `cd <repository> && swift package resolve`
Expected: Dependencies resolved successfully

**Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "feat: add mlx-audio-swift dependency for Qwen3ASR support"
```

---

## Task 2: Add Qwen3ASR Model Variants

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`

**Step 1: Add Qwen3ASR cases to ModelVariant enum**

Add to `ModelVariant` enum after `parakeetV3`:

```swift
// Qwen3 ASR models
case qwen3ASR = "qwen3-asr-0.6b-8bit"
case qwen3ForcedAligner = "qwen3-forcedaligner-0.6b-4bit"
```

**Step 2: Update displayName computed property**

Add cases to `displayName` switch:

```swift
case .qwen3ASR: return "Qwen3 ASR (0.6B)"
case .qwen3ForcedAligner: return "Qwen3 ForcedAligner (0.6B)"
```

**Step 3: Update summary computed property**

Add cases to `summary` switch:

```swift
case .qwen3ASR:
  return "MLX-based ASR supporting 52 languages with high efficiency on Apple Silicon."
case .qwen3ForcedAligner:
  return "Forced alignment model for precise word-level timestamp prediction."
```

**Step 4: Add isQwen3Model computed property**

```swift
/// Check if this model is a Qwen3 ASR model
var isQwen3Model: Bool {
  switch self {
  case .qwen3ASR, .qwen3ForcedAligner: return true
  default: return false
  }
}
```

**Step 5: Update provider computed property**

Modify `provider` to include Qwen3:

```swift
public var provider: TranscriberType {
  if isParakeetModel { return .parakeet }
  if isQwen3Model { return .qwen3 }
  return .whisper
}
```

**Step 6: Update whisperKitModel for Qwen3 models**

Add cases to `whisperKitModel`:

```swift
case .qwen3ASR: return "mlx-community/Qwen3-ASR-0.6B-8bit"
case .qwen3ForcedAligner: return "mlx-community/Qwen3-ForcedAligner-0.6B-4bit"
```

**Step 7: Update fileSize computed property**

Add to `fileSize` switch:

```swift
case .qwen3ASR: return 600
case .qwen3ForcedAligner: return 400
```

**Step 8: Update accuracy and speedScore**

Add to `accuracy` switch:

```swift
case .qwen3ASR, .qwen3ForcedAligner: return "High"
```

Add to `speedScore` switch:

```swift
case .qwen3ASR: return 8.5
case .qwen3ForcedAligner: return 9.0
```

Add to `accuracyScore` switch:

```swift
case .qwen3ASR: return 9.0
case .qwen3ForcedAligner: return 9.2
```

**Step 9: Update supportedLanguages**

Add to `supportedLanguages` switch:

```swift
case .qwen3ASR:
  return [
    .auto, .english, .chinese, .japanese, .korean, .french, .german,
    .spanish, .portuguese, .italian, .russian, .arabic, .hindi,
    .dutch, .polish, .turkish, .vietnamese, .thai, .indonesian,
  ]
case .qwen3ForcedAligner:
  return [
    .english, .chinese, .japanese, .korean, .french, .german,
    .spanish, .portuguese, .italian, .russian,
  ]
```

**Step 10: Update languageSummary**

Add to `languageSummary` switch:

```swift
case .qwen3ASR:
  return "52 supported languages"
case .qwen3ForcedAligner:
  return "11 supported languages"
```

**Step 11: Update featureHighlights**

Add to `featureHighlights` switch:

```swift
case .qwen3ASR:
  return [
    "MLX optimized",
    "52 languages",
    "Streaming support",
  ]
case .qwen3ForcedAligner:
  return [
    "Word-level timestamps",
    "Forced alignment",
    "High precision",
  ]
```

**Step 12: Commit**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift
git commit -m "feat: add Qwen3ASR and ForcedAligner model variants"
```

---

## Task 3: Add Qwen3 TranscriberType

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`

**Step 1: Add qwen3 case to TranscriberType enum**

```swift
public enum TranscriberType: String, CaseIterable, Identifiable, Codable, Sendable {
  case whisper
  case parakeet = "parakeet"
  case qwen3 = "qwen3"
  // ...
}
```

**Step 2: Update displayName**

Add to `displayName` switch:

```swift
case .qwen3: return "Qwen3 ASR"
```

**Step 3: Update description**

Add to `description` switch:

```swift
case .qwen3: return "Qwen3 ASR with MLX optimization for Apple Silicon"
```

**Step 4: Update supportedModels**

Add to `supportedModels` switch:

```swift
case .qwen3: return [.qwen3ASR, .qwen3ForcedAligner]
```

**Step 5: Update supportedLanguages**

Add to `supportedLanguages` switch:

```swift
case .qwen3: return Language.allCases
```

**Step 6: Update createTranscriber factory method**

Add to `createTranscriber` switch:

```swift
case .qwen3:
  let qwenModel = model.isQwen3Model ? model : .qwen3ASR
  return Qwen3ASRTranscriber(model: qwenModel)
```

**Step 7: Commit**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift
git commit -m "feat: add Qwen3 transcriber type"
```

---

## Task 4: Create Qwen3ASRTranscriber Service

**Files:**
- Create: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`

**Step 1: Create the Qwen3ASRTranscriber class**

```swift
import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// Qwen3 ASR Transcriber implementation using MLX Audio
public final class Qwen3ASRTranscriber: @unchecked Sendable, Transcriber {
  private var asrModel: Qwen3ASRModel?
  private var alignerModel: Qwen3ForcedAlignerModel?
  private let modelVariant: ModelVariant
  private var isModelReady: Bool = false
  
  /// Whether to use forced aligner mode (requires pre-existing text)
  public var isForcedAligner: Bool {
    modelVariant == .qwen3ForcedAligner
  }
  
  public init(model: ModelVariant) {
    self.modelVariant = model
  }
  
  // MARK: - Model Warm-up
  
  public func warmUpModelWithProgress(
    progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
  ) async throws {
    guard !isModelReady else { return }
    
    let modelName = modelVariant.displayName
    let startTime = Date()
    
    await MainActor.run {
      progressHandler(
        ModelDownloadProgress(
          currentStep: "Checking \(modelName) availability...",
          progress: 0.05
        )
      )
    }
    
    // Check if model is downloaded
    let isDownloaded = await Qwen3ModelDownloadManager.shared.isModelDownloaded(modelVariant)
    guard isDownloaded else {
      throw ModelPreparationError.modelNotDownloaded(modelVariant)
    }
    
    await MainActor.run {
      progressHandler(
        ModelDownloadProgress(
          currentStep: "Loading \(modelName) into memory...",
          progress: 0.2
        )
      )
    }
    
    // Load the appropriate model
    let repoId = modelVariant.huggingFaceRepoId
    
    do {
      if isForcedAligner {
        await MainActor.run {
          progressHandler(
            ModelDownloadProgress(
              currentStep: "Initializing ForcedAligner runtime...",
              progress: 0.4
            )
          )
        }
        
        let model = try await Qwen3ForcedAlignerModel.fromPretrained(repoId)
        self.alignerModel = model
      } else {
        await MainActor.run {
          progressHandler(
            ModelDownloadProgress(
              currentStep: "Initializing Qwen3 ASR runtime...",
              progress: 0.4
            )
          )
        }
        
        let model = try await Qwen3ASRModel.fromPretrained(repoId)
        self.asrModel = model
      }
      
      isModelReady = true
      let totalTime = Date().timeIntervalSince(startTime)
      
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "\(modelName) ready (\(String(format: "%.1f", totalTime))s)",
            progress: 1.0
          )
        )
      }
    } catch {
      await MainActor.run {
        progressHandler(
          ModelDownloadProgress(
            currentStep: "Failed to load \(modelName): \(error.localizedDescription)",
            progress: 0.0
          )
        )
      }
      throw error
    }
  }
  
  // MARK: - Transcription
  
  public func transcribeWithProgress(
    audioPath: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    try Task.checkCancellation()
    
    guard isModelReady else {
      throw NSError(
        domain: "VoiceFlow",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Model not initialized. Please warm up the model first."
        ]
      )
    }
    
    let startTime = Date()
    let audioURL = URL(fileURLWithPath: audioPath)
    
    // Access security scoped resource
    let needsStop = audioURL.startAccessingSecurityScopedResource()
    defer { if needsStop { audioURL.stopAccessingSecurityScopedResource() } }
    
    // Get audio duration
    let asset = AVURLAsset(url: audioURL)
    let assetDuration = try await asset.load(.duration)
    let audioDuration = max(assetDuration.seconds, 0.001)
    
    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.0,
          statusMessage: "Loading audio...",
          estimatedTimeRemaining: audioDuration
        )
      )
    }
    
    try Task.checkCancellation()
    
    // Load audio
    let (sampleRate, audioData) = try loadAudioArray(from: audioURL)
    
    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.1,
          statusMessage: "Processing audio...",
          estimatedTimeRemaining: audioDuration * 0.9
        )
      )
    }
    
    try Task.checkCancellation()
    
    // Perform transcription
    let segments: [Segment]
    
    if isForcedAligner {
      // Forced aligner requires existing text - for now, return empty
      // This will be used with a separate alignment API
      throw NSError(
        domain: "VoiceFlow",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "ForcedAligner requires text input. Use alignWithText() instead."
        ]
      )
    } else {
      guard let model = asrModel else {
        throw NSError(
          domain: "VoiceFlow",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "ASR model not loaded."]
        )
      }
      
      Task { @MainActor in
        progressHandler(
          TranscriptionProgress(
            currentSegments: [],
            progress: 0.2,
            statusMessage: "Transcribing...",
            estimatedTimeRemaining: audioDuration * 0.8
          )
        )
      }
      
      // Convert audio to MLXArray
      let audioArray = MLXArray(audioData)
      
      // Generate transcription
      let result = model.generate(audio: audioArray, language: language.qwen3LanguageCode)
      
      Task { @MainActor in
        progressHandler(
          TranscriptionProgress(
            currentSegments: [],
            progress: 0.9,
            statusMessage: "Processing results...",
            estimatedTimeRemaining: 0.5
          )
        )
      }
      
      // Convert result to segments
      segments = convertToSegments(from: result, audioDuration: audioDuration)
    }
    
    let processingTime = Date().timeIntervalSince(startTime)
    
    let finalProgress = TranscriptionProgress(
      currentSegments: segments,
      progress: 1.0,
      statusMessage: "Completed",
      estimatedTimeRemaining: 0
    )
    Task { @MainActor in progressHandler(finalProgress) }
    
    return TranscriptionResult(
      segments: segments,
      totalDuration: audioDuration,
      processingTime: processingTime,
      modelUsed: modelVariant.rawValue
    )
  }
  
  // MARK: - Forced Alignment API
  
  /// Align existing text with audio timestamps
  public func alignWithText(
    audioPath: String,
    text: String,
    language: Language,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    guard isForcedAligner else {
      throw NSError(
        domain: "VoiceFlow",
        code: 4,
        userInfo: [
          NSLocalizedDescriptionKey: "alignWithText() requires ForcedAligner model variant."
        ]
      )
    }
    
    guard let model = alignerModel else {
      throw NSError(
        domain: "VoiceFlow",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "ForcedAligner model not loaded."]
      )
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
          currentSegments: [],
          progress: 0.1,
          statusMessage: "Loading audio for alignment...",
          estimatedTimeRemaining: audioDuration
        )
      )
    }
    
    // Load audio
    let (_, audioData) = try loadAudioArray(from: audioURL)
    let audioArray = MLXArray(audioData)
    
    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.3,
          statusMessage: "Aligning timestamps...",
          estimatedTimeRemaining: audioDuration * 0.7
        )
      )
    }
    
    // Perform forced alignment
    let result = model.generate(
      audio: audioArray,
      text: text,
      language: language.qwen3LanguageCode
    )
    
    Task { @MainActor in
      progressHandler(
        TranscriptionProgress(
          currentSegments: [],
          progress: 0.9,
          statusMessage: "Processing alignment results...",
          estimatedTimeRemaining: 0.5
        )
      )
    }
    
    // Convert forced alignment result to segments
    let segments = convertAlignmentToSegments(from: result)
    
    let processingTime = Date().timeIntervalSince(startTime)
    
    let finalProgress = TranscriptionProgress(
      currentSegments: segments,
      progress: 1.0,
      statusMessage: "Alignment completed",
      estimatedTimeRemaining: 0
    )
    Task { @MainActor in progressHandler(finalProgress) }
    
    return TranscriptionResult(
      segments: segments,
      totalDuration: audioDuration,
      processingTime: processingTime,
      modelUsed: modelVariant.rawValue
    )
  }
  
  // MARK: - Helper Methods
  
  private func convertToSegments(from result: STTOutput, audioDuration: Double) -> [Segment] {
    var segments: [Segment] = []
    
    // Parse the result segments
    for segmentDict in result.segments {
      guard let text = segmentDict["text"] as? String,
            let start = segmentDict["start"] as? Double,
            let end = segmentDict["end"] as? Double else {
        continue
      }
      
      let segment = Segment(
        startTime: start,
        endTime: min(end, audioDuration),
        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
        words: nil
      )
      
      if !segment.text.isEmpty {
        segments.append(segment)
      }
    }
    
    // If no segments, create one from full text
    if segments.isEmpty && !result.text.isEmpty {
      segments.append(
        Segment(
          startTime: 0,
          endTime: audioDuration,
          text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
          words: nil
        )
      )
    }
    
    return segments
  }
  
  private func convertAlignmentToSegments(from result: ForcedAlignResult) -> [Segment] {
    var segments: [Segment] = []
    var currentSegmentWords: [WordTiming] = []
    var segmentStartTime: Double = 0
    var segmentText: [String] = []
    
    for item in result.items {
      let wordTiming = WordTiming(
        word: item.text,
        startTime: item.startTime,
        endTime: item.endTime,
        confidence: nil
      )
      
      if currentSegmentWords.isEmpty {
        segmentStartTime = item.startTime
      }
      
      currentSegmentWords.append(wordTiming)
      segmentText.append(item.text)
      
      // Create segment every ~10 words or at punctuation
      let shouldSplit = currentSegmentWords.count >= 10 ||
                        item.text.last?.isPunctuation == true
      
      if shouldSplit && !currentSegmentWords.isEmpty {
        let segment = Segment(
          startTime: segmentStartTime,
          endTime: item.endTime,
          text: segmentText.joined(separator: " "),
          words: currentSegmentWords
        )
        segments.append(segment)
        currentSegmentWords = []
        segmentText = []
      }
    }
    
    // Add remaining words as final segment
    if !currentSegmentWords.isEmpty, let lastWord = currentSegmentWords.last {
      let segment = Segment(
        startTime: segmentStartTime,
        endTime: lastWord.endTime,
        text: segmentText.joined(separator: " "),
        words: currentSegmentWords
      )
      segments.append(segment)
    }
    
    return segments
  }
}

// MARK: - Language Extension for Qwen3

extension Language {
  var qwen3LanguageCode: String {
    switch self {
    case .auto: return "auto"
    case .english: return "English"
    case .chinese: return "Chinese"
    case .japanese: return "Japanese"
    case .korean: return "Korean"
    case .french: return "French"
    case .german: return "German"
    case .spanish: return "Spanish"
    case .portuguese: return "Portuguese"
    case .italian: return "Italian"
    case .russian: return "Russian"
    case .arabic: return "Arabic"
    case .hindi: return "Hindi"
    case .dutch: return "Dutch"
    case .polish: return "Polish"
    case .turkish: return "Turkish"
    case .vietnamese: return "Vietnamese"
    case .thai: return "Thai"
    case .indonesian: return "Indonesian"
    default: return "English"
    }
  }
}

// MARK: - ModelVariant Extension for Qwen3

extension ModelVariant {
  var huggingFaceRepoId: String {
    switch self {
    case .qwen3ASR: return "mlx-community/Qwen3-ASR-0.6B-8bit"
    case .qwen3ForcedAligner: return "mlx-community/Qwen3-ForcedAligner-0.6B-4bit"
    default: return rawValue
    }
  }
}
```

**Step 2: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift
git commit -m "feat: add Qwen3ASRTranscriber with ForcedAligner support"
```

---

## Task 5: Create Qwen3 Model Download Manager

**Files:**
- Create: `Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift`

**Step 1: Create the download manager**

```swift
import Foundation
import MLXAudioCore
import MLXAudioSTT
import HuggingFace

/// Manages Qwen3 ASR model downloads from HuggingFace
actor Qwen3ModelDownloadManager {
  static let shared = Qwen3ModelDownloadManager()
  
  private let fileManager: FileManager
  private var activeDownloads: [ModelVariant: Task<Void, Error>] = [:]
  
  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }
  
  // MARK: - Public API
  
  func isModelDownloaded(_ model: ModelVariant) async -> Bool {
    guard model.isQwen3Model else { return false }
    
    let cacheDir = modelCacheDirectory(for: model)
    return modelFilesExist(at: cacheDir)
  }
  
  func getModelDirectory(for model: ModelVariant) -> URL? {
    guard model.isQwen3Model else { return nil }
    
    let cacheDir = modelCacheDirectory(for: model)
    return modelFilesExist(at: cacheDir) ? cacheDir : nil
  }
  
  func download(
    model: ModelVariant,
    progressHandler: @escaping @Sendable (ModelDownloadProgress) async -> Void
  ) async throws {
    guard model.isQwen3Model else {
      throw NSError(
        domain: "Qwen3ModelDownloadManager",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Not a Qwen3 model: \(model.displayName)"]
      )
    }
    
    // Check for existing download
    if let existing = activeDownloads[model] {
      try await existing.value
      return
    }
    
    // Check if already downloaded
    if await isModelDownloaded(model) {
      await progressHandler(
        ModelDownloadProgress(currentStep: "Model already downloaded", progress: 1.0)
      )
      return
    }
    
    let task = Task {
      try await downloadQwen3Model(model, progressHandler: progressHandler)
    }
    
    activeDownloads[model] = task
    defer { activeDownloads[model] = nil }
    
    try await task.value
  }
  
  func cancelDownload(for model: ModelVariant) {
    guard let task = activeDownloads[model] else { return }
    task.cancel()
  }
  
  func delete(model: ModelVariant) throws {
    guard model.isQwen3Model else { return }
    
    let cacheDir = modelCacheDirectory(for: model)
    if fileManager.fileExists(atPath: cacheDir.path) {
      try fileManager.removeItem(at: cacheDir)
    }
  }
  
  // MARK: - Private Helpers
  
  private func downloadQwen3Model(
    _ model: ModelVariant,
    progressHandler: @escaping @Sendable (ModelDownloadProgress) async -> Void
  ) async throws {
    try Task.checkCancellation()
    
    let repoId = model.huggingFaceRepoId
    let maxRetries = 3
    var lastError: Error?
    
    for attempt in 1...maxRetries {
      try Task.checkCancellation()
      
      do {
        await progressHandler(
          ModelDownloadProgress(
            currentStep: "Downloading \(model.displayName)...",
            progress: 0.1,
            attemptNumber: attempt,
            maxAttempts: maxRetries
          )
        )
        
        // Start simulated progress tracking
        let progressTask = Task<Void, Never> {
          var simulatedProgress: Float = 0.1
          while !Task.isCancelled && simulatedProgress < 0.95 {
            do {
              try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch { break }
            simulatedProgress += 0.15
            
            await progressHandler(
              ModelDownloadProgress(
                currentStep: "Downloading \(model.displayName)... (\(Int(simulatedProgress * 100))%)",
                progress: simulatedProgress,
                attemptNumber: attempt,
                maxAttempts: maxRetries
              )
            )
          }
        }
        
        // Download and load model to verify
        if model == .qwen3ForcedAligner {
          _ = try await Qwen3ForcedAlignerModel.fromPretrained(repoId)
        } else {
          _ = try await Qwen3ASRModel.fromPretrained(repoId)
        }
        
        progressTask.cancel()
        
        await progressHandler(
          ModelDownloadProgress(
            currentStep: "Qwen3 model ready",
            progress: 1.0,
            attemptNumber: attempt,
            maxAttempts: maxRetries
          )
        )
        
        return
        
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        lastError = error
        
        await progressHandler(
          ModelDownloadProgress(
            currentStep: "Download failed: \(error.localizedDescription)",
            progress: 0.0,
            attemptNumber: attempt,
            maxAttempts: maxRetries
          )
        )
        
        if attempt < maxRetries {
          let delay = TimeInterval(attempt * 3)
          await progressHandler(
            ModelDownloadProgress(
              currentStep: "Retrying in \(Int(delay))s...",
              progress: 0.0,
              estimatedTimeRemaining: delay,
              attemptNumber: attempt,
              maxAttempts: maxRetries
            )
          )
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }
    }
    
    throw NSError(
      domain: "Qwen3ModelDownloadManager",
      code: -10,
      userInfo: [
        NSLocalizedDescriptionKey: "Failed to download \(model.displayName)",
        NSLocalizedFailureReasonErrorKey: lastError?.localizedDescription ?? "Unknown error"
      ]
    )
  }
  
  private func modelCacheDirectory(for model: ModelVariant) -> URL {
    let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let repoName = model.huggingFaceRepoId.replacingOccurrences(of: "/", with: "_")
    return base
      .appendingPathComponent("huggingface", isDirectory: true)
      .appendingPathComponent("hub", isDirectory: true)
      .appendingPathComponent("models--\(repoName)", isDirectory: true)
  }
  
  private func modelFilesExist(at directory: URL) -> Bool {
    guard fileManager.fileExists(atPath: directory.path) else { return false }
    
    // Check for safetensors files
    guard let contents = try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return false
    }
    
    // Look recursively for safetensors
    return containsSafetensors(in: directory)
  }
  
  private func containsSafetensors(in directory: URL) -> Bool {
    guard let enumerator = fileManager.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return false
    }
    
    while let fileURL = enumerator.nextObject() as? URL {
      if fileURL.pathExtension == "safetensors" {
        return true
      }
    }
    
    return false
  }
}
```

**Step 2: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift
git commit -m "feat: add Qwen3ModelDownloadManager for HuggingFace model downloads"
```

---

## Task 6: Integrate Qwen3 into ModelDownloadManager

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`

**Step 1: Update isModelDownloaded method**

Add Qwen3 check before the return:

```swift
func isModelDownloaded(_ model: ModelVariant) async -> Bool {
  if model.requiresProSubscription {
    do {
      let permission: ModelDownloadPermission = try await accessController.checkPermission(for: model)
      guard permission.isAllowed else { return false }
    } catch {
      return false
    }
  }

  // Handle Qwen3 models
  if model.isQwen3Model {
    return await Qwen3ModelDownloadManager.shared.isModelDownloaded(model)
  }

  return hasLocalModel(for: model)
}
```

**Step 2: Update getModelDirectory method**

Add Qwen3 handling:

```swift
func getModelDirectory(for model: ModelVariant) -> URL? {
  if model.isQwen3Model {
    return Qwen3ModelDownloadManager.shared.getModelDirectory(for: model)
  }
  // ... rest of existing code
}
```

**Step 3: Update download method**

Add Qwen3 download handling in the task:

```swift
let task = Task {
  if model.isQwen3Model {
    try await Qwen3ModelDownloadManager.shared.download(model: model, progressHandler: progressHandler)
  } else if model.isParakeetModel {
    try await self.downloadParakeetModel(model, progressHandler: progressHandler)
  } else {
    try await self.downloadWhisperModel(model, progressHandler: progressHandler)
  }
}
```

**Step 4: Update delete method**

Add Qwen3 deletion:

```swift
func delete(model: ModelVariant) throws {
  if model.isQwen3Model {
    try Qwen3ModelDownloadManager.shared.delete(model: model)
    return
  }
  // ... rest of existing code
}
```

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelDownloadManager.swift
git commit -m "feat: integrate Qwen3 model support into ModelDownloadManager"
```

---

## Task 7: Update TranscriberPool for Qwen3

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/TranscriberPool.swift`

**Step 1: Add Qwen3 transcriber cache**

Add a new cache dictionary for Qwen3 transcibers if not already generic.

**Step 2: Update getTranscriber to handle qwen3 type**

In the `getTranscriber` method, add case for `.qwen3`:

```swift
case .qwen3:
  let qwenModel = model.isQwen3Model ? model : .qwen3ASR
  let transcriber = Qwen3ASRTranscriber(model: qwenModel)
  try await transcriber.warmUpModelWithProgress(progressHandler: progress)
  return transcriber
```

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/TranscriberPool.swift
git commit -m "feat: add Qwen3 transcriber support to TranscriberPool"
```

---

## Task 8: Build and Test

**Step 1: Build the project**

Run: `cd <repository> && swift build 2>&1`
Expected: Build succeeds

**Step 2: Run tests if available**

Run: `swift test 2>&1 | head -100`
Expected: Tests pass

**Step 3: Fix any compilation errors**

Address any type mismatches or missing imports.

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete Qwen3 ASR integration with ForcedAligner support"
```

---

## Summary

This implementation plan adds:

1. **mlx-audio-swift dependency** - Adds the MLXAudioSTT library for Qwen3 ASR support
2. **ModelVariant extensions** - `qwen3ASR` and `qwen3ForcedAligner` model variants
3. **TranscriberType.qwen3** - New transcriber type for Qwen3 models
4. **Qwen3ASRTranscriber** - Full implementation of the `Transcriber` protocol with:
   - Normal transcription mode (`transcribeWithProgress`)
   - Forced alignment mode (`alignWithText`)
   - Language code mapping for Qwen3
5. **Qwen3ModelDownloadManager** - Handles model downloads from HuggingFace
6. **Integration** - Updates to `ModelDownloadManager` and `TranscriberPool`

The implementation follows the existing patterns in the codebase and integrates seamlessly with the current architecture.
