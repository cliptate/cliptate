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
Tests/Legacy/            previously unselected test suites and helpers
Tests/Fixtures/manual/   legacy manual audio sample, outside automated test resources
config/                  shared build settings and local configuration template
scripts/                 build, run, and asset generation tools
assets/                  design source images
docs/                    development, architecture, ADRs, plans, and release notes
openspec/                existing change proposals and specifications
.github/                 CI and contributor templates
```

The app remains a single module: this migration preserves its existing Models,
Services, Views, and Utilities boundaries instead of changing runtime ownership.
