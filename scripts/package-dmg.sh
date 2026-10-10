#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode}"
if [[ "${1:-}" == --help ]]; then
  echo "usage: $0 [Cliptate.app path] [output directory]"
  exit 0
fi
if [[ $# -gt 2 ]]; then
  echo "usage: $0 [Cliptate.app path] [output directory]" >&2
  exit 2
fi
APP_BUNDLE="${1:-$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Cliptate.app}"
OUTPUT_DIR="${2:-$ROOT_DIR/dist}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing built application: $APP_BUNDLE. Run CONFIGURATION=Release ./scripts/build-and-run.sh build first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE")"
ARCHITECTURES="${ARCHITECTURES// /-}"
if [[ ! "$VERSION" =~ ^[[:alnum:]._-]+$ || ! "$BUILD_NUMBER" =~ ^[[:alnum:]._-]+$ || ! "$ARCHITECTURES" =~ ^[[:alnum:]_-]+$ ]]; then
  echo "Invalid application version, build number, or architecture." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
if [[ -n "${CODE_SIGN_IDENTITY:-}" && "$CODE_SIGN_IDENTITY" != - ]]; then
  SIGNATURE="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
  if [[ "$SIGNATURE" != *'Authority=Developer ID Application:'* ||
        "$SIGNATURE" != *"TeamIdentifier=${DEVELOPMENT_TEAM:?}"* ||
        "$SIGNATURE" != *'(runtime)'* || "$SIGNATURE" != *'Timestamp='* ]]; then
    echo 'App must have a timestamped Developer ID signature with Hardened Runtime from the configured team.' >&2
    exit 1
  fi
  /usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null |
    python3 "$ROOT_DIR/scripts/verify-distribution-entitlements.py"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
DMG_NAME="Cliptate-$VERSION-$BUILD_NUMBER-macOS-$ARCHITECTURES.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "$OUTPUT_DIR/.dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

# ditto preserves the executable permissions, framework symlinks, and app signature.
/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/Cliptate.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/Licenses/docs"
/usr/bin/ditto "$ROOT_DIR/LICENSE" "$STAGING_DIR/Licenses/LICENSE"
/usr/bin/ditto "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGING_DIR/Licenses/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "$ROOT_DIR/docs/legal" "$STAGING_DIR/Licenses/docs/legal"

/usr/bin/hdiutil create -volname "Cliptate $VERSION" -srcfolder "$STAGING_DIR" \
  -fs HFS+ -format UDZO -ov "$DMG_PATH"
if [[ -n "${CODE_SIGN_IDENTITY:-}" && "$CODE_SIGN_IDENTITY" != - ]]; then
  /usr/bin/codesign --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
  /usr/bin/codesign --verify --strict "$DMG_PATH"
fi
/usr/bin/hdiutil verify "$DMG_PATH"
(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'dmg-path=%s\n' "$DMG_PATH"
    printf 'dmg-name=%s\n' "$DMG_NAME"
    printf 'checksum-path=%s\n' "$DMG_PATH.sha256"
  } >> "$GITHUB_OUTPUT"
fi
echo "$DMG_PATH"
