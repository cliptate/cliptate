#!/usr/bin/env bash
set -euo pipefail

# CI provides a contents:write token only to the release job, after packaging.
DMG_PATH="${1:?Usage: publish-release.sh /path/to/package.dmg}"
DMG_NAME="$(basename "$DMG_PATH")"
CHECKSUM_PATH="$DMG_PATH.sha256"
TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
COMMIT="${BUILT_COMMIT:?BUILT_COMMIT is required}"
export GH_REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

[[ "$DMG_NAME" == Cliptate.dmg ]]
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]
test -s "$DMG_PATH"
test -s "$CHECKSUM_PATH"
(cd "$(dirname "$DMG_PATH")" && shasum -a 256 -c "$DMG_NAME.sha256")

ASSET_PATHS=("$DMG_PATH" "$CHECKSUM_PATH")
if [[ -n "${APPCAST_PATH:-}" ]]; then
  if [[ "$TAG" == nightly ]]; then
    echo 'Nightly builds use the latest stable feed and cannot publish their own appcast.' >&2
    exit 1
  fi
  if [[ "${SIGNING_STATUS:-}" != developer-id-notarized ]]; then
    echo 'Only notarized Developer ID releases can publish update feeds.' >&2
    exit 1
  fi
  test "$(basename "$APPCAST_PATH")" = appcast.xml
  python3 "$(dirname "${BASH_SOURCE[0]}")/validate-appcast.py" \
    "$APPCAST_PATH" "$DMG_PATH" "$GH_REPO" "$TAG"
fi

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
case "${SIGNING_STATUS:-ad-hoc}" in
  developer-id-notarized) SIGNING_DESCRIPTION='Developer ID signed and Apple-notarized.' ;;
  ad-hoc) SIGNING_DESCRIPTION='Release build with ad-hoc signing; not Apple-notarized.' ;;
  *) echo 'Unrecognized signing status.' >&2; exit 1 ;;
esac
cat > "$NOTES" <<EOF
Apple Silicon, macOS 15+. $SIGNING_DESCRIPTION

Download the DMG and drag Cliptate into Applications. Verify the download with the accompanying SHA-256 file.

Source: [$COMMIT](https://github.com/$GH_REPO/commit/$COMMIT)
Build: [GitHub Actions](https://github.com/$GH_REPO/actions/runs/${GITHUB_RUN_ID:?})
EOF

if [[ "$TAG" == nightly ]]; then
  TITLE="Nightly ($(date -u +%Y-%m-%d))"
  # Create the reserved tag if needed. Existing tags move only after upload succeeds.
  if ! gh api "repos/$GH_REPO/git/ref/tags/nightly" --silent; then
    gh api --method POST "repos/$GH_REPO/git/refs" \
      -f ref=refs/tags/nightly -f sha="$COMMIT" --silent
  fi
  FLAGS=(--prerelease --latest=false)
else
  TITLE="Cliptate $TAG"
  # Never create or move a version tag: it must already identify the built commit.
  ENCODED_TAG="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")"
  test "$(gh api "repos/$GH_REPO/commits/$ENCODED_TAG" --jq .sha)" = "$COMMIT"
  FLAGS=(--prerelease=false --latest=true)
fi

if ! gh release view "$TAG" --json id >/dev/null 2>&1; then
  gh release create "$TAG" --verify-tag --draft --title "$TITLE" \
    --notes-file "$NOTES" "${FLAGS[@]}"
fi

gh release upload "$TAG" "${ASSET_PATHS[@]}" --clobber
# Publish the feed only after its referenced installer has uploaded successfully.
if [[ -n "${APPCAST_PATH:-}" ]]; then
  gh release upload "$TAG" "$APPCAST_PATH" --clobber
fi

if [[ "$TAG" == nightly ]]; then
  gh api --method PATCH "repos/$GH_REPO/git/refs/tags/nightly" \
    -f sha="$COMMIT" -F force=true --silent
  gh release edit "$TAG" --draft=false --prerelease --latest=false \
    --title "$TITLE" --notes-file "$NOTES" --target "$COMMIT"
  # Keep only the current installer pair when the app version/build changes.
  ASSETS="$(gh release view "$TAG" --json assets --jq '.assets[].name')"
  while IFS= read -r asset; do
    case "$asset" in
      "$DMG_NAME"|"$DMG_NAME.sha256") continue ;;
      Cliptate-*.dmg|Cliptate-*.dmg.sha256)
        gh release delete-asset "$TAG" "$asset" --yes ;;
    esac
  done <<< "$ASSETS"
else
  gh release edit "$TAG" --draft=false --prerelease=false --latest=true
fi

URL="$(gh release view "$TAG" --json url --jq .url)"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### macOS download\n\n[%s](%s) contains `%s` and its SHA-256 checksum.\n' \
    "$TITLE" "$URL" "$DMG_NAME" >> "$GITHUB_STEP_SUMMARY"
fi
echo "$URL"
