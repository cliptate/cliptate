# In-app updates

Cliptate uses [Sparkle 2](https://sparkle-project.org/documentation/) and its native
update window to check, download, verify, install, and relaunch. The integration
was informed by [VoiceInk's updater](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/App/Updates/UpdaterViewModel.swift).
Cliptate uses Sparkle's standard scheduler and user consent prompt. Preferences
are persisted by Sparkle rather than added to transcription configuration presets.

The app menu and the status item both offer **Check for Updates…**. The settings
page offers automatic update checking. Missing distribution configuration disables
the updater, and tests never start it. Sparkle normally asks about automatic checks
on the second launch, checks every 24 hours after consent, and asks before installing;
the integration does not enable automatic installation.

## Feeds and versions

- Stable builds: `https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml`
- Nightly builds: `https://github.com/cliptate/cliptate/releases/download/nightly/appcast.xml`

Each feed is a release asset generated from the final notarized and stapled DMG
using Sparkle's `generate_appcast` tool. The feed contains that release's build
number, display version, minimum macOS version, download URL, byte length, and
Ed25519 signature. A new Nightly replaces the previous feed and installer. Stable
and Nightly builds stay on their respective feeds; users change channel by
installing the other distribution. Before the first release with an appcast, its
feed URL will return 404.

CI assigns `CFBundleVersion` as `1000 + GITHUB_RUN_NUMBER`, followed by the run
attempt (for example `1042.1`). This increases even when the marketing version is
unchanged and lets daily builds discover updates. Version-tag and Nightly builds
use the same numbering rule. Source builds keep the checked-in build number.
Do not reset the package workflow's run counter or reuse a released build number.

## One-time signing setup

Download the [Sparkle 2.10.0 distribution](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
and extract it outside this checkout. The release archive SHA-256 is
`c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.
Use its `bin/generate_keys` tool:

```bash
/path/to/Sparkle/bin/generate_keys --account cliptate
/path/to/Sparkle/bin/generate_keys --account cliptate -p
```

The private key stays in the login Keychain. Add the printed base64 public key as
repository Actions **variable** `SPARKLE_PUBLIC_KEY`. Export the corresponding
private key to a private directory outside Git:

```bash
/path/to/Sparkle/bin/generate_keys --account cliptate -x /private/path/cliptate-sparkle-key
```

Add the file's contents (the exported base64 text, without additional base64 encoding)
as repository Actions **secret** `SPARKLE_PRIVATE_KEY`, using GitHub's secret UI or
`gh secret set SPARKLE_PRIVATE_KEY < /private/path/cliptate-sparkle-key`.
Keep a secure backup of this key. Never commit it or put it in command arguments,
chat, or build logs. These are separate from Apple's Developer ID signing keys.

The existing Package and release workflow injects the public key and appropriate
feed into the built app. It re-signs Sparkle's nested installation helpers with
the configured Developer ID identity, notarizes and staples the DMG, then signs
that final archive and generates the appcast. Generation validates the archive's
embedded public key against the signing key. Missing credentials or a mismatched
key prevents publication. The private key reaches the tool only through stdin.

The publication job validates the feed's signature shape, file length, and release
URL, uploads the DMG and checksum, then uploads `appcast.xml`. It publishes the
release and only then removes obsolete Nightly installers. No branch write or
GitHub Pages setup is required. Feed validation is structural; cryptographic
archive verification is performed by Sparkle when installing the update.

## Local builds and App Store distribution

Copy `config/Local.xcconfig.example` to the ignored `config/Local.xcconfig` and set
`CLIPTATE_SPARKLE_PUBLIC_KEY` to the public key for your feed. Optionally set
`CLIPTATE_UPDATE_FEED_URL` to your own HTTPS appcast. In xcconfig files, write the
URL as `https:/$()/example.com/appcast.xml` so `//` does not start a comment.
The build script also accepts those settings as environment variables, plus
`CURRENT_PROJECT_VERSION` for testing a newer build.

`APP_STORE` remains the existing accessibility capability gate. It is independent
of distribution. Set `CLIPTATE_UPDATES_ENABLED=NO` for an actual Mac App Store
build; a detected App Store receipt also disables the updater. For an App Store
submission, omit the Sparkle package/framework and its temporary Mach lookup
entitlements from that distribution target, as required by Sparkle's
[sandbox integration instructions](https://sparkle-project.org/documentation/sandboxing/).
The current Xcode target packages direct-download releases.

To test a full update, install an older signed and notarized build in Applications,
publish a newer signed build to the same feed, then choose **Check for Updates…**.
Verify download, installation, relaunch, and the automatic-check preference after
relaunch. Do not use a running application inside a read-only DMG for this test.
An existing build without Sparkle must be upgraded manually once.

Offline regression checks:

```bash
swift test --filter AppUpdateConfigurationTests
python3 -m unittest discover -s Tests/Automation -v
```
