#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:?Usage: generate-appcast.sh notarized.dmg}"
TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
# Do not sign until notarization and stapling have finalized the archive bytes.
[[ "${SIGNING_STATUS:-}" == developer-id-notarized ]]
: "${SPARKLE_PRIVATE_KEY:?Configure the Sparkle Ed25519 signing secret}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tools" "$WORK/updates"
# Same pinned release as Package.swift; verify the complete tool distribution.
curl --fail --location --retry 3 \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
  --output "$WORK/Sparkle.tar.xz"
printf '%s  %s\n' c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c \
  "$WORK/Sparkle.tar.xz" | shasum -a 256 -c -
tar -xf "$WORK/Sparkle.tar.xz" -C "$WORK/tools"
cp "$DMG_PATH" "$WORK/updates/"
PREFIX="$(python3 -c 'import sys, urllib.parse; print("https://github.com/" + sys.argv[1] + "/releases/download/" + urllib.parse.quote(sys.argv[2], safe="") + "/")' "$REPOSITORY" "$TAG")"
# Pass the secret through stdin, never through command arguments or a disk file.
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$WORK/tools/bin/generate_appcast" \
  --ed-key-file - --download-url-prefix "$PREFIX" \
  --maximum-deltas 0 --maximum-versions 1 \
  --link "https://github.com/$REPOSITORY/releases" \
  -o "$WORK/appcast.xml" "$WORK/updates"
python3 "$ROOT_DIR/scripts/validate-appcast.py" "$WORK/appcast.xml" "$DMG_PATH" "$REPOSITORY" "$TAG"
cp "$WORK/appcast.xml" "$(dirname "$DMG_PATH")/appcast.xml"
