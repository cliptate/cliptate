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
