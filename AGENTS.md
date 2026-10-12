# Cliptate development instructions

Work directly in this checkout unless the user requests a worktree.
Read `docs/development.md` for build prerequisites, signing, and optional billing configuration.
Read `CONTEXT.md` when changing domain concepts and `docs/architecture/README.md` when changing module boundaries.

Use Conventional Commits for every new commit and squash-merge title; follow the
commit-message conventions in `CONTRIBUTING.md`.

## Validation

Use `swift build` and `swift test` for library changes. Use focused regression tests
for changed behavior; use test-first implementation when practical.
For app lifecycle, resources, or Xcode changes, also run
`./scripts/build-and-run.sh build` with full Xcode selected.
SwiftPM discovers tests automatically in `Tests/CliptateTests`.

## State and runtime conventions

- `AppConfiguration` owns settings. Persist new fields through the snapshot and preset paths.
- `ConfigurationRuntime` owns restore, persistence, presets, and deferred warmup ordering.
- Use `ModelRuntime` and `ModelCacheManager` for active inference; `TranscriberPool` is legacy.
- Keep per-video editing state in `VideoState`; use `SegmentIdentifier` across segment reshaping.
- Preserve `APP_STORE` capability behavior; read `docs/adr/0001-accessibility-gate-for-app-store.md` before changing accessibility or shortcut delivery.

## Resources and configuration

Localize new user-visible strings in `Sources/Cliptate/Localizable.xcstrings` for
zh-Hans, ja, ko, and de. Use localized string keys in SwiftUI and `String(localized:)`
for String parameters. Native language names and pure format/separator keys may remain unchanged.
Keep signing material, billing keys, user data, and downloaded model weights outside Git.
Preserve production bundle identifiers unless the task explicitly changes distribution identity.

## Context on demand

- For version releases or release-note updates, follow the concise template in `docs/release-notes/README.md` and commit the version document before creating the tag.
- For issue work, read `docs/agents/issue-tracker.md`; issues belong to `cliptate/cliptate`.
- For triage, read `docs/agents/triage-labels.md`.
- For existing product requirements, read `docs/agents/legacy-requirements.md`.
