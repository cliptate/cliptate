#!/usr/bin/env bash
set -euo pipefail
DMG_PATH="${1:?Usage: notarize-dmg.sh /path/to/package.dmg}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}"
: "${SIGNING_KEYCHAIN:?SIGNING_KEYCHAIN is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
test -s "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"
SIGNATURE="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1)"
if [[ "$SIGNATURE" != *'Authority=Developer ID Application:'* ||
      "$SIGNATURE" != *"TeamIdentifier=$APPLE_TEAM_ID"* ||
      "$SIGNATURE" != *'Timestamp='* ]]; then
  echo 'DMG must have a timestamped Developer ID signature from the configured team.' >&2
  exit 1
fi

PROFILE=cliptate-notarization
xcrun notarytool store-credentials "$PROFILE" --keychain "$SIGNING_KEYCHAIN" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
AUTH=(--keychain-profile "$PROFILE" --keychain "$SIGNING_KEYCHAIN")
RESULT="$RUNNER_TEMP/cliptate-notary-result.json"
SUBMITTED=0
if xcrun notarytool submit "$DMG_PATH" "${AUTH[@]}" --wait --timeout 30m \
  --output-format json --no-progress > "$RESULT"; then
  SUBMITTED=1
fi
STATUS="$(python3 - "$RESULT" <<'PY'
import json, sys
from pathlib import Path
try:
    print(json.loads(Path(sys.argv[1]).read_text()).get('status', 'Unknown'))
except (ValueError, OSError):
    print('Unknown')
PY
)"
if [[ "$SUBMITTED" != 1 || "$STATUS" != Accepted ]]; then
  echo "Apple notarization did not succeed (status: $STATUS). No package will be published." >&2
  exit 1
fi
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
hdiutil verify "$DMG_PATH"
# Stapling changes the image: the downloadable checksum must describe the final bytes.
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo 'signing-status=developer-id-notarized' >> "$GITHUB_OUTPUT"
fi
echo 'Developer ID signature, notarization ticket, and Gatekeeper assessment verified.'
