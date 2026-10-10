# SplitNatural Design

## Problem

The existing split strategies (by silence, by sentence punctuation, by character count) either
rely on punctuation cues or produce mechanically even splits. For languages like Chinese that
lack word-boundary spaces, a semantically aware split that respects part-of-speech structure
produces more natural subtitle line breaks.

## Approach

Add a new `SegmentSplitByNatural` strategy that uses Apple's `NaturalLanguage` framework
(`NLTagger`) to score candidate split points by POS tag weight and proximity to the text
midpoint, then maps the winning character index to the nearest word timing boundary.

## Components

### `SegmentSplitByNatural.swift` (new file)

- `Options.minLength: Int = 20` — skip segments shorter than this
- Scans `segment.text` with `NLTagger(schemes: [.lexicalClass])`
- Scores each gap between tokens: `score = nextToken.weight / (1 + distanceFromCenter × 0.5)`
- POS weights: punctuation 10, conjunction 8, preposition 5, verb 3, noun 1
- Maps winning char index to nearest word boundary when `words` is present
- Falls back to character-ratio timing interpolation when `words` is nil

### `SegmentProcess.Operation` (extend)

```swift
case splitByNatural(SegmentSplitByNatural.Options)
```

### `AppConfiguration` / `Snapshot` (extend)

- New `splitByNatural: Bool`, default `false`

### `ControlPanelConfigurationView` (UI)

- Toggle "Smart Split (NL)" below the "Split By Sentence" toggle

### `AICutView` pipeline

- Append `.splitByNatural(.init())` when `config.splitByNatural` is true, after `splitBySentence`

## Trade-offs

| Aspect | Decision |
|--------|----------|
| Timing accuracy | Map to word boundary (not char interpolation) when words available |
| Recursion | Single binary split per call; pipeline can chain multiple passes |
| Fallback | Char-ratio interpolation for segments without word timings |
