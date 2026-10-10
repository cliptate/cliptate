# TTS Model Best Practices Design

## Problem

The Qwen3 TTS family has three distinct checkpoint types with different synthesis APIs:

- **Base**: preset speakers (named voice) + voice cloning (reference audio + transcript)
- **CustomVoice**: preset speakers + emotion/style control via `voice:` field
- **VoiceDesign**: free-form voice description via `voice:` field

The current implementation incorrectly marks CustomVoice models as `supportsVoiceClone: true`. They do not support reference-audio cloning — their `voice:` field takes a speaker name optionally combined with an emotion/style description (e.g. `"Vivian, very happy and excited."`). This mismatch causes:

1. CustomVoice models showing the Voice Clone UI tab (incorrect)
2. CustomVoice models missing an Emotion Control UI tab (missing feature)
3. No way to pass emotion prompts to CustomVoice models

## Approach

Add `supportsEmotionControl` as a computed property on `MLXTTSModelDefinition` (derived from `family == .customVoice`). Fix `supportsVoiceClone: false` on all CustomVoice model definitions. Add a new `VoiceMode.emotionControl` tab in the synthesis UI, backed by a new `ttsEmotionPrompt` field in `AppConfiguration`.

## Architecture

### TextToSpeechModels.swift

- `TTSModelFamily.customVoice.subtitle` → "Named speakers with emotion/style control"
- New computed property: `MLXTTSModelDefinition.supportsEmotionControl: Bool { family == .customVoice }`
- Fix all 6 CustomVoice model definitions: `supportsVoiceClone: false`

### AppConfiguration.swift

- New `@Published var ttsEmotionPrompt: String` (default `""`)
- Wired through `Snapshot`, `makeSnapshot()`, `applySnapshot()`, `defaultSnapshot`

### TTSSynthesisView.swift

- New `VoiceMode.emotionControl = "Emotion Control"` case
- `availableModes` derived from `selectedDef?.family`:
  - `.base` → `[.preset, .clone]`
  - `.customVoice` → `[.preset, .emotionControl]`
  - `.voiceDesign` → `[.voiceDesign]`
- New `emotionControlSection`: speaker dropdown (same as preset) + emotion text field
- Voice string composition in `generateAudio`:
  - `.preset` → `speaker.isEmpty ? nil : speaker`
  - `.clone` → `nil` voice + refAudio + refText
  - `.emotionControl` → `"\(speaker), \(emotionPrompt)"` or just `emotionPrompt` if no speaker selected
  - `.voiceDesign` → `ttsVoiceDescription`

## Data Flow

```
User selects model → family drives availableModes → user picks VoiceMode tab
→ UI inputs map to ttsPresetSpeaker + ttsEmotionPrompt + ttsVoiceDescription + refAudio
→ generateAudio() composes voice: String? per mode → MLXTTSService.synthesize(voice:)
```

## Error Handling

No new error cases required. Existing validation (empty text, model not loaded) is unchanged. An empty emotion prompt with emotion control mode is valid — the speaker name alone is passed as the `voice:` field.

## Testing

TDD — write failing tests first:

1. `TTSModelDefinitionCapabilityTests`: verify `supportsEmotionControl`, `supportsVoiceClone`, and `supportsVoiceDesign` per model family
2. `AppConfigurationTTSEmotionPromptTests`: `ttsEmotionPrompt` default, snapshot round-trip, backward compat decode
3. Update `ModelVariantTTSTests`: counts updated from 6 → 18 to reflect full model catalog

All new test files must be added to the `sources:` list in `Package.swift`.
