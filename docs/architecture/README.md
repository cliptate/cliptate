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
- **Command line:** `CliptateCommand` owns parsing, terminal output, and file writes;
  the lightweight `CliptateCLIKit` target owns the CLI request session through
  `CLIRequestClient` and `CLIRequestServer`, alongside the wire protocol and formatters.
  The client owns authenticated startup retries; the server owns one-use credentials,
  transcription and TTS admission, ordered progress and terminal events, and disconnect cleanup.
  Application launch and the framed `CLIChannel` transport are adapters at internal seams.
  `CLIApplicationServer` owns the direct-build listener, while `CLIRequestHandler`
  uses the existing configuration, batch runtime, and TTS session runtime. Dictionary
  mutations flush through `ConfigurationRuntime` before success. History queries use
  `HistoryRuntime` and bounded portable text projections, including applied AI correction
  evidence; they never read the history file from the CLI process. Inference admission
  stays occupied until cancelled work exits; dictionary requests remain available
  during transcription or TTS. The command owns a private staging WAV passed by bookmark; it publishes the output atomically after synthesis succeeds,
  keeping large audio outside JSON frames and preserving existing files on failure.
  Callers and real-loopback tests cross the same request interfaces. Only direct
  builds embed the helper and activate the listener. See [CLI documentation](../cli.md).
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
- **Application updates:** `AppUpdateManager` owns one Sparkle updater shared by
  the app menu, status item, and settings. Distribution metadata and receipt checks
  live in `AppUpdateConfiguration`; update preferences belong to Sparkle. Release
  automation generates feeds from notarized DMGs. `AppUpdateUserDriver` delegates
  standard interaction to Sparkle and presents the verified installation prompt
  after installer preparation. See [in-app updates](../updates.md).
- **Release-channel policy:** `scripts/release_policy.py` owns pure build and
  publication decisions. `scripts/release-policy.py` adapts them to GitHub settings
  and JSON consumed by the workflow and publishing script. Signing, notarization,
  upload ordering, and tag mutations remain in the existing scripts. Initial
  checkout and concurrency expressions run before repository code is available;
  focused checks keep those expressions aligned with the policy.
- **Platform capabilities:** `AccessibilityGate` selects capability behavior according
  to the `APP_STORE` compilation condition; see [ADR 0001](../adr/0001-accessibility-gate-for-app-store.md).

## Supporting records

- [Development and build instructions](../development.md)
- [Release vocabulary](../../GLOSSARY.md)
- [Historical architecture investigations](archive/ARCHITECTURE_INDEX.md)
- Existing design records under `docs/plans/` and `docs/superpowers/`

The archived investigations and historical plans describe earlier revisions. Use
the current source, manifests, and this guide for present-day paths and behavior.
