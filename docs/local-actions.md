# Local Actions and Make tasks

Run `make help` for all task entry points. The Makefile wraps existing scripts and
the existing Test and Package and release workflows; it does not maintain a second
packaging pipeline.

## Setup

Use an Apple Silicon Mac with the [development prerequisites](development.md).
Install [act](https://github.com/nektos/act) and GitHub CLI:

```bash
brew install act gh
gh auth login
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make actions-list
make actions-plan
```

These commands map `macos-26` and the publication job's `ubuntu-24.04` to
`-self-hosted`, which executes directly on this Mac, as described in the
[act runner guide](https://nektosact.com/usage/runners.html). Docker is unnecessary.
The wrapper selects full Xcode for this invocation without changing `xcode-select`.
It explicitly sets run steps to the real checkout because act's host runner uses
a temporary workspace by default. Generic Docker socket/architecture warnings at
startup can still appear before the host jobs; these jobs run on macOS.
It skips Actions checkout/cache/artifact steps locally so the current checkout,
`.build` products and `dist` files remain available across runs and jobs.
`actions-plan` lists packaging stages using act's `--list` and never executes
workflow steps. In host mode, act's `--dryrun` can still execute shell steps, so
the wrapper uses listing for a safe plan.
The first invocation can still download the pinned action definitions, including
skipped cloud steps. Later invocations reuse act's action cache in offline mode.

## Development tasks

```bash
make resolve          # Resolve locked packages
make build            # SwiftPM app executable and CLI
make test             # SwiftPM tests
make automation-test  # Offline release regression checks
make app              # SwiftPM Debug app bundle
make run              # Launch Cliptate Dev
make dmg              # Ad-hoc direct-download Release DMG
make ci               # Full Test workflow through act
```

Direct Swift commands use the toolchain selected in the shell. App tasks use the
existing scripts' signing and launch checks. `make ci` runs against the current
working tree, including edits, reusing local SwiftPM products. Dependency locks,
license notices and the cooperative-worker regression still run.

## Signed packaging

Keep credentials outside the checkout. Create private files at
`~/.config/cliptate/act.secrets` and `~/.config/cliptate/act.vars` using the dotenv
format supported by [act](https://nektosact.com/usage/index.html#secrets).
Use a private editor to enter real values and restrict the files to your account
(`chmod 600`); do not paste credentials into commands, logs or Git.

`act.secrets` needs these existing Actions secrets:

```dotenv
APPLE_CERTIFICATE_P12_BASE64=...
APPLE_CERTIFICATE_PASSWORD=...
APPLE_ID=...
APPLE_APP_SPECIFIC_PASSWORD=...
SPARKLE_PRIVATE_KEY=...
```

`act.vars` needs the existing repository variables:

```dotenv
APPLE_TEAM_ID=FB4W45V73V
SPARKLE_PUBLIC_KEY=...
```

See [signing setup](development.md#apple-signing-and-notarization) and
[Sparkle setup](updates.md). Stable packages require the Sparkle private key;
Nightly only requires the public key. GitHub authentication comes from `GH_TOKEN`,
`GITHUB_TOKEN`, or the authenticated `gh` account, passed to act through the
environment rather than a token argument. That account needs Actions read access
for build numbering and contents write access for publication.

```bash
make package                       # Notarized Nightly package, no GitHub publication
make package TAG=v1.3               # Stable package and signed feed, no publication
make package ACT_SECRETS_FILE=/private/path/act.secrets ACT_VARS_FILE=/private/path/act.vars
```

Packaging uses the current checkout. `TAG` selects the release channel and notes;
for a stable package, check out its tag before packaging. Outputs remain in `dist/`.
The workflow verifies the previous stable installer's permission identity, imports
the Developer ID certificate into act's temporary keychain, signs the app and DMG,
waits for notarization, staples and verifies the ticket, and refreshes the checksum.
The cleanup step restores the previous keychain search list and removes the
temporary signing keychain on success or failure.

Local build numbers use `1000 + latest package workflow run_number` as the first
component and the current Unix timestamp as the second. This makes local runs
newer than the current cloud run's attempt, while the next cloud run has a larger
first component. `BUILD_VERSION=<major>.<minor>` overrides this when needed. Choose
an override that is newer than the installed stable build and compatible with
future cloud numbering. Avoid simultaneous cloud and local publication or rerunning
an older cloud build after local publication; act does not enforce GitHub's
[workflow concurrency](https://nektosact.com/not_supported.html).
Local Actions are serialized within this checkout, including keychain operations.

## Quick publication

Commit the version settings and [release notes](release-notes/README.md) before
creating the version tag. Push the source and tag first, then run:

```bash
make release TAG=v1.3
# Or, from a clean checkout matching the remote main commit:
make release TAG=nightly
```

`release` runs packaging and publication together. It requires a clean checkout,
including untracked files. Version tags must identify HEAD locally and on
`cliptate/cliptate`; Nightly must match the repository's current `main` commit.
These checks run before packaging and again immediately before publication,
rejecting changes made during a build. Version tags are never created or moved by
this command. Existing version-tag pushes also trigger cloud packaging: wait for
that run to finish before locally republishing, or use the cloud result directly.

The publication job uses the files produced in this run, requires successful
notarization, and uses the existing checksum/appcast validation. Stable releases
become Latest; Nightly remains a rolling prerelease. Local release notes identify
the build as local instead of linking to an invented Actions run.
`package`, `ci`, `actions-list`, and `actions-plan` do not publish releases.
