# Model Cache Status Sync Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MLX Audio model readiness and downloaded state match the real Hugging Face cache location so cached Sortformer/Qwen3 models never appear as missing.

**Architecture:** Keep `ModelCacheDirectory` responsible for cache-path resolution and `Qwen3ModelDownloadManager` responsible for validating whether MLX Audio artifacts are present. Route higher-level readiness checks in `ModelDownloadManager` through that same MLX Audio artifact probe so UI state and runtime preparation share one source of truth.

**Tech Stack:** Swift, SwiftUI, Swift Testing, `swift-huggingface`, `mlx-audio-swift`

---

## Chunk 1: Cache state unification

### Task 1: Lock down the MLX Audio regression with tests

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelCacheDirectory.swift`
- Modify: `Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test that verifies MLX Audio cache resolution prefers `~/.cache/huggingface/hub/mlx-audio/...` when no cache env vars are set and also retains the legacy `Library/Caches/...` fallback candidate.

- [ ] **Step 2: Run test to verify it fails or guards the regression**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelCacheDirectoryTests -parallel-testing-enabled NO`
Expected: The test suite exercises the expected candidate ordering and fails if path resolution diverges.

- [ ] **Step 3: Write minimal implementation**

Keep `ModelCacheDirectory` aligned with `swift-huggingface` resolution rules while preserving legacy fallback candidates for existing caches.

- [ ] **Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm `ModelCacheDirectoryTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelCacheDirectory.swift Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift
git commit -m "fix: align mlx cache path detection"
```

### Task 2: Unify MLX Audio artifact detection in the download manager

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Add a regression test covering an MLX Audio VAD model so `hasLocalArtifacts` / downloaded checks succeed when a valid `config.json` and `.safetensors` file exist in the resolved cache directory.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelDownloadManagerTests -parallel-testing-enabled NO`
Expected: The new test fails before the fix because Sortformer falls through a non-MLX artifact path.

- [ ] **Step 3: Write minimal implementation**

Update `ModelDownloadManager` so every `isMLXAudioModel` uses the same artifact/readiness path, not just Qwen3 ASR/aligner variants.

- [ ] **Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm `ModelDownloadManagerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelDownloadManager.swift Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift
git commit -m "fix: unify mlx model readiness checks"
```

### Task 3: Verify end-to-end model status consistency

**Files:**
- Verify: `Sources/VoiceFlowPro/Views/ModelsView.swift`
- Verify: `Sources/VoiceFlowPro/Views/ModelSelectionView.swift`

- [ ] **Step 1: Run targeted test suites**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ModelCacheDirectoryTests -only-testing:VoiceFlowProTests/ModelDownloadManagerTests -parallel-testing-enabled NO`
Expected: Both suites pass.

- [ ] **Step 2: Inspect UI call sites that consume downloaded/readiness state**

Check: `Sources/VoiceFlowPro/Views/ModelsView.swift` and `Sources/VoiceFlowPro/Views/ModelSelectionView.swift`
Expected: Both views still consume `ModelDownloadManager` / `ModelDownloadStatusChecker` without any extra path-specific logic, so the manager-level fix is sufficient.

- [ ] **Step 3: Run a project build**

Run: `xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit verification-safe changes**

```bash
git add Sources/VoiceFlowPro/Services/ModelDownloadManager.swift Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift Sources/VoiceFlowPro/Services/ModelCacheDirectory.swift Sources/VoiceFlowProTests/Services/ModelDownloadManagerTests.swift Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift
git commit -m "fix: sync mlx cache and download status"
```
