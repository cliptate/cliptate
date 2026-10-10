#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Cliptate.app"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNING_TEAM="${DEVELOPMENT_TEAM:-}"
SIGNING_FLAGS=(CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$SIGNING_TEAM")
if [[ "${CLIPTATE_APP_STORE:-YES}" == NO ]]; then
  # Explicitly select the free direct-distribution channel, including Accessibility support.
  SIGNING_FLAGS+=(CLIPTATE_CHANNEL_CONDITIONS= CLIPTATE_ENABLE_APP_SANDBOX=NO CLIPTATE_CLI_URL_SCHEME=cliptate-cli CLIPTATE_CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/Sources/Cliptate/Cliptate-Direct.entitlements")
fi
for setting in CLIPTATE_SPARKLE_PUBLIC_KEY CLIPTATE_UPDATE_FEED_URL CLIPTATE_UPDATES_ENABLED CURRENT_PROJECT_VERSION; do
  if [[ -n "${!setting:-}" ]]; then
    SIGNING_FLAGS+=("$setting=${!setting}")
  fi
done
if [[ "$SIGNING_IDENTITY" != - ]]; then
  if [[ -z "$SIGNING_TEAM" ]]; then
    echo "DEVELOPMENT_TEAM is required when CODE_SIGN_IDENTITY is set." >&2
    exit 1
  fi
  SIGNING_FLAGS+=(OTHER_CODE_SIGN_FLAGS=--timestamp)
else
  # Ad-hoc signatures have no Team ID and cannot satisfy runtime library validation.
  SIGNING_FLAGS+=(ENABLE_HARDENED_RUNTIME=NO)
fi
case "$MODE" in
  run|build|--debug|--logs|--verify) ;;
  *) echo "usage: $0 [run|build|--debug|--logs|--verify]" >&2; exit 2 ;;
esac
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Select full Xcode with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer." >&2
  exit 1
fi
# Source builds default to ad-hoc signing; CI supplies an imported Developer ID.
xcodebuild -quiet -project "$ROOT_DIR/Cliptate.xcodeproj" -scheme Cliptate \
  -configuration "$CONFIGURATION" -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -onlyUsePackageVersionsFromResolvedFile \
  "${SIGNING_FLAGS[@]}" build
if [[ "$SIGNING_IDENTITY" != - ]]; then
  "$ROOT_DIR/scripts/sign-sparkle.sh" "$APP_BUNDLE"
fi
case "$MODE" in
  build) echo "$APP_BUNDLE" ;;
  run) open "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/Cliptate" ;;
  --logs)
    open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "Cliptate"'
    ;;
  --verify)
    open "$APP_BUNDLE"
    sleep 2
    pgrep -x Cliptate >/dev/null
    ;;
esac
