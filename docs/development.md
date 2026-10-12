# Building Cliptate

## Requirements

- An Apple Silicon Mac running macOS 15 or newer (the Xcode test target requires 15.5).
- Xcode 26 or newer with Swift 6.2 or newer and the macOS SDK.
- Internet access for the first dependency resolution and model downloads.

If command-line tools are selected instead of full Xcode, set the environment for
your terminal session without changing the system-wide selection:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Build and test

```bash
git clone https://github.com/cliptate/cliptate.git
cd cliptate
swift package resolve
swift build
swift test
./scripts/build-and-run.sh build
./scripts/run.sh
```

SwiftPM builds the library and runs unit tests. It deliberately excludes the `@main`
app entry point. Use `Cliptate.xcodeproj` or the build script for the actual application
bundle, resource compilation, sandbox entitlements, and MLX Metal integration.
Debug builds produce **Cliptate Dev.app** with bundle identifier `com.cliptate.dev`.
The shared **Cliptate Dev** Xcode scheme runs, tests, profiles, and archives this
Debug app. Release builds retain **Cliptate.app** and the production identifier
`com.voicepink.voicepinkpro`; CI packaging always selects Release.

### Preserve installed privacy permissions during development

Development and production are separate applications, with separate macOS privacy
consent and UserDefaults domains. Configuration, presets, transcript history, and
recordings use `Application Support/Cliptate Dev` for development and the existing
`Application Support/Cliptate` for production. Sandboxed builds keep these paths
inside their respective containers. Development never migrates the production or
legacy VoiceFlowPro data. Direct builds can intentionally share model weights in
the Hugging Face cache.

The development CLI uses its own `cliptate-dev-cli` URL scheme and a separate local
port range. The embedded CLI selects its containing app; standalone CLI defaults
to production. Set `CLIPTATE_APP` to a Dev app bundle to explicitly select it.
Development disables the production updater, including if a local configuration
accidentally supplies the production feed and signing key.

The build script automatically selects a single available **Apple Development**
identity, keeping development consent stable across rebuilds. If multiple identities
are available, select one with `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM`. For IDE
launches, set `CLIPTATE_DEVELOPMENT_TEAM` in the ignored `config/Local.xcconfig`.
Without a certificate the script falls back to ad-hoc signing and disables Hardened
Runtime; this works for public source builds, but development consent can reset
after rebuilding. See Apple's
[code-signing requirements explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Debug (Cliptate Dev) defaults to the free direct-distribution channel, without
App Sandbox and with Accessibility-backed capabilities and the embedded CLI:

```bash
./scripts/run.sh
```

To test the App Store channel using the same independent development identity:

```bash
CLIPTATE_APP_STORE=YES ./scripts/run.sh
```

The `APP_STORE` capability gate remains independent of development identity.
Release keeps its App Store default; `CLIPTATE_APP_STORE=NO` explicitly selects
the free direct-distribution channel for either configuration.

Before `run`, `--debug`, `--logs`, and `--verify`, the script checks identity
compatibility against installed Cliptate and Cliptate Dev bundles in `/Applications`
and `~/Applications`. Different bundle IDs can coexist. The same bundle ID must
have compatible signing requirements in both directions. For another installation
location, set `CLIPTATE_INSTALLED_APP` to that app bundle. `build` never launches.
When deliberately testing permission resets, `CLIPTATE_ALLOW_PERMISSION_RESET=YES`
bypasses the launch check. Official DMG packaging rejects development identity.
Permissions already invalidated by an earlier identity change must be enabled
again in System Settings; development does not copy production consent.

## DMG packages and CI downloads

The **Test** workflow (`.github/workflows/ci.yml`) resolves the locked dependencies,
builds the SwiftPM library, verifies license notices, and runs unit tests on every
push (all branches and tags) and pull request. It also supports manual runs.
New pushes do not cancel tests for earlier commits.

Both macOS workflows use GitHub Actions caches isolated by OS, CPU architecture,
the macOS build, Xcode/Swift versions, and dependency inputs. Test runs cache the
SwiftPM `.build` directory per commit and can restore the latest build with the
same manifest and lockfile. Unchanged dependency products can be reused; fresh
checkout timestamps may still cause project sources to recompile. Locked resolution,
library builds, and all tests still run on cache hits.

Packaging caches only SwiftPM downloads/state and Xcode's `SourcePackages`, keyed
by both lockfiles, the manifest, and the Xcode project. It builds and signs the app
on every run. Signing credentials, update configuration, app bundles, and installers
are outside the cached paths. Test and release caches use separate keys and paths.
The first run for new dependency inputs or a changed toolchain populates the cache;
later runs benefit from it. Compare the cache restore/save, resolution, and build
step durations in Actions to measure the net improvement. Increment the `v1` cache
prefix in the relevant workflow to discard old entries if needed.

The independent **Package and release** workflow (`.github/workflows/package.yml`)
builds the macOS application in Release configuration and verifies a compressed
DMG. It runs manually, daily at **03:17 Beijing time** (19:17 UTC on the previous
day), or when a tag other than the reserved `nightly` tag is pushed. Ordinary
branch pushes and pull requests do not build installers.

- Scheduled and manual branch builds use the latest `main` commit and update the rolling
  [Nightly prerelease](https://github.com/cliptate/cliptate/releases/tag/nightly).
- To package manually, open **Package and release** on the
  [Actions page](https://github.com/cliptate/cliptate/actions/workflows/package.yml)
  and choose **Run workflow**. A branch run packages `main` and updates `nightly`; a tag run
  publishes to that tag's release.
- To publish a version, update the app version/build settings and write the detailed
  [version release document](release-notes/README.md), commit both, then push
  a tag such as `git tag v1.0 && git push origin v1.0`. The workflow publishes
  the tagged source to that version's release and never moves version tags.
  The installer is always named `Cliptate.dmg`; its version comes from the app's build settings.

Version release notes are maintained in `docs/release-notes/<tag>.md` and checked
before building. GitHub Release and the Sparkle feed use that document from the
packaged commit; publication appends verified signing, installation, and build
details. Rerunning publication also refreshes an existing release's description.
Nightly keeps its generated build summary and does not require a version document.

Stable releases include the DMG, SHA-256 checksum, and signed `appcast.xml` feed
generated during packaging (the XML is not tracked in Git),
and are publicly downloadable without signing in. Stable publication explicitly
sets Latest. All builds, including Nightly, check that latest stable feed.
Nightly updates replace the previous installer pair and move the `nightly` tag to
the packaged commit; they remain prereleases and do not replace Latest.
Release publication runs separately from the build with `contents: write` and
the built-in `GITHUB_TOKEN`; no personal access token or branch write is required.
See [in-app updates](updates.md) for feed and version ordering.

Each successful packaging run retains the DMG and checksum as separate Actions
artifacts for 14 days; stable runs also retain the signed appcast. These artifact
downloads require signing in to GitHub and contain the files themselves, without
an additional ZIP archive.

To reproduce packaging locally:

```bash
CONFIGURATION=Release ./scripts/build-and-run.sh build
./scripts/package-dmg.sh
cd dist
shasum -a 256 -c Cliptate.dmg.sha256
```

`scripts/package-dmg.sh` also accepts an existing app bundle and output directory:
`./scripts/package-dmg.sh /path/to/Cliptate.app /path/to/output`.
The output is always `dist/Cliptate.dmg` with `Cliptate.dmg.sha256`; version,
build number, and architecture remain in the app metadata and signed appcast.
The image includes `Cliptate.app`, an `Applications`
shortcut, and the project's and dependencies' license notices in `Licenses`.
Open the DMG and drag the app into Applications to install it.

Run `python3 -m unittest discover -s Tests/Automation -v` to verify release
automation safeguards without contacting GitHub or publishing anything.

Release-channel decisions live in `scripts/release_policy.py`. Its command-line
adapter, `scripts/release-policy.py`, supplies build outputs and update settings to
the workflow, and a publication plan to `publish-release.sh`. Change channel rules
there rather than adding tag comparisons to each caller. The workflow's initial
checkout and concurrency expressions must remain aligned with the policy because
they execute before repository scripts are available.

The publication script retains its existing compatibility for ad-hoc installers
and version releases without an appcast when invoked directly. The package
workflow applies the stricter public-release requirements described above:
notarized packages for both channels, plus a signed feed for stable releases.

Local Debug builds prefer Apple Development signing and fall back to ad-hoc signing.
Local Release builds default to ad-hoc signing. CI packages require the Developer ID
distribution setup below and fail before building if credentials are missing.
Ad-hoc builds disable Hardened Runtime so embedded frameworks can load without a
Team ID; Developer ID builds retain Hardened Runtime and timestamped signatures.
An existing release produced before this setup may still be ad-hoc signed; check
its release notes. Only successfully notarized packages are marked as such.

## In-app update configuration

Direct-download builds use Sparkle and a signed appcast. Configure the Actions
variable `SPARKLE_PUBLIC_KEY` and secret `SPARKLE_PRIVATE_KEY` before the next
package run. See [in-app updates](updates.md) for key generation, the shared stable
feed, version ordering, local testing, and App Store distribution requirements.
The `APP_STORE` accessibility capability flag remains unchanged.

## Shared model cache

Direct-download builds use the account's real home directory for
`~/.cache/huggingface/hub` and run without App Sandbox. App Store builds retain
their sandbox container. `HF_HUB_CACHE` and `HF_HOME` overrides
continue to work when their target is accessible to the application.

Models use the Python-compatible `models--<owner>--<repository>/snapshots/<revision>`
layout. Existing snapshots and their blob symlinks are reused without downloading
or copying the weights. Legacy MLX Audio cache directories remain readable.
Repository identity must match the selected model: `mlx-community/Qwen3-0.6B-4bit`
is a text model, while transcription uses repositories such as
`mlx-community/Qwen3-ASR-0.6B-8bit`.

### Whisper transcription

The existing MLX Audio Swift 0.1.5 dependency supplies Whisper; no separate
WhisperKit dependency is needed. The catalog exposes multilingual Tiny, Base,
Small, Medium, Large v3, and Large v3 Turbo, with Turbo recommended when switching
to Whisper. Existing ASR selections remain unchanged. Whisper uses the same
`ModelRuntime`, cache lifecycle, VAD, batch alignment, and live dictation paths.

Models download from `openai/whisper-*` into the shared Hugging Face cache. Only
`model.safetensors` and JSON/text assets are requested, avoiding duplicate weights
for other frameworks and the optional Large v3 FP32 shards. Readiness requires
local tokenizer and generation configuration files as well as weights. Models
are downloaded on demand and are never bundled with the app.

The pinned upstream implementation provides whole-window text with a fixed
30-second window and no word timestamps. Enable forced alignment for precise
editing/subtitle timing. Although the upstream README describes automatic language
detection, its current implementation does not perform a language-detection pass;
Cliptate therefore requires an explicit supported language for Whisper. Legacy
Whisper selections that pointed to Parakeet restore to Turbo; unsupported language
selections normalize to English. Custom vocabulary is applied by the shared
post-processor rather than passed to Whisper as a decoding prompt. Cancellation
is checked between windows; an active synchronous decode must finish first.

The optional real-model regression downloads Tiny and transcribes a synthesized
English fixture. Keep its audio and model files outside the checkout:

```bash
say -v Samantha -o /tmp/cliptate-whisper-smoke.aiff \
  'The quick brown fox jumps over the lazy dog.'
RUN_WHISPER_MODEL_TESTS=1 WHISPER_TEST_AUDIO_PATH=/tmp/cliptate-whisper-smoke.aiff \
  WHISPER_TEST_METALLIB_PATH="$(swift build --show-bin-path)/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
  swift test --filter MLXWhisperTranscriberTests.realModelSmoke
```

### Nemotron transcription

MLX Audio Swift 0.1.5 also supplies NVIDIA Nemotron ASR. Select **Nemotron ASR**
in the model picker for AI Cut and Voice To Text. The recommended checkpoint is
`mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit` (~756 MB); the catalog also
offers the 3.5 bf16 checkpoint (~1.28 GB) and the older English-only 8-bit
checkpoint (~664 MB). Existing selections remain unchanged. These models are free
in both distribution channels and download on demand into the shared model cache.

Nemotron 3.5 exposes automatic language detection and the 28 language families
represented by Cliptate from NVIDIA's transcription-ready and broad-coverage
locales. The eight adaptation-ready locales require fine-tuning and are not offered
as supported selections. Chinese uses the `zh-CN` prompt, Japanese `ja-JP`, and
Norwegian Bokmål `nb-NO`; unsupported prompt identifiers would silently fall back
to automatic detection upstream. The older English checkpoint accepts English only.
See the [NVIDIA language table](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b#supported-languages).

File inference uses bounded 30-second windows and preserves upstream sentence
timestamps. Precise word timing uses the existing optional forced alignment.
The shared batch pipeline uses VAD speech-range timing when alignment is disabled.
Live dictation uses the shared VAD chunk pipeline; it does not yet keep a native
Nemotron encoder cache between microphone chunks. The custom dictionary remains
part of shared post-processing. Cancellation is checked between synchronous
decodes; an active decode finishes before cancellation returns.

Offline readiness requires nonempty safetensors and an embedded vocabulary in
`config.json`; external tokenizer files are unnecessary for the Swift loader.
Checkpoint weights retain the NVIDIA Open Model License and are never bundled.

The optional real-model regression uses synthesized speech and keeps its audio
and downloaded model outside the checkout:

```bash
say -v Samantha -o /tmp/cliptate-nemotron-smoke.aiff \
  'The quick brown fox jumps over the lazy dog.'
RUN_NEMOTRON_MODEL_TESTS=1 NEMOTRON_TEST_AUDIO_PATH=/tmp/cliptate-nemotron-smoke.aiff \
  NEMOTRON_TEST_METALLIB_PATH="$(swift build --show-bin-path)/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
  swift test --filter NemotronASRTranscriberTests.realModelSmoke
```

## Default folder access

Sandboxed builds declare read/write access to Downloads, Movies, Music, and
Pictures, plus a home-relative file-access temporary exception for `/`, covering
the account's home directory and its subdirectories, including Documents and
Desktop. The slash is relative to the user's home, not the filesystem root.
Direct-download builds already run without App Sandbox.

These entitlements do not grant macOS privacy consent: protected folders may
still require the user's permission when first accessed. Mac App Store submissions
must justify the home-directory temporary exception to App Review. See Apple's
[temporary exception documentation](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
and [Documents folder privacy policy](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocumentsfolderusagedescription).

## Apple signing and notarization

For this application's existing identity, use the Qi Li team `FB4W45V73V` and keep
the production bundle identifier `com.voicepink.voicepinkpro`. Create a
**Developer ID Application** certificate with the G2 intermediary in the
[Apple Developer certificate portal](https://developer.apple.com/account/resources/certificates/list).
Apple Development and Mac App Distribution certificates cannot replace this
certificate for public DMG distribution. Follow
[Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
then export the certificate and its matching private key as a password-protected
`.p12` file. Keep the private key, `.p12`, passwords, and downloaded certificates
outside this checkout.

In the repository's **Settings → Secrets and variables → Actions**, configure:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `APPLE_CERTIFICATE_P12_BASE64` | Base64 encoding of the encrypted `.p12` |
| Secret | `APPLE_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |
| Secret | `APPLE_ID` | Apple Account email authorized for this developer team |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for Apple notarization |
| Variable | `APPLE_TEAM_ID` | `FB4W45V73V` |

Create the app-specific password yourself at
[Apple Account](https://account.apple.com/) under **Sign-In and Security →
App-Specific Passwords**. Enter it directly into the repository secret or a trusted
local setup terminal; do not put it in chat, logs, shell history, or source files.
Test runs do not consume signing credentials.

Release builds disable Xcode's base entitlement injection for the app and embedded CLI
so neither carries the debugging-only `com.apple.security.get-task-allow` permission.
Signed packaging checks the actual app entitlements before creating the DMG;
Debug builds retain Xcode's normal debugger configuration.

The package workflow imports exactly one matching Developer ID identity into a
temporary keychain, builds with Hardened Runtime and a secure timestamp, signs
the app and DMG, and submits the DMG with `notarytool`. Publication requires Apple's
`Accepted` status, a successfully stapled and validated ticket, and a Gatekeeper
assessment. The SHA-256 checksum is regenerated after stapling changes the image.
The temporary keychain and credential files are removed even if packaging fails.
Nightly and version-tag releases use the same verification gates.

To opt into signing a local Release build after importing a Developer ID identity
into your keychain:

```bash
export CODE_SIGN_IDENTITY='<Developer ID Application certificate SHA-1 fingerprint>'
export DEVELOPMENT_TEAM=FB4W45V73V
CONFIGURATION=Release ./scripts/build-and-run.sh build
./scripts/package-dmg.sh
```

For local notarization, `scripts/notarize-dmg.sh /path/to/package.dmg` requires
`APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `SIGNING_KEYCHAIN`, and
`RUNNER_TEMP`. Use a dedicated temporary keychain and private temporary directory;
the script stores notarization credentials in that keychain. Never export secrets
in a command that will be recorded in shell history.

## Focused validation

For focused checks:

```bash
swift test --filter SegmentTests
xcodebuild -project Cliptate.xcodeproj -scheme Cliptate \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= test
```

Hardware/model tests may require downloaded models. UI launch tests are opt-in
with `RUN_UI_SMOKE_TESTS=1`; the unit-test scheme does not run the UI target.
Tests omitted from the original SwiftPM source list are preserved in `Tests/Legacy`;
some document removed RevenueCat hooks or obsolete model expectations. See the
[legacy test inventory](../Tests/Legacy/README.md).

`Package.resolved` files are checked in for reproducible dependency selection.
When updating a dependency, update both the SwiftPM manifest and Xcode reference,
resolve both graphs, run `python3 scripts/update-dependency-notices.py`, and run the builds and tests.
MLX Audio Swift 0.1.5, MLX Swift 0.32.3, and MLX Swift LM 3.32.3 are pinned to
exact versions for compatibility; update that inference graph as a unit.
Combine Schedulers 1.2.0 and XCTest Dynamic Overlay 1.11.0 are pinned in both build
graphs because later releases select different IssueReporting package identities
with Swift 6.3 and Swift 6.4.
CI explicitly selects Xcode 26.6 on the macOS 26 Apple Silicon runner. Keep locked
resolution enabled so a clean checkout verifies the complete dependency graph.

## Billing and distribution configuration

Non-`APP_STORE` builds are fully free and do not use App Sandbox: all models and Pro features are available
without a subscription, purchase, or RevenueCat SDK key. These builds do not
initialize billing, show upgrade promotions, or present paywalls. GitHub Release
and Nightly packages explicitly select this channel.

Default Xcode and SwiftPM Debug builds select the free direct channel. Release
builds retain `APP_STORE` and the existing subscription policy. Public source
builds contain no RevenueCat SDK key, so App Store billing stays unconfigured
until you provide one.

To build and test the free direct-distribution channel with either entry point:

```bash
CLIPTATE_APP_STORE=NO swift build
CLIPTATE_APP_STORE=NO swift test
CLIPTATE_APP_STORE=NO ./scripts/build-and-run.sh build
```

The option removes `APP_STORE`, disables App Sandbox, and enables the existing Accessibility-backed
capabilities described in [ADR 0001](adr/0001-accessibility-gate-for-app-store.md).
For an App Store build, set it to `YES` (or omit it for Release). Explicit `YES`
also restores the App Store entitlements, App Sandbox, and disabled CLI URL in
Debug. When building directly in Xcode, Debug already selects the direct channel;
see `config/Local.xcconfig.example` for per-configuration channel overrides.
App Store builds remain sandboxed.
Direct builds copy missing configuration and history from the previous sandbox
container once without removing originals or replacing current direct-build data.

The direct app includes a signed native `cliptate` executable. See [CLI usage and
installation](cli.md) for transcription, TTS, and dictionary commands. The CLI shares
the running application's configuration and model runtime; SwiftPM's standalone
CLI product connects to the app rather than linking the inference libraries.

To connect your own RevenueCat application:

```bash
cp config/Local.xcconfig.example config/Local.xcconfig
```

Set `CLIPTATE_REVENUECAT_API_KEY` to your public Apple SDK key. The ignored local
configuration is consumed by both Debug and Release builds. The same environment
variable can override the key when launching a development build from a terminal
or an Xcode scheme. Secret REST keys must never be embedded in an app.

App Store distribution requires your own signing configuration, store products,
and RevenueCat application. Developer ID distribution requires signing configuration
but no billing configuration. The existing production bundle identifier
is retained to avoid breaking app data and product integration; forks intended for
distribution should choose their own identifier and product IDs.

Both build entry points preserve the `APP_STORE` capability gate and support
explicit channel selection. Consult [ADR 0001](adr/0001-accessibility-gate-for-app-store.md)
before changing the gate.

## Repository layout

```text
Cliptate.xcodeproj/       macOS application and test targets
Package.swift            SwiftPM library and automatically discovered unit tests
Sources/Cliptate/         app entry point, models, services, views, utilities, resources
Tests/CliptateTests/      unit and integration tests, bundled fixtures
Tests/CliptateUITests/    opt-in Xcode UI tests
Tests/Automation/        release automation regression checks
Tests/Legacy/            previously unselected test suites and helpers
Tests/Fixtures/manual/   legacy manual audio sample, outside automated test resources
config/                  shared build settings and local configuration template
scripts/                 build, run, and asset generation tools
assets/                  design source images
docs/                    development, architecture, ADRs, plans, and release notes
.github/                 CI and contributor templates
.agents/skills/          repository-local agent skills and supporting references
```

The app uses a single module with Models, Services, Views, and Utilities boundaries.
