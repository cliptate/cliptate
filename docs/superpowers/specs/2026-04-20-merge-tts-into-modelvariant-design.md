# Merge TTS Downloads into ModelVariant — Design Spec

## Problem

`MLXTTSDownloadManager` is a separate actor that manages TTS model downloads in parallel to `ModelDownloadManager`. This creates three bugs:

1. `isModelCached` only checks for `.safetensors` — does not require `config.json`, so models that failed mid-download appear as "cached".
2. `deleteModel` does not fire `ModelArtifactStatusNotifier.postChange`, so the UI does not refresh after deletion.
3. Path base comes from `overrideCacheBaseURL: URL?` (nullable), not from the unified `cacheRootProvider` injectable closure, so tests that inject a temp directory work differently from `ModelDownloadManager` tests.

## Approach

Add 6 TTS `ModelVariant` cases. Attach a `modelVariant: ModelVariant` property to `MLXTTSModelDefinition`. Route all TTS download/status/delete/size operations through `ModelDownloadManager`. Delete `MLXTTSDownloadManager`.

`MLXTTSModelDefinition` is kept as-is for UI-only metadata (supportsVoiceClone, family, quantization, parameterSize, description). It is no longer used for any download logic.

## ModelVariant additions

Six new cases (raw values become `ModelVariant.id` for `Codable`):

| Case | Raw value | HuggingFace repo |
|---|---|---|
| `qwen3TTS06B4bit` | `qwen3-tts-0.6b-4bit` | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit` |
| `qwen3TTS06B8bit` | `qwen3-tts-0.6b-8bit` | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit` |
| `qwen3TTS06Bbf16` | `qwen3-tts-0.6b-bf16` | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` |
| `qwen3TTS17B4bit` | `qwen3-tts-1.7b-4bit` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit` |
| `qwen3TTS17B8bit` | `qwen3-tts-1.7b-8bit` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit` |
| `qwen3TTS17Bbf16` | `qwen3-tts-1.7b-bf16` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` |

New computed properties: `isTTSModel: Bool`, `static var ttsModels: [ModelVariant]`.
All other computed properties gain TTS cases with sensible values.

## ModelDownloadManager additions

1. TTS case in `downloadMLXAudioModel` switch — uses `ModelUtils.resolveOrDownloadModel` (same as Sortformer/Aligner).
2. `func modelSizeInMB(for model: ModelVariant) -> Int` — directory size helper using `FileManager`.

## Caller migration

`ModelsView.swift`: replace `MLXTTSDownloadManager.shared.*` with `ModelDownloadManager.shared.*`. Switch state dict keys from `String` (huggingFaceRepo) to `ModelVariant`.

`TTSSynthesisView.swift`, `ModelCacheManager.swift`: replace `isModelCached(repoId:)` with `hasLocalArtifacts(for: def.modelVariant)`.

## Testing

Existing `MLXTTSDownloadManagerTests` migrated into a new `ModelDownloadManagerTTSTests` file using `cacheRootProvider` injection. `isModelCached`-equivalent tests seed both `config.json` + `model.safetensors`.
