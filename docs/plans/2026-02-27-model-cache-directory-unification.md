# ModelCacheDirectory Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract all model cache-path resolution logic into a single `ModelCacheDirectory` enum, eliminating duplication and fixing two latent bugs in `ensureMergesFile`.

**Architecture:** A caseless `enum ModelCacheDirectory` acts as a pure namespace with static computed properties and methods. All six call sites replace inline path construction with calls to this enum. The enum's internal helpers accept an injected `environment` dict so they can be unit-tested without spawning subprocesses.

**Tech Stack:** Swift, Foundation (`URL`, `ProcessInfo`), Swift Testing framework (`@Test`)

---

## Task 1: Create `ModelCacheDirectory.swift`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ModelCacheDirectory.swift`
- Test: `Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift`

**Step 1: Write the failing tests first**

Create `Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceFlowPro

@Suite("ModelCacheDirectory Tests")
struct ModelCacheDirectoryTests {

    // MARK: - hubCacheRoot

    @Test("hubCacheRoot uses HF_HUB_CACHE when set")
    func testHubCacheRootHFHubCache() {
        let env = ["HF_HUB_CACHE": "/custom/hub"]
        let result = ModelCacheDirectory.hubCacheRoot(environment: env)
        #expect(result.path == "/custom/hub")
    }

    @Test("hubCacheRoot uses HF_HOME/hub when HF_HUB_CACHE absent")
    func testHubCacheRootHFHome() {
        let env = ["HF_HOME": "/my/hf"]
        let result = ModelCacheDirectory.hubCacheRoot(environment: env)
        #expect(result.path == "/my/hf/hub")
    }

    @Test("hubCacheRoot falls back to URL.cachesDirectory")
    func testHubCacheRootDefault() {
        let result = ModelCacheDirectory.hubCacheRoot(environment: [:])
        #expect(result == URL.cachesDirectory)
    }

    @Test("HF_HUB_CACHE takes priority over HF_HOME")
    func testHubCacheRootPriority() {
        let env = ["HF_HUB_CACHE": "/hub-cache", "HF_HOME": "/hf-home"]
        let result = ModelCacheDirectory.hubCacheRoot(environment: env)
        #expect(result.path == "/hub-cache")
    }

    // MARK: - mlxAudioBase

    @Test("mlxAudioBase appends mlx-audio to hub root")
    func testMlxAudioBaseDefault() {
        let result = ModelCacheDirectory.mlxAudioBase(environment: [:])
        #expect(result == URL.cachesDirectory.appendingPathComponent("mlx-audio"))
    }

    @Test("mlxAudioBase appends mlx-audio to HF_HUB_CACHE")
    func testMlxAudioBaseWithHFHubCache() {
        let env = ["HF_HUB_CACHE": "/custom/hub"]
        let result = ModelCacheDirectory.mlxAudioBase(environment: env)
        #expect(result.path == "/custom/hub/mlx-audio")
    }

    // MARK: - mlxAudioDirectory

    @Test("mlxAudioDirectory replaces slash with underscore in repoId")
    func testMlxAudioDirectorySubdir() {
        let result = ModelCacheDirectory.mlxAudioDirectory(forRepo: "mlx-community/Qwen3-ASR-0.6B-8bit")
        let expected = URL.cachesDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent("mlx-community_Qwen3-ASR-0.6B-8bit")
        #expect(result == expected)
    }

    // MARK: - kokoroBase

    @Test("kokoroBase is URL.cachesDirectory/fluid-audio")
    func testKokoroBase() {
        let result = ModelCacheDirectory.kokoroBase
        #expect(result == URL.cachesDirectory.appendingPathComponent("fluid-audio"))
    }
}
```

**Step 2: Run tests to verify they fail**

In Xcode: ⌘6 → run `ModelCacheDirectoryTests`. All should fail with "cannot find type 'ModelCacheDirectory'".

Or via CLI (if SPM test target is configured):
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -only-testing VoiceFlowProTests/ModelCacheDirectoryTests 2>&1 | tail -20
```

Expected: compile error — `ModelCacheDirectory` not found.

**Step 3: Create the implementation**

Create `Sources/VoiceFlowPro/Services/ModelCacheDirectory.swift`:

```swift
import Foundation

/// Single source of truth for model cache directory resolution.
///
/// Mirrors the env-var priority order of HuggingFace's `CacheLocationProvider`:
///   1. `HF_HUB_CACHE` env var  → used as hub root directly
///   2. `HF_HOME` env var       → `<HF_HOME>/hub`
///   3. Default                 → `URL.cachesDirectory` (resolves to the app's
///                                sandboxed Library/Caches on macOS)
///
/// All mlx-audio models (ASR, Aligner, TTS) land at:
///   `<hubRoot>/mlx-audio/<org>_<repo>/`
///
/// The mlx-audio-swift library's `ModelUtils.resolveOrDownloadModel` uses
/// `HubCache.default.cacheDirectory/mlx-audio/<subdir>`, and on a sandboxed
/// macOS app `HubCache.default.cacheDirectory` resolves to `URL.cachesDirectory`.
enum ModelCacheDirectory {

    // MARK: - mlx-audio (ASR, Aligner, TTS)

    /// Root directory for all mlx-audio models.
    ///
    /// Example (sandboxed): `~/Library/Containers/<bundle>/Data/Library/Caches/mlx-audio`
    static var mlxAudioBase: URL {
        mlxAudioBase(environment: ProcessInfo.processInfo.environment)
    }

    /// Returns the cache directory for a specific mlx-audio model repo.
    ///
    /// - Parameter repoId: HuggingFace repo identifier, e.g. `"mlx-community/Qwen3-ASR-0.6B-8bit"`
    /// - Returns: `<mlxAudioBase>/<org>_<repo>/`
    static func mlxAudioDirectory(forRepo repoId: String) -> URL {
        let subdir = repoId.replacingOccurrences(of: "/", with: "_")
        return mlxAudioBase.appendingPathComponent(subdir, isDirectory: true)
    }

    // MARK: - Kokoro / fluid-audio

    /// Root directory for Kokoro TTS (fluid-audio) models.
    static var kokoroBase: URL {
        URL.cachesDirectory.appendingPathComponent("fluid-audio")
    }

    // MARK: - Internal helpers (exposed for testing)

    /// Resolves the HuggingFace hub cache root, respecting env-var overrides.
    /// Exposed as `internal` (not `private`) so tests can call it directly.
    static func hubCacheRoot(environment env: [String: String]) -> URL {
        if let v = env["HF_HUB_CACHE"] {
            return URL(fileURLWithPath: NSString(string: v).expandingTildeInPath)
        }
        if let v = env["HF_HOME"] {
            return URL(fileURLWithPath: NSString(string: v).expandingTildeInPath)
                .appendingPathComponent("hub")
        }
        return URL.cachesDirectory
    }

    /// Returns the mlx-audio base directory for a given environment dict.
    static func mlxAudioBase(environment env: [String: String]) -> URL {
        hubCacheRoot(environment: env).appendingPathComponent("mlx-audio")
    }
}
```

**Step 4: Run tests — expect all to pass**

Re-run `ModelCacheDirectoryTests` in Xcode. All 7 tests should be green.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ModelCacheDirectory.swift \
        Sources/VoiceFlowProTests/Services/ModelCacheDirectoryTests.swift
git commit -m "feat: add ModelCacheDirectory as single source of truth for cache paths"
```

---

## Task 2: Migrate `MLXTTSDownloadManager`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift`

**Context:** `MLXTTSDownloadManager` has a private `cacheBaseURL` computed property (lines 24–38) that duplicates the env-var priority logic now in `ModelCacheDirectory`. It also has an `overrideCacheBaseURL` injection point used by tests — we must preserve that.

**Step 1: Replace `cacheBaseURL` body**

In `MLXTTSDownloadManager.swift`, replace the entire `cacheBaseURL` computed property:

```swift
// BEFORE
private var cacheBaseURL: URL {
    if let override = overrideCacheBaseURL { return override }
    let env = ProcessInfo.processInfo.environment
    if let hubCache = env["HF_HUB_CACHE"] {
        return URL(fileURLWithPath: NSString(string: hubCache).expandingTildeInPath)
            .appendingPathComponent("mlx-audio")
    } else if let hfHome = env["HF_HOME"] {
        return URL(fileURLWithPath: NSString(string: hfHome).expandingTildeInPath)
            .appendingPathComponent("hub")
            .appendingPathComponent("mlx-audio")
    } else {
        return URL.cachesDirectory.appendingPathComponent("mlx-audio")
    }
}

// AFTER
private var cacheBaseURL: URL {
    overrideCacheBaseURL ?? ModelCacheDirectory.mlxAudioBase
}
```

**Step 2: Verify existing tests still pass**

Run `MLXTTSDownloadManagerTests` in Xcode. All 4 tests should remain green (the `overrideCacheBaseURL` injection path is unchanged).

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift
git commit -m "refactor: MLXTTSDownloadManager uses ModelCacheDirectory"
```

---

## Task 3: Migrate `Qwen3ModelDownloadManager`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift`

**Context:** `Qwen3ModelDownloadManager` duplicates the path logic in two places: the actor-isolated `mlxAudioCacheBase` and the `nonisolated` `mlxAudioCacheBaseSync`. Both can be replaced. `ModelCacheDirectory` static methods are safe to call from `nonisolated` contexts.

**Step 1: Replace `mlxAudioCacheDirectory` + `mlxAudioCacheBase`**

Delete the `mlxAudioCacheBase` computed property entirely. Replace `mlxAudioCacheDirectory(for:)`:

```swift
// BEFORE
private func mlxAudioCacheDirectory(for model: ModelVariant) -> URL {
    let repoId = model.huggingFaceRepoId
    let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
    return mlxAudioCacheBase.appendingPathComponent(modelSubdir, isDirectory: true)
}

private var mlxAudioCacheBase: URL { ... } // DELETE this entire property

// AFTER
private func mlxAudioCacheDirectory(for model: ModelVariant) -> URL {
    ModelCacheDirectory.mlxAudioDirectory(forRepo: model.huggingFaceRepoId)
}
```

**Step 2: Replace `mlxAudioCacheDirectorySync` + `mlxAudioCacheBaseSync`**

Delete `mlxAudioCacheBaseSync`. Replace `mlxAudioCacheDirectorySync(for:)`:

```swift
// BEFORE
private nonisolated func mlxAudioCacheDirectorySync(for model: ModelVariant) -> URL {
    let repoId = model.huggingFaceRepoId
    let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
    return mlxAudioCacheBaseSync.appendingPathComponent(modelSubdir, isDirectory: true)
}

private nonisolated var mlxAudioCacheBaseSync: URL { ... } // DELETE

// AFTER
private nonisolated func mlxAudioCacheDirectorySync(for model: ModelVariant) -> URL {
    ModelCacheDirectory.mlxAudioDirectory(forRepo: model.huggingFaceRepoId)
}
```

**Step 3: Build to verify — no compile errors**

In Xcode: ⌘B. Expected: build succeeds, no errors.

**Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ModelDownloadManager.swift
git commit -m "refactor: Qwen3ModelDownloadManager uses ModelCacheDirectory"
```

---

## Task 4: Fix `ensureMergesFile` bug in `Qwen3ASRTranscriber`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift:562-576`

**Context (bug):** `ensureMergesFile` currently constructs `modelDir` as:
```swift
let modelDir = URL.cachesDirectory.appendingPathComponent(modelSubdir)
// => Library/Caches/mlx-community_Qwen3-ASR-0.6B-8bit/
```
But model files are in:
```
Library/Caches/mlx-audio/mlx-community_Qwen3-ASR-0.6B-8bit/
```
So `merges.txt` was being written to the wrong directory and never found by the model loader.

**Step 1: Replace the `modelDir` construction**

```swift
// BEFORE (lines 563-566)
let repoId = model.huggingFaceRepoId
let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
let modelDir = URL.cachesDirectory
  .appendingPathComponent(modelSubdir)

// AFTER
let repoId = model.huggingFaceRepoId
let modelDir = ModelCacheDirectory.mlxAudioDirectory(forRepo: repoId)
```

Remove the now-unused `modelSubdir` local variable.

**Step 2: Build to verify**

⌘B — expected: clean build.

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift
git commit -m "fix: ensureMergesFile writes merges.txt to correct mlx-audio directory"
```

---

## Task 5: Fix `ensureMergesFile` bug in `Qwen3StreamingModule`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift:131-134`

**Context (bug):** Same bug as Task 4 — wrong `modelDir` path, `merges.txt` lands outside the model directory.

**Step 1: Replace `modelDir` construction**

```swift
// BEFORE (lines 131-134)
private func ensureMergesFile(repoId: String) async throws {
    let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
    let modelDir = URL.cachesDirectory
      .appendingPathComponent(modelSubdir)

// AFTER
private func ensureMergesFile(repoId: String) async throws {
    let modelDir = ModelCacheDirectory.mlxAudioDirectory(forRepo: repoId)
```

Remove the now-unused `modelSubdir` local variable.

**Step 2: Build to verify**

⌘B — expected: clean build.

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift
git commit -m "fix: ensureMergesFile (streaming) writes merges.txt to correct mlx-audio directory"
```

---

## Task 6: Migrate `KokoroDownloadManager` (style consistency)

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/KokoroDownloadManager.swift` (lines ~163–166)

**Step 1: Replace inline `URL.cachesDirectory.appendingPathComponent("fluid-audio")`**

Find the two occurrences and replace with `ModelCacheDirectory.kokoroBase`:

```swift
// BEFORE
return URL.cachesDirectory.appendingPathComponent("fluid-audio")

// AFTER
return ModelCacheDirectory.kokoroBase
```

**Step 2: Build to verify**

⌘B — expected: clean build.

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/KokoroDownloadManager.swift
git commit -m "refactor: KokoroDownloadManager uses ModelCacheDirectory.kokoroBase"
```

---

## Task 7: Final verification

**Step 1: Run all tests**

In Xcode: ⌘U (run all unit tests). Expected: all existing tests pass, 7 new `ModelCacheDirectoryTests` pass.

**Step 2: Confirm no stray inline paths remain**

Search codebase for any remaining inline cache path construction:

```bash
grep -rn "cachesDirectory.*mlx-audio\|cachesDirectory.*fluid-audio\|\.cache/huggingface/hub" \
  Sources/VoiceFlowPro/Services/ --include="*.swift"
```

Expected: zero matches (only `ModelCacheDirectory.swift` itself should contain these strings).

**Step 3: Confirm test coverage**

```bash
grep -rn "ModelCacheDirectory" Sources/ --include="*.swift"
```

Expected: references in `ModelCacheDirectory.swift`, `ModelCacheDirectoryTests.swift`, `MLXTTSDownloadManager.swift`, `Qwen3ModelDownloadManager.swift`, `Qwen3ASRTranscriber.swift`, `Qwen3StreamingModule.swift`, `KokoroDownloadManager.swift`.
