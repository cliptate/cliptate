#!/usr/bin/env bash
set -euo pipefail
APP_BUNDLE="${1:?Usage: sign-sparkle.sh Cliptate.app}"
IDENTITY="${CODE_SIGN_IDENTITY:?Apple code-signing identity is required}"
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
test -d "$FRAMEWORK"
SIGNING_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then
  SIGNING_FLAGS+=(--options runtime --timestamp)
fi
# Re-sign the binary package's nested helpers before signing the containing app.
# Sign inside out and preserve the downloader's sandbox entitlements.
for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign "${SIGNING_FLAGS[@]}" \
    --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$helper"
done
codesign "${SIGNING_FLAGS[@]}" "$FRAMEWORK"
codesign --verify --deep --strict "$FRAMEWORK"
