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
./run.sh
```

SwiftPM builds the library and runs unit tests. It deliberately excludes the `@main`
app entry point. Use `Cliptate.xcodeproj` or the build script for the actual application
bundle, resource compilation, sandbox entitlements, and MLX Metal integration.
The script uses ad-hoc signing and a deterministic `.build/xcode` output directory;
no paid developer account or original maintainer's signing team is required.

## DMG packages and CI downloads

The **Test** workflow (`.github/workflows/ci.yml`) resolves the locked dependencies,
builds the SwiftPM library, verifies license notices, and runs unit tests on every
push (all branches and tags) and pull request. It also supports manual runs.
New pushes do not cancel tests for earlier commits.

The independent **Package and release** workflow (`.github/workflows/package.yml`)
builds the macOS application in Release configuration and verifies a compressed
DMG. It runs manually, daily at **03:17 Beijing time** (19:17 UTC on the previous
day), or when a tag other than the reserved `nightly` tag is pushed. Ordinary
branch pushes and pull requests do not build installers.

- Scheduled builds use the latest `main` commit and update the rolling
  [Nightly prerelease](https://github.com/cliptate/cliptate/releases/tag/nightly).
- To package manually, open **Package and release** on the
  [Actions page](https://github.com/cliptate/cliptate/actions/workflows/package.yml)
  and choose **Run workflow**. A branch build updates `nightly`; a tag build
  publishes to that tag's release.
- To publish a version, update the app version/build settings, commit, then push
  a tag such as `git tag v1.8.0 && git push origin v1.8.0`. The workflow publishes
  the tagged source to that version's release and never moves version tags.
  The DMG filename and application version come from the app's build settings.

Releases include the DMG, SHA-256 checksum, and signed `appcast.xml` update feed and are publicly downloadable
without signing in. Nightly updates replace the previous installer pair and move
the `nightly` tag to the packaged commit; they do not become the latest stable
release. Release publication runs separately from the build with `contents: write`
permission and the built-in `GITHUB_TOKEN`; no personal access token is required.

Each successful packaging run also retains the DMG, checksum, and appcast as separate
Actions artifacts for 14 days. These artifact downloads require signing in to
GitHub and contain the files themselves, without an additional ZIP archive.

To reproduce packaging locally:

```bash
CONFIGURATION=Release ./scripts/build-and-run.sh build
./scripts/package-dmg.sh
cd dist
shasum -a 256 -c Cliptate-*.dmg.sha256
```

`scripts/package-dmg.sh` also accepts an existing app bundle and output directory:
`./scripts/package-dmg.sh /path/to/Cliptate.app /path/to/output`.
The default output is `dist/Cliptate-<version>-<build>-macOS-arm64.dmg`, using the
built app's metadata. The image includes `Cliptate.app`, an `Applications`
shortcut, and the project's and dependencies' license notices in `Licenses`.
Open the DMG and drag the app into Applications to install it.

Run `python3 -m unittest discover -s Tests/Automation -v` to verify release
automation safeguards without contacting GitHub or publishing anything.

Local source builds default to ad-hoc signing. CI packages require the Developer ID
distribution setup below and fail before building if credentials are missing.
An existing release produced before this setup may still be ad-hoc signed; check
its release notes. Only successfully notarized packages are marked as such.

## In-app update configuration

Direct-download builds use Sparkle and a signed appcast. Configure the Actions
variable `SPARKLE_PUBLIC_KEY` and secret `SPARKLE_PRIVATE_KEY` before the next
package run. See [in-app updates](updates.md) for key generation, stable/Nightly
feeds, version ordering, local testing, and App Store distribution requirements.
The `APP_STORE` accessibility capability flag remains unchanged.

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

Release builds disable Xcode's base entitlement injection so distribution apps
do not carry the debugging-only `com.apple.security.get-task-allow` permission.
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
MLX Swift 0.31.3 and MLX Swift LM 3.31.3 are intentionally pinned for compatibility
with the selected MLX Audio revision; update that inference graph as a unit.
Combine Schedulers 1.2.0 and XCTest Dynamic Overlay 1.11.0 are pinned in both build
graphs because later releases select different IssueReporting package identities
with Swift 6.3 and Swift 6.4.
CI explicitly selects Xcode 26.6 on the macOS 26 Apple Silicon runner. Keep locked
resolution enabled so a clean checkout verifies the complete dependency graph.

## Billing and distribution configuration

The complete subscription implementation is included. Public source builds contain
no RevenueCat SDK key; billing stays unconfigured until you provide one. Premium
model download access continues to follow the existing subscription policy.

To connect your own RevenueCat application:

```bash
cp config/Local.xcconfig.example config/Local.xcconfig
```

Set `CLIPTATE_REVENUECAT_API_KEY` to your public Apple SDK key. The ignored local
configuration is consumed by both Debug and Release builds. The same environment
variable can override the key when launching a development build from a terminal
or an Xcode scheme. Secret REST keys must never be embedded in an app.

App Store or Developer ID distribution requires your own signing configuration,
store products, and RevenueCat application. The existing production bundle identifier
is retained to avoid breaking app data and product integration; forks intended for
distribution should choose their own identifier and product IDs.

Both build entry points retain the `APP_STORE` compilation condition. Consult
[ADR 0001](adr/0001-accessibility-gate-for-app-store.md) before changing that condition.

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
openspec/                existing change proposals and specifications
.github/                 CI and contributor templates
.agents/skills/          repository-local agent skills and supporting references
```

The app remains a single module: this migration preserves its existing Models,
Services, Views, and Utilities boundaries instead of changing runtime ownership.
