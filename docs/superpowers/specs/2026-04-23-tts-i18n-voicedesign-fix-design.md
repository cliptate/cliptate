# TTS i18n & VoiceDesign Bug Fix — Design

**Date:** 2026-04-23  
**Status:** Approved (autonomous — user unavailable)

---

## Problem

1. **VoiceDesign input invisible on first load.** `voiceMode` initialises to `.preset`. SwiftUI's `.onChange(of:)` does not fire for the initial value, only subsequent changes. When the user already has a VoiceDesign model selected, `availableModes = [.voiceDesign]` but `voiceMode` stays `.preset`, so the preset-speaker section is shown instead of the voice-parameter input.

2. **Speaker descriptions appear in Chinese for all UI locales.** `TTSPresetSpeaker.all` uses `NSLocalizedString("Chinese text", ...)` where the first argument is a Chinese string — this is the lookup *key*. Without a translation file providing an English value for that key, English-UI users see raw Chinese text. The same antipattern affects `TTSModelFamily.subtitle`, `TTSVariantPreference.displayName`, `TTSEngine.subtitle`, and `VoiceMode.localizedTitle` (added last session but also needs catalog backing).

---

## Approach — Apple String Catalog (`.xcstrings`)

**Chosen:** String Catalog (`.xcstrings`, Xcode 15+).  
*Rationale:* Single-file JSON, built-in state tracking (new / translated / needs-review), first-class Xcode editor, compatible with `String(localized:)` and SwiftUI `Text("literal")` lookups.

**Target locales:** `en` (base/development), `zh-Hans` (Simplified Chinese — primary market per speaker set), `ja` (Japanese), `ko` (Korean).

---

## Architecture

### VoiceDesign bug fix

Add `.task(id: config.ttsMLXModelId)` to `mlxVoiceControls` to normalise `voiceMode` whenever the model changes *or* the view first appears:

```swift
.task(id: config.ttsMLXModelId) {
    let family = MLXTTSModelDefinition.availableModels
        .first { $0.huggingFaceRepo == config.ttsMLXModelId }?.family
    switch family {
    case .customVoice where voiceMode != .emotionControl:
        voiceMode = .emotionControl
    case .voiceDesign where voiceMode != .voiceDesign:
        voiceMode = .voiceDesign
    case .base where voiceMode == .emotionControl || voiceMode == .voiceDesign:
        voiceMode = .preset
    default: break
    }
}
```

### String Catalog

**File:** `Sources/VoiceFlowPro/Localizable.xcstrings`  
Auto-synced into the app bundle via `PBXFileSystemSynchronizedRootGroup`.

**Strings covered:**

| Category | Count | Keys |
|---|---|---|
| Speaker descriptions | 9 | `"Vivian.description"` … `"Sohee.description"` |
| Model family subtitles | 3 | `"TTSModelFamily.base.subtitle"` … |
| TTSVariantPreference | 3 | `"TTSVariantPreference.automatic.displayName"` … |
| TTSEngine subtitle | 1 | `"TTSEngine.qwen3TTS.subtitle"` |
| VoiceMode titles | 4 | Already in code via `String(localized:)` |
| Error/status messages | 6 | Already in code via `String(localized:)` |

### Code changes

- **`TTSPresetSpeaker.all`:** Replace `NSLocalizedString("Chinese text")` with `String(localized: "Speaker.description", bundle: .main, comment: "…")` using English text as the default value (comment field).
- **`TTSModelFamily.subtitle`:** Use `String(localized: "TTSModelFamily.X.subtitle")`.
- **`TTSVariantPreference.displayName`:** Use `String(localized: "TTSVariantPreference.X.displayName")`.
- **`TTSEngine.subtitle`:** Use `String(localized: "TTSEngine.qwen3TTS.subtitle")`.
- **`TTSVoiceProfile.Locale.localizedDisplayName`:** Switch to `Locale.current.localizedString(forIdentifier: rawValue)` — system API, no catalog entry needed.

### Out of scope

- `MLXTTSModelDefinition.description` — shown only in the models library picker, not end-user UI.
- Model `displayName`, `parameterSize`, `quantization` — technical identifiers.

---

## Testing (TDD)

1. `TTSPresetSpeakerLocalizationTests` — each speaker has a non-empty description; no Chinese keys visible in en locale.
2. `TTSModelFamilyStringTests` — each family subtitle is non-empty.
3. VoiceDesign mode normalisation — unit-test the family→mode mapping logic.
