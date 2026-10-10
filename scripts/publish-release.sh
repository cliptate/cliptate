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

POLICY_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/release-policy.py"
# Parse data from one validated plan; never evaluate generated shell code.
POLICY_JSON="$(python3 "$POLICY_SCRIPT" publication)"
policy_field() {
  printf '%s\n' "$POLICY_JSON" | python3 "$POLICY_SCRIPT" field "$1"
}
MOVE_TAG="$(policy_field move_tag)"
TITLE="$(policy_field title)"
SIGNING_DESCRIPTION="$(policy_field signing_description)"
POLICY_FLAGS="$(policy_field flags)"
FLAGS=()
while IFS= read -r flag; do
  FLAGS+=("$flag")
done <<< "$POLICY_FLAGS"

ASSET_PATHS=("$DMG_PATH" "$CHECKSUM_PATH")
if [[ -n "${APPCAST_PATH:-}" ]]; then
  test "$(basename "$APPCAST_PATH")" = appcast.xml
  python3 "$(dirname "${BASH_SOURCE[0]}")/validate-appcast.py" \
    "$APPCAST_PATH" "$DMG_PATH" "$GH_REPO" "$TAG"
fi

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<EOF
Apple Silicon, macOS 15+. $SIGNING_DESCRIPTION

Download the DMG and drag Cliptate into Applications. Verify the download with the accompanying SHA-256 file.

Source: [$COMMIT](https://github.com/$GH_REPO/commit/$COMMIT)
Build: [GitHub Actions](https://github.com/$GH_REPO/actions/runs/${GITHUB_RUN_ID:?})
EOF

if [[ "$MOVE_TAG" == true ]]; then
  # Create the reserved tag if needed. Existing tags move only after upload succeeds.
  if ! gh api "repos/$GH_REPO/git/ref/tags/nightly" --silent; then
    gh api --method POST "repos/$GH_REPO/git/refs" \
      -f ref=refs/tags/nightly -f sha="$COMMIT" --silent
  fi
else
  # Never create or move a version tag: it must already identify the built commit.
  ENCODED_TAG="$(policy_field encoded_tag)"
  test "$(gh api "repos/$GH_REPO/commits/$ENCODED_TAG" --jq .sha)" = "$COMMIT"
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

if [[ "$MOVE_TAG" == true ]]; then
  gh api --method PATCH "repos/$GH_REPO/git/refs/tags/nightly" \
    -f sha="$COMMIT" -F force=true --silent
  gh release edit "$TAG" --draft=false "${FLAGS[@]}" \
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
  gh release edit "$TAG" --draft=false "${FLAGS[@]}"
fi

URL="$(gh release view "$TAG" --json url --jq .url)"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### macOS download\n\n[%s](%s) contains `%s` and its SHA-256 checksum.\n' \
    "$TITLE" "$URL" "$DMG_NAME" >> "$GITHUB_STEP_SUMMARY"
fi
echo "$URL"
