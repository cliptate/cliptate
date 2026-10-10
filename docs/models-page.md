# Models Page Guide

The Models page is the central place to manage transcription, alignment, and speech-synthesis models.

## What You Can Do

- Download or remove ASR, align, and TTS models
- Set the active ASR model from the model card
- Set or clear the active align model
- Choose the active TTS engine, model, and voice settings
- Preload the active align/TTS runtime to avoid first-use latency
- Clear cached runtime models while keeping the active ASR model

## Model Status

The header shows live cache state for active model roles:

- `Not Loaded`: model is configured but not currently in memory
- `Loading`: model is warming up
- `Loaded`: model is cached and ready to use
- `Error`: load failed; use the retry action

Cache memory usage is shown both as total (`Cache Memory`) and per active role badge.

## Language Filtering

Language pickers now adapt to model capabilities:

- ASR language list follows the active ASR model
- Alignment language list follows the selected align model
- TTS language list follows the selected TTS model/engine

If a previously selected language becomes unsupported after switching models, the app automatically falls back to a supported language and shows a notice.

## Typical Workflow

1. Download needed ASR/align/TTS models.
2. Set the active ASR model and (optionally) an align model.
3. Configure TTS engine/model/voice in the TTS selection card.
4. Use `Preload Align` or `Preload TTS` before long processing jobs.
5. Use `Clear Cache` when you want to reclaim memory.
