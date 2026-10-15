# Architecture

Cliptate uses three SwiftPM modules with matching product names:

- `CliptateCore` (`Sources/CliptateCore`) is the shared library for transcription data,
  language and model metadata, transcript sessions, segment processing, and CLI
  parsing, formatting, transport, and request sessions. It depends only on system
  frameworks and does not import the application or its inference/UI dependencies.
- `Cliptate` (`Sources/Cliptate`) is the SwiftUI app executable. It depends on Core
  and owns UI, configuration, inference runtimes, billing, updates, and OS adapters.
  Concrete transcriber construction and model access policy stay in this module.
- `CliptateCLI` (`Sources/CliptateCLI`) is the command-line executable. It depends
  only on Core and sends inference requests to the app, sharing its model lifecycle.
  The app bundle installs this executable as `Contents/Helpers/cliptate`.

`CliptateCoreTests` depends only on Core; `CliptateTests` covers the app and its
integration with Core. The executable filenames also remain distinct on
case-insensitive macOS filesystems.

`scripts/app_bundle.py` assembles resources, Metal shaders, embedded code, and signing
into a distributable `.app`. `config/app.json` owns version and update defaults;
`Package.swift` and the root lockfile own the single dependency graph. [CONTEXT.md](../../CONTEXT.md) defines the domain vocabulary.

## Main boundaries

- **Application and navigation:** `Cliptate.swift` restores configuration and creates
  the scenes. `Views/ContentView.swift` routes sections; AI Cut owns per-video editing
  state rather than losing it on file switches.
- **Configuration:** `AppConfiguration` owns settings. `ConfigurationRuntime` orders
  restoration, presets, persistence, and warmup.
- **Command line:** `CliptateCommand` owns parsing, terminal output, and file writes;
  the shared `CliptateCore` library owns the CLI request session through
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
  download and error interaction to Sparkle, publishes an actionable update offer
  for the sidebar, and presents the verified installation prompt after installer
  preparation. See [in-app updates](../updates.md).
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
