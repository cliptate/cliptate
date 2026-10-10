# WhisperCutPro → Cliptate

The application was migrated from `sysulq/WhisperCutPro` revision
`32d7b579c8d2992c169d8408fd7e70fa9d783998` into the existing
`cliptate/cliptate` repository on 2026-10-10. The source checkout is preserved.

## Path changes

| Previous path | Current path |
| --- | --- |
| `Sources/Cliptate.xcodeproj` | `Cliptate.xcodeproj` |
| `Sources/CliptateTests` | `Tests/CliptateTests` |
| `Sources/CliptateUITests` | `Tests/CliptateUITests` |
| `script/build_and_run.sh` | `scripts/build-and-run.sh` |
| `generate_icons.sh` | `scripts/generate-icons.sh` |
| Root architecture investigation documents | `docs/architecture/archive/` |
| `icon_clean.png` | `assets/design/icon-clean.png` |
| `test.wav` | `Tests/Fixtures/manual/test.wav` |

All tracked application sources, tests, resources, design assets, specifications,
and engineering records are retained. Existing multilingual Cliptate READMEs remain
the public entry points. Root run scripts remain compatibility entry points.

Machine/editor settings, transient brainstorming state, and installed agent/plugin
skill copies are not application code and were omitted. The imported repository
history was not merged: this keeps the existing Cliptate history and avoids publishing
old configuration that predates the current cleanup. Attribution in source files is
preserved. Original project instructions are retained as reference in
`docs/agents/legacy-requirements.md` with current paths and repository names.

## Build changes

SwiftPM follows standard Sources/Tests conventions and automatically discovers tests.
The 12 files omitted from the original SwiftPM source list are preserved in
`Tests/Legacy/CliptateTests`, outside the active SwiftPM and Xcode unit-test targets.
This preserves the previous active SwiftPM suite while retaining legacy code for
future repairs; automatic discovery initially exposed strict-concurrency failures
in the old Paywall view test.
The localization catalog is explicitly registered as a package resource. Xcode's
synchronized groups and entitlement paths point to the new locations. Machine-specific
fixture paths and the one localization test's relative source lookup were updated.
FireRed fixture lookup supports both the copied SwiftPM resource directory and
Xcode's flattened resources. The CLI export regression test explicitly enables
translation and disables padding to match its existing expected output.

The original signing team and embedded RevenueCat SDK key were removed. Billing can
be configured with an ignored local xcconfig or a launch-time environment variable.
The complete subscription code and its existing access policy are preserved.
The production bundle identifier and `APP_STORE` condition are retained.

MLX Swift and MLX Swift LM are pinned to 0.31.3 and 3.31.3 respectively. The
newer automatically selected MLX graph failed to compile the pinned MLX Audio
Parakeet implementation because of stricter Sendable closure requirements. Direct
imports of MLX, MLXLMCommon, and HuggingFace are now declared in both build graphs.

The project source is licensed under MIT. Dependencies and separately downloaded
model weights retain their own terms; see [third-party notices](../THIRD_PARTY_NOTICES.md).

## Migration validation

Validated on Apple Silicon with Xcode 27.0 and Swift 6.4 on 2026-10-10:

- `swift build` completed successfully.
- `swift test` passed all 680 tests in 105 suites.
- `./scripts/build-and-run.sh build` produced `Cliptate.app` with macOS 15.0 as its deployment target.
- `codesign --verify --deep --strict` validated the ad-hoc signed app.
- Both dependency locks selected identical revisions; 22 dependency notice copies matched their locked checkouts.
- The built application's RevenueCat configuration was empty, and credential-pattern scanning found no embedded token/private-key matches in staged project text.
- All application, test, resource, and engineering files selected for migration were accounted for; the original WhisperCutPro checkout remains unchanged.

The compiled application was not launched for an interactive smoke test. The original
Swift source carries some compiler warnings; dependencies also emit Metal/C++ warnings.
These did not prevent the validated builds or tests.
