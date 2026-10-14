# In-app updates

Cliptate uses [Sparkle 2](https://sparkle-project.org/documentation/) to check,
download, verify, install, and relaunch. The integration
was informed by [VoiceInk's updater](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/App/Updates/UpdaterViewModel.swift).
Cliptate uses Sparkle's standard scheduler and user consent prompt. Preferences
are persisted by Sparkle rather than added to transcription configuration presets.

When an automatic check finds an update, a blue version button appears next to
Settings in the sidebar. Clicking it opens a popover with the version, download
size, publication date, and **Skip**, **Later**, and **Install and Relaunch** actions.
Missing size or date metadata is omitted. Release notes open the appcast's release
notes or information link in the browser. Clicking outside the popover leaves the
reminder available; Skip and Later complete the current Sparkle offer with their
corresponding choices. Manual checks show the same details in a window. When the
main window is hidden, an automatic offer appears in a window without activating
the application, so menu-bar-only users can still act on it.

The ready-to-install window shows Cliptate's icon and a green **Signature verified**
badge. It appears only when Sparkle reports that installer preparation has finished,
after validation, rather than when an update is first found or downloaded. Checking,
downloading, and errors continue to use Sparkle's standard UI. The custom update
offer and installation prompt use Sparkle's public user-driver API. Choosing
**Install on Quit** or closing this prompt leaves the prepared update scheduled for installation on quit,
as Sparkle specifies; **Install and Relaunch** proceeds immediately.

The app menu and the status item both offer **Check for Updates…**. The settings
page offers automatic update checking. Missing distribution configuration disables
the updater, and tests never start it. Sparkle normally asks about automatic checks
on the second launch, checks every 24 hours after consent, and asks before installing;
the integration does not enable automatic installation.

## Feeds and versions

All production direct-download builds, including Nightly and local Release builds,
use the latest stable feed: `https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml`.
Nightly still builds `main` as a rolling prerelease, but checks for stable updates.
It does not publish a separate update feed. Version tags identify stable source;
the publication job explicitly marks the verified version release as Latest.

The feed follows [VoiceInk's appcast structure](https://github.com/Beingpax/VoiceInk/blob/main/appcast.xml).
Each stable release has one item containing the build number, display version,
publication date, minimum macOS version, embedded release notes, installer URL,
byte length, and Ed25519 signature. Packaging generates it from the final
notarized and stapled DMG with Sparkle's `generate_appcast`, then validates it.
The publication workflow creates channel metadata in a temporary directory and
generates a fresh `appcast.xml` for each stable release. The feed is a generated
Release asset, not a tracked source file; apps fetch the Latest release asset.
GitHub Pages and commits to `main` are unnecessary for serving updates.

Embedded notes come from the complete repository
[version document](release-notes/README.md). The generator includes its content as
plain text plus release and source links; missing or incomplete version notes stop
generation before the signing tool is downloaded. GitHub Release links to the
website's version page instead of duplicating this document. This presentation
change preserves the complete in-app notes and their validation.

The initial stable release is `v1.0`, with display version `1.0`. Its internal build
number continues above existing installations even though the display version
starts at 1.0. Before the first signed stable feed is published, the Latest feed
URL will return 404. Publishing a tag runs **Package and release**, which uploads
the verified installer and appcast before publishing the release as Latest.

Manual checks detect an unpublished feed (HTTP 404) and explain that update
information is not published yet, with a link to GitHub Releases. They do not
report that the app is up to date or switch between stable and Nightly channels.
Other network failures and all update validation remain handled by Sparkle.

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
URL, uploads the DMG and checksum, then uploads `appcast.xml`. Only stable version
releases publish update feeds. Nightly publication keeps its prerelease status
and `latest=false`, and only replaces its installer and checksum. The source
branch is never written by the release workflow. Feed validation is structural;
cryptographic archive verification is performed by Sparkle when installing.

## Local builds and App Store distribution

Debug builds use the independent `com.cliptate.dev` identity and disable the
production updater, even when a feed and key are configured. Use Release and
compatible Developer ID signing for end-to-end production upgrade testing.

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
Use a dedicated macOS test account. Grant microphone, Accessibility (direct
builds), and screen-recording access to the old build before updating. Verify
download, installation, relaunch, the automatic-check preference, retained
configuration/history, and all three permissions after relaunch. Repeat a rebuild
of the separately signed Dev app and verify that production consent is unaffected. Do not use a running application inside a read-only DMG for this test.
An existing build without Sparkle must be upgraded manually once.

Offline regression checks:

```bash
swift test --filter AppUpdateConfigurationTests
python3 -m unittest discover -s Tests/Automation -v
```
