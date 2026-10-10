import Foundation
#if os(macOS)
import Darwin
#endif

enum ModelDownloadBackend: Equatable, Sendable {
  case qwen3ASR
  case qwen3Aligner
  case fireRedASR
  case cohereASR
  case sortformerVAD
  case sileroVAD
  case resolver
  case unsupported
}

struct ModelStoragePaths: Equatable, Sendable {
  let mlxAudioDirectories: [URL]
  let huggingFaceRepositoryDirectories: [URL]

  var primaryMLXAudioDirectory: URL? { mlxAudioDirectories.first }
  var primaryHuggingFaceRepositoryDirectory: URL? { huggingFaceRepositoryDirectories.first }

  var storageDirectories: [URL] {
    ModelStorageLayoutResolver.deduplicatedURLs(huggingFaceRepositoryDirectories + mlxAudioDirectories)
  }
}

enum ModelStorageLayoutResolver {
  static var defaultHomeDirectory: URL {
    #if os(macOS)
    // Foundation's home-directory APIs all resolve inside the app container.
    let accountHome = getpwuid(getuid()).flatMap { entry in
      entry.pointee.pw_dir.map { path in
        URL(fileURLWithPath: String(cString: path), isDirectory: true)
      }
    }
    #else
    let accountHome: URL? = nil
    #endif
    return modelHomeDirectory(
      processHome: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
      accountHome: accountHome
    )
  }

  static func modelHomeDirectory(processHome: URL, accountHome: URL?) -> URL {
    #if APP_STORE
      return processHome
    #else
      // NSHomeDirectory points into the container even for sandboxed direct builds.
      return accountHome ?? processHome
    #endif
  }

  static func hubCacheRoot(environment env: [String: String]) -> URL {
    hubCacheRoot(
      environment: env,
      homeDirectory: defaultHomeDirectory,
      cachesDirectory: URL.cachesDirectory
    )
  }

  static func hubCacheRoot(
    environment env: [String: String],
    homeDirectory: URL,
    cachesDirectory: URL
  ) -> URL {
    if let value = env["HF_HUB_CACHE"] {
      return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
    }
    if let value = env["HF_HOME"] {
      return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
        .appendingPathComponent("hub")
    }
    #if os(macOS)
      return homeDirectory
        .appendingPathComponent(".cache")
        .appendingPathComponent("huggingface")
        .appendingPathComponent("hub")
    #else
      return legacyHubCacheRoot(cachesDirectory: cachesDirectory)
    #endif
  }

  static func mlxAudioBase(environment env: [String: String]) -> URL {
    mlxAudioBase(
      environment: env,
      homeDirectory: defaultHomeDirectory,
      cachesDirectory: URL.cachesDirectory
    )
  }

  static func mlxAudioBase(
    environment env: [String: String],
    homeDirectory: URL,
    cachesDirectory: URL
  ) -> URL {
    hubCacheRoot(
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    ).appendingPathComponent("mlx-audio")
  }

  static func mlxAudioBase(hubRoot: URL) -> URL {
    hubRoot.appendingPathComponent("mlx-audio")
  }

  static func mlxAudioDirectories(
    forRepo repoId: String,
    hubRoot: URL,
    legacyMLXAudioBase: URL?
  ) -> [URL] {
    let subdirectory = repoId.replacingOccurrences(of: "/", with: "_")
    let primary = mlxAudioBase(hubRoot: hubRoot)
      .appendingPathComponent(subdirectory, isDirectory: true)
    guard let legacyMLXAudioBase else {
      return [primary]
    }
    let legacy = legacyMLXAudioBase.appendingPathComponent(subdirectory, isDirectory: true)
    if legacy.standardizedFileURL == primary.standardizedFileURL {
      return [primary]
    }
    return [primary, legacy]
  }

  static func huggingFaceRepositoryDirectories(
    forRepo repoId: String,
    hubRoot: URL,
    legacyMLXAudioBase: URL?
  ) -> [URL] {
    let primary = huggingFaceRepositoryDirectory(forRepo: repoId, hubRoot: hubRoot)
    guard let legacyMLXAudioBase else {
      return [primary]
    }
    let legacyHubRoot = legacyMLXAudioBase.deletingLastPathComponent()
    let legacy = huggingFaceRepositoryDirectory(forRepo: repoId, hubRoot: legacyHubRoot)
    if legacy.standardizedFileURL == primary.standardizedFileURL {
      return [primary]
    }
    return [primary, legacy]
  }

  static func huggingFaceRepositoryDirectory(forRepo repoId: String, hubRoot: URL) -> URL {
    let repoDirName = "models--" + repoId.replacingOccurrences(of: "/", with: "--")
    return hubRoot.appendingPathComponent(repoDirName, isDirectory: true)
  }

  static func deduplicatedURLs(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    var result: [URL] = []
    for url in urls {
      let key = url.standardizedFileURL.path
      if seen.insert(key).inserted {
        result.append(url)
      }
    }
    return result
  }

  static func legacyHubCacheRoot(cachesDirectory: URL) -> URL {
    cachesDirectory
      .appendingPathComponent("huggingface")
      .appendingPathComponent("hub")
  }

  static func legacyMLXAudioBase(cachesDirectory: URL) -> URL {
    legacyHubCacheRoot(cachesDirectory: cachesDirectory)
      .appendingPathComponent("mlx-audio")
  }
}

extension ModelVariant {
  var downloadBackend: ModelDownloadBackend {
    if isParakeetModel { return .resolver }
    if isQwen3ASRModel { return .qwen3ASR }
    if isFireRedASRModel { return .fireRedASR }
    if isCohereTranscribeModel { return .cohereASR }
    if isQwen3AlignerModel { return .qwen3Aligner }
    if isSortformerVADModel { return .sortformerVAD }
    if isSileroVADModel { return .sileroVAD }
    if isTTSModel { return .resolver }
    return .unsupported
  }

  func storagePaths(hubRoot: URL, legacyMLXAudioBase: URL?) -> ModelStoragePaths {
    ModelStoragePaths(
      mlxAudioDirectories: ModelStorageLayoutResolver.mlxAudioDirectories(
        forRepo: huggingFaceRepoId,
        hubRoot: hubRoot,
        legacyMLXAudioBase: legacyMLXAudioBase
      ),
      huggingFaceRepositoryDirectories: ModelStorageLayoutResolver.huggingFaceRepositoryDirectories(
        forRepo: huggingFaceRepoId,
        hubRoot: hubRoot,
        legacyMLXAudioBase: legacyMLXAudioBase
      )
    )
  }

  func storagePaths(
    environment env: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = ModelStorageLayoutResolver.defaultHomeDirectory,
    cachesDirectory: URL = URL.cachesDirectory
  ) -> ModelStoragePaths {
    let hubRoot = ModelStorageLayoutResolver.hubCacheRoot(
      environment: env,
      homeDirectory: homeDirectory,
      cachesDirectory: cachesDirectory
    )
    let legacyMLXAudioBase = ModelStorageLayoutResolver.legacyMLXAudioBase(
      cachesDirectory: cachesDirectory
    )
    return storagePaths(hubRoot: hubRoot, legacyMLXAudioBase: legacyMLXAudioBase)
  }

  /// Get the HuggingFace repository ID for this model variant.
  public var huggingFaceRepoId: String {
    switch self {
    case .qwen3ASR: return "mlx-community/Qwen3-ASR-0.6B-8bit"
    case .qwen3ASR06B4bit: return "mlx-community/Qwen3-ASR-0.6B-4bit"
    case .qwen3ASR06B5bit: return "mlx-community/Qwen3-ASR-0.6B-5bit"
    case .qwen3ASR06B6bit: return "mlx-community/Qwen3-ASR-0.6B-6bit"
    case .qwen3ASR06Bbf16: return "mlx-community/Qwen3-ASR-0.6B-bf16"
    case .qwen3ASR17B4bit: return "mlx-community/Qwen3-ASR-1.7B-4bit"
    case .qwen3ASR17B5bit: return "mlx-community/Qwen3-ASR-1.7B-5bit"
    case .qwen3ASR17B6bit: return "mlx-community/Qwen3-ASR-1.7B-6bit"
    case .qwen3ASR17B8bit: return "mlx-community/Qwen3-ASR-1.7B-8bit"
    case .qwen3ASR17Bbf16: return "mlx-community/Qwen3-ASR-1.7B-bf16"
    case .qwen3ForcedAligner: return "mlx-community/Qwen3-ForcedAligner-0.6B-4bit"
    case .qwen3ForcedAligner06B5bit: return "mlx-community/Qwen3-ForcedAligner-0.6B-5bit"
    case .qwen3ForcedAligner06B6bit: return "mlx-community/Qwen3-ForcedAligner-0.6B-6bit"
    case .qwen3ForcedAligner06B8bit: return "mlx-community/Qwen3-ForcedAligner-0.6B-8bit"
    case .qwen3ForcedAligner06Bbf16: return "mlx-community/Qwen3-ForcedAligner-0.6B-bf16"
    case .fireRedASR2: return "mlx-community/FireRedASR2-AED-mlx"
    case .cohereTranscribe03FP16: return "beshkenadze/cohere-transcribe-03-2026-mlx-fp16"
    case .cohereTranscribe038bit: return "beshkenadze/cohere-transcribe-03-2026-mlx-8bit"
    case .cohereTranscribe034bit: return "beshkenadze/cohere-transcribe-03-2026-mlx-4bit"
    case .sortformerStreaming, .sortformerOffline:
      return "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    case .sileroVAD:
      return "mlx-community/silero-vad"
    case .parakeetV2:
      return "mlx-community/parakeet-tdt-0.6b-v2"
    case .parakeetV3:
      return "mlx-community/parakeet-tdt-0.6b-v3"
    case .qwen3TTS06B4bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"
    case .qwen3TTS06B8bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    case .qwen3TTS06Bbf16: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    case .qwen3TTS17B4bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit"
    case .qwen3TTS17B8bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
    case .qwen3TTS17Bbf16: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    case .qwen3TTS06BCustomVoice4bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"
    case .qwen3TTS06BCustomVoice8bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
    case .qwen3TTS06BCustomVoiceBf16: return "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
    case .qwen3TTS17BCustomVoice4bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit"
    case .qwen3TTS17BCustomVoice8bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
    case .qwen3TTS17BCustomVoiceBf16: return "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"
    case .qwen3TTS06BVoiceDesign4bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-VoiceDesign-4bit"
    case .qwen3TTS06BVoiceDesign8bit: return "mlx-community/Qwen3-TTS-12Hz-0.6B-VoiceDesign-8bit"
    case .qwen3TTS06BVoiceDesignBf16: return "mlx-community/Qwen3-TTS-12Hz-0.6B-VoiceDesign-bf16"
    case .qwen3TTS17BVoiceDesign4bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit"
    case .qwen3TTS17BVoiceDesign8bit: return "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"
    case .qwen3TTS17BVoiceDesignBf16: return "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
    }
  }
}
