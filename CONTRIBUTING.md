# Contributing to Cliptate

Start with the [development guide](docs/development.md) and
[architecture guide](docs/architecture/README.md).

1. Fork the repository and create a branch for one focused change.
2. Describe the problem in an [issue](https://github.com/cliptate/cliptate/issues)
   before starting a large feature or architecture change.
3. Preserve existing behavior and add focused regression coverage for changed logic.
4. Run `swift build` and `swift test`. For app, resource, or project changes, also
   run `./scripts/build-and-run.sh build` using full Xcode.
5. Open a pull request describing the user-visible result and your validation.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
`type(scope): summary`. Gitflow describes branching and release workflows;
this convention defines the commit messages used alongside them.

- Use a lowercase type: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`,
  `build`, `ci`, `style`, `chore`, or `revert`.
- Use a short lowercase scope naming the affected area, such as `cli`, `runtime`,
  `models`, or `release`. Omit it for changes that span the repository.
- Write the summary in English, starting with a lowercase imperative verb,
  without a trailing period. Aim for a subject of 72 characters or fewer.
- Add a body when the reason, compatibility impact, or validation needs explanation.
  Separate the body and footers from the subject with blank lines.
- Mark breaking changes with `!` before the colon and explain the impact and
  migration in a `BREAKING CHANGE:` footer.
- Apply the same format to the final squash-merge title. For release preparation,
  use `chore(release): prepare vX.Y.Z`; choose `ci(release)` for release automation.

Examples:

```text
feat(cli): add batch transcription
fix(runtime): avoid blocking login item queries
ci(release): require detailed version release notes
docs(release): document v1.0 changes
chore(release): prepare v1.1.0
```

## Code and resources

Application code belongs in `Sources/Cliptate`, unit tests in `Tests/CliptateTests`,
and UI tests in `Tests/CliptateUITests`. SwiftPM discovers unit tests automatically.
Keep scripts independent of the current working directory and machine-specific paths.

Every new UI string needs a localization entry in `Localizable.xcstrings` for
Simplified Chinese, Japanese, Korean, and German. Use `String(localized:)` where
an API expects a `String`, and localized string keys in SwiftUI views.

Contributions use the repository's MIT license. Preserve third-party copyright and
license notices. Keep credentials, signing material, model weights, personal recordings,
and user data out of commits. Consult [third-party notices](THIRD_PARTY_NOTICES.md)
before introducing a dependency or model.
