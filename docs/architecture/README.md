# Architecture

Cliptate is a native SwiftUI macOS application with an independently testable SwiftPM
library target. The application lives in `Sources/Cliptate`; Xcode builds its real
entry point, while SwiftPM excludes that entry point and exposes the remaining code
to unit tests. [CONTEXT.md](../../CONTEXT.md) defines the domain vocabulary.

## Main boundaries

- **Application and navigation:** `Cliptate.swift` restores configuration and creates
  the scenes. `Views/ContentView.swift` routes sections; AI Cut owns per-video editing
  state rather than losing it on file switches.
- **Configuration:** `AppConfiguration` owns settings. `ConfigurationRuntime` orders
  restoration, presets, persistence, and warmup.
- **Inference:** `ModelRuntime` coordinates sessions. `ModelDownloadManager` handles
  disk artifacts; `ModelCacheManager` handles loaded models, leases, and eviction.
  Active workflows use the cache manager rather than legacy `TranscriberPool`.
- **Transcription and dubbing:** batch and streaming runtimes manage model use,
  segmentation, alignment, speaker attribution, and post-processing. TTS and dubbing
  runtimes own synthesis and retained output.
- **Editing and export:** segment processing produces timing-aware decisions consumed
  by video, FCPXML, and subtitle exporters. `SegmentIdentifier` preserves selection
  across reshaped segments.
- **Subscription:** RevenueCat, access control, and paywall code are included. SDK
  configuration is supplied locally, independently from source distribution.
- **Platform capabilities:** `AccessibilityGate` selects capability behavior according
  to the `APP_STORE` compilation condition; see [ADR 0001](../adr/0001-accessibility-gate-for-app-store.md).

## Supporting records

- [Development and build instructions](../development.md)
- [Migration record](../migration.md)
- [Historical architecture investigations](archive/ARCHITECTURE_INDEX.md)
- Existing design records under `docs/plans/`, `docs/superpowers/`, and `openspec/`

The archived investigations and historical plans describe earlier revisions. Use
the current source, manifests, and this guide for present-day paths and behavior.
