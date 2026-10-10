# WhisperCutPro Architecture Investigation - Quick Index

This analysis covers the transcription engine architecture with focus on replacing FluidAudio-based Parakeet with mlx-audio support.

## 📄 Documentation Files

### 1. **INVESTIGATION_SUMMARY.md** ← START HERE
- **Length:** 558 lines (~30 min read)
- **Best for:** Executive overview, key decisions, quick reference
- **Contains:**
  - Quick reference table of all three engines
  - Where engines are defined & selected (with code examples)
  - MLXAudio/Qwen3 current implementation
  - Current FluidAudio Parakeet architecture
  - Test coverage analysis
  - TDD recommendations with specific files to modify
  - Implementation checklist

### 2. **ARCHITECTURE_ANALYSIS.md** ← DETAILED REFERENCE
- **Length:** 598 lines (~40 min read)
- **Best for:** Deep technical details, implementation patterns, file paths
- **Contains:**
  - All information from INVESTIGATION_SUMMARY
  - PLUS: Complete code snippets with line numbers
  - PLUS: Detailed streaming module architectures
  - PLUS: Full list of all FluidAudio imports (9+ files)
  - PLUS: Complete test file listing and patterns
  - PLUS: File location appendix with directory tree
  - PLUS: Key insights for replacement implementation

## 🎯 Quick Answers

**"Where do I start?"**
→ Read INVESTIGATION_SUMMARY.md Section 1 & 6

**"How does engine selection work?"**
→ INVESTIGATION_SUMMARY.md Section 1 or ARCHITECTURE_ANALYSIS.md Section 1.3

**"What files need to change?"**
→ INVESTIGATION_SUMMARY.md Section 6 (Priority 1 list)

**"How should I structure tests?"**
→ INVESTIGATION_SUMMARY.md Section 6 + ARCHITECTURE_ANALYSIS.md Section 4.3

**"What pattern should I follow?"**
→ Study Qwen3StreamingModule in ARCHITECTURE_ANALYSIS.md Section 2.2

**"Are there existing tests for Parakeet?"**
→ No - see INVESTIGATION_SUMMARY.md Section 4 (Test Gap Analysis)

## 🔑 Key Findings Summary

### Three Transcription Engines
| Engine | Current | Library | Status |
|--------|---------|---------|--------|
| Whisper | WhisperTranscriber.swift | WhisperKit | ✓ Working |
| Parakeet | FluidAudioStreamModule.swift + FluidAudioTranscriptionModule.swift | FluidAudio | ✓ Working, needs MLX-audio replacement |
| Qwen3 ASR | Qwen3ASRTranscriber.swift + Qwen3StreamingModule.swift | mlx-audio-swift | ✓ Already MLX-audio based |

### Engine Selection Flow
```
TranscriberType.createTranscriber() 
  → VoiceTranscriber.configureEngine() 
  → ModelCacheManager.getASRTranscriber() 
  → Type-specific module (parakeetModule, whisperModule, qwen3Module)
```

### Files Recommended for Change (Priority 1)
1. **FluidAudioStreamModule.swift** (429 lines) - Replace transcriber impl
2. **FluidAudioTranscriptionModule.swift** (429 lines) - Replace streaming impl
3. **DataTypes.swift** - Update model classifications if needed
4. **VoiceTranscriber.swift** (750+ lines) - Update imports/references
5. **ModelCacheManager.swift** - NO CHANGES NEEDED (already compatible)

### Pattern to Follow
**Use Qwen3StreamingModule as a template:**
- Chunk-based audio processing (~2 second chunks for Qwen, 0.1s for Parakeet)
- AVAudioEngine input tap → buffer → process → accumulate
- Callback delivery (onAudioLevel, onInterimText)
- @MainActor coordination

### Test Gap
- **Qwen3 streaming:** Has tests (Qwen3StreamingSpeechAccumulatorTests.swift)
- **Parakeet streaming:** No tests (clean slate for TDD)

### Compatibility News - All Good! ✓
- Protocol consistency: Both must implement Transcriber + ChunkTranscriber
- Model cache: ModelCacheManager already handles any Transcriber type
- Build system: mlx-audio-swift already in Package.swift
- No breaking changes needed to existing architecture

## 📊 File Importance Matrix

```
Priority  | File                              | Action
----------|----------------------------------|------------------
HIGH      | FluidAudioStreamModule.swift     | REPLACE (~430 lines)
HIGH      | FluidAudioTranscriptionModule    | REPLACE (~430 lines)
HIGH      | VoiceTranscriber.swift           | UPDATE imports
HIGH      | DataTypes.swift                  | VERIFY + maybe update
MEDIUM    | ModelDownloadManager.swift       | CHECK
MEDIUM    | Package.swift                    | VERIFY
LOW       | ModelCacheManager.swift          | NO CHANGES
REFERENCE | Qwen3StreamingModule.swift       | COPY PATTERN
TEST      | ModelSelectionUIFlowTests.swift  | ADD tests
TEST      | NEW: ParakeetMLXTranscriberTests | CREATE
TEST      | NEW: ParakeetMLXStreamingTests   | CREATE
```

## 🧪 Test Strategy (TDD)

### Phase 1: Unit Tests
- [ ] ParakeetMLXTranscriber.warmUpModelWithProgress()
- [ ] ParakeetMLXTranscriber.transcribeChunk()
- [ ] Model state transitions
- [ ] Language validation

### Phase 2: Integration Tests
- [ ] Engine selection dispatch (factory pattern)
- [ ] ModelCacheManager integration
- [ ] Streaming pipeline (audio → chunks → transcription)
- [ ] Callback delivery

### Phase 3: E2E Tests
- [ ] Full transcription workflow with UI
- [ ] Engine switching
- [ ] Model caching and reuse

## 📚 Reference Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ VoiceTranscriber (@MainActor)                               │
│ ├─ parakeetModule: ParakeetTranscriptionModule              │
│ ├─ whisperModule: WhisperStreamingModule                    │
│ └─ qwen3Module: Qwen3StreamingModule                        │
└─────────────────────────────────────────────────────────────┘
           ↓ (calls)
┌─────────────────────────────────────────────────────────────┐
│ ModelCacheManager (actor)                                   │
│ ├─ getASRTranscriber() → creates via factory               │
│ └─ Lifecycle management (load, cache, cleanup)             │
└─────────────────────────────────────────────────────────────┘
           ↓ (dispatches)
┌─────────────────────────────────────────────────────────────┐
│ Transcriber Protocol                                        │
│ ├─ WhisperTranscriber (WhisperKit library)                 │
│ ├─ FluidAudioTranscriber (FluidAudio library) ← REPLACE    │
│ └─ Qwen3ASRTranscriber (mlx-audio-swift library) ✓         │
└─────────────────────────────────────────────────────────────┘
```

## 🔗 Related Documents in Repo

- `CLAUDE.md` - Architecture overview
- `docs/plans/2026-02-09-qwen3-asr-integration.md` - MLX integration guide
- `Package.swift` - Dependencies

## 📝 Notes

- All three engines already follow the **same protocol** (Transcriber)
- Qwen3 implementation provides a **good reference** for MLX-based approach
- **No protocol changes** needed for replacement
- **ModelCacheManager** will work with new implementation automatically
- FluidAudio used in **9+ files** (consider if keeping for Kokoro TTS)

---

**Generated:** March 2025  
**Scope:** WhisperCutPro Parakeet → mlx-audio replacement analysis
