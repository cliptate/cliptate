# Escape-to-End Shortcut Mode + Qwen3 Language Fix

## Problem

Two issues with the voice dictation shortcut system:

1. **Hold-to-record is hard to trigger and inflexible.** The current 0.3s hold threshold auto-starts recording and releasing the modifier key immediately ends the session. Users expect a Typeless-style flow: enter mode with a modifier key tap, use Space to start/stop recording freely, and press Escape to end the session.

2. **Qwen3 language parameter is broken under non-English UI.** `Language.qwen3LanguageName` delegates to `displayName`, which returns `String(localized:)`. When the app UI is Chinese/Japanese/Korean, Qwen3 receives localized language names (e.g., "英语") instead of the English names it expects (e.g., "English").

## Design

### 1. Shortcut Mode Rework

#### New Lifecycle

```
Modifier Press → .modeActivated → session .ready
Space (in .ready) → start recording → session .recording
Space (in .recording) → stop recording → session .ready
Space (in .ready again) → start recording again → session .recording
...repeat as needed...
Esc → stop recording (if active), end session → trigger AI Enhance
Modifier Press (while mode active) → toggle off (same as Esc) → end session
```

Key principle: **modifier key only enters/exits mode; Space controls recording; Esc is the canonical end.**

#### KeyboardShortcutManager Changes

- **Remove** hold-to-record infrastructure: `holdTimer`, `isHoldRecording`, `holdThreshold`, `startHoldTimer()`, `cancelHoldTimer()`, `.holdRecordingStarted`, `.holdRecordingEnded`.
- **Add** `.escapePressed` to `ShortcutEvent.Phase`.
- **Add** Escape key detection (keyCode 53) in the CGEventTap callback. When a mode is active and Escape is pressed, emit `.escapePressed` and suppress the event.
- **Simplify** `handleModeKeyPressed()`: first press activates, second press deactivates. No hold timer.
- **Simplify** `handleModeKeyReleased()`: no-op (mode persists after modifier release).

#### ContentView Handler Changes

- **Remove** `.holdRecordingStarted` / `.holdRecordingEnded` case handlers.
- **Add** `.escapePressed` handler: stop recording if active, call `requestEndSession()`.

#### VoiceShortcutState

No changes needed — the existing state machine (`idle → ready → recording → ready → ...`) already supports multi-segment recording via Space toggles.

### 2. Qwen3 Language Name Fix

Replace `displayName` delegation in `Language.qwen3LanguageName` with a hardcoded `switch` returning English-only names that Qwen3 expects:

```swift
public var qwen3LanguageName: String {
    switch self {
    case .auto: return "auto"
    case .english: return "English"
    case .chinese: return "Chinese"
    case .german: return "German"
    case .spanish: return "Spanish"
    case .russian: return "Russian"
    case .korean: return "Korean"
    case .french: return "French"
    case .japanese: return "Japanese"
    case .portuguese: return "Portuguese"
    case .turkish: return "Turkish"
    case .polish: return "Polish"
    case .catalan: return "Catalan"
    case .dutch: return "Dutch"
    case .arabic: return "Arabic"
    case .swedish: return "Swedish"
    case .italian: return "Italian"
    case .indonesian: return "Indonesian"
    case .hindi: return "Hindi"
    case .finnish: return "Finnish"
    case .vietnamese: return "Vietnamese"
    case .hebrew: return "Hebrew"
    case .ukrainian: return "Ukrainian"
    case .greek: return "Greek"
    case .malay: return "Malay"
    case .czech: return "Czech"
    case .romanian: return "Romanian"
    case .danish: return "Danish"
    case .hungarian: return "Hungarian"
    case .tamil: return "Tamil"
    case .norwegian: return "Norwegian"
    case .thai: return "Thai"
    case .urdu: return "Urdu"
    case .croatian: return "Croatian"
    case .bulgarian: return "Bulgarian"
    case .lithuanian: return "Lithuanian"
    case .latin: return "Latin"
    case .maori: return "Maori"
    case .malayalam: return "Malayalam"
    case .welsh: return "Welsh"
    case .slovak: return "Slovak"
    case .telugu: return "Telugu"
    case .persian: return "Persian"
    case .latvian: return "Latvian"
    case .bengali: return "Bengali"
    case .serbian: return "Serbian"
    case .azerbaijani: return "Azerbaijani"
    case .slovenian: return "Slovenian"
    case .kannada: return "Kannada"
    case .estonian: return "Estonian"
    case .macedonian: return "Macedonian"
    case .breton: return "Breton"
    case .basque: return "Basque"
    case .icelandic: return "Icelandic"
    case .armenian: return "Armenian"
    case .nepali: return "Nepali"
    case .mongolian: return "Mongolian"
    case .bosnian: return "Bosnian"
    case .kazakh: return "Kazakh"
    case .albanian: return "Albanian"
    case .swahili: return "Swahili"
    case .galician: return "Galician"
    case .marathi: return "Marathi"
    case .punjabi: return "Punjabi"
    case .sinhala: return "Sinhala"
    case .khmer: return "Khmer"
    case .shona: return "Shona"
    case .yoruba: return "Yoruba"
    case .somali: return "Somali"
    case .afrikaans: return "Afrikaans"
    case .occitan: return "Occitan"
    case .georgian: return "Georgian"
    case .belarusian: return "Belarusian"
    case .tajik: return "Tajik"
    case .sindhi: return "Sindhi"
    case .gujarati: return "Gujarati"
    case .amharic: return "Amharic"
    case .yiddish: return "Yiddish"
    case .lao: return "Lao"
    case .uzbek: return "Uzbek"
    case .faroese: return "Faroese"
    case .haitianCreole: return "Haitian Creole"
    case .pashto: return "Pashto"
    case .turkmen: return "Turkmen"
    case .nynorsk: return "Nynorsk"
    case .maltese: return "Maltese"
    case .sanskrit: return "Sanskrit"
    case .luxembourgish: return "Luxembourgish"
    case .burmese: return "Burmese"
    case .tibetan: return "Tibetan"
    case .tagalog: return "Tagalog"
    case .malagasy: return "Malagasy"
    case .assamese: return "Assamese"
    case .tatar: return "Tatar"
    case .hawaiian: return "Hawaiian"
    case .lingala: return "Lingala"
    case .hausa: return "Hausa"
    case .bashkir: return "Bashkir"
    case .javanese: return "Javanese"
    case .sundanese: return "Sundanese"
    case .cantonese: return "Cantonese"
    }
}
```

This ensures language names are always English regardless of app UI locale.

## Testing

### Shortcut Mode Tests

- Modifier tap activates mode, second tap deactivates
- Escape while mode active emits `.escapePressed`
- Modifier release does **not** deactivate mode
- Space toggles recording multiple times within a session
- Escape while recording stops recording and ends session
- Escape key is suppressed (not forwarded) when mode is active

### Qwen3 Language Tests

- Each Language enum case returns a non-localized English string from `qwen3LanguageName`
- `.auto` returns `"auto"`
- `qwen3LanguageName` output does not change when app locale changes (verified by checking it does not use `String(localized:)`)

## Scope

- `KeyboardShortcutManager.swift` — remove hold-to-record, add Escape handling
- `ContentView.swift` — update handler for new event phases
- `Language.swift` — fix `qwen3LanguageName` 
- `KeyboardShortcutManagerHoldTests.swift` — rewrite for new behavior
- New test file for Qwen3 language name verification
