#!/usr/bin/env bash
set -euo pipefail
APP_BUNDLE="${1:?Usage: sign-sparkle.sh Cliptate.app}"
IDENTITY="${CODE_SIGN_IDENTITY:?Developer ID identity is required}"
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
test -d "$FRAMEWORK"
# Xcode build (unlike archive/export) does not re-sign Sparkle's nested helpers.
# Sign inside out and preserve the downloader's sandbox entitlements.
for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$helper"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --preserve-metadata=entitlements,identifier,requirements "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
