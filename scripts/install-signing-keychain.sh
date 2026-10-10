#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${RUNNER_TEMP:?Run this script only on an ephemeral CI runner}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
for name in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing signing configuration: $name. See docs/development.md#apple-signing-and-notarization." >&2
    exit 1
  fi
done
if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo 'APPLE_TEAM_ID must be a ten-character Apple team identifier.' >&2
  exit 1
fi

KEYCHAIN_PATH="$RUNNER_TEMP/cliptate-signing.keychain-db"
CERTIFICATE_PATH="$RUNNER_TEMP/cliptate-signing.p12"
trap 'rm -f "$CERTIFICATE_PATH"' EXIT
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
echo "::add-mask::$KEYCHAIN_PASSWORD"
python3 - "$RUNNER_TEMP/cliptate-keychains.json" <<'PY'
import json, shlex, subprocess, sys
from pathlib import Path
keys = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
Path(sys.argv[1]).write_text(json.dumps(keys))
PY
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -f pkcs12 -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
python3 - "$RUNNER_TEMP/cliptate-keychains.json" "$KEYCHAIN_PATH" <<'PY'
import json, subprocess, sys
from pathlib import Path
keys = json.loads(Path(sys.argv[1]).read_text())
subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', sys.argv[2], *keys], check=True)
PY
security find-identity -v -p codesigning "$KEYCHAIN_PATH" > "$RUNNER_TEMP/cliptate-identities.txt"
python3 - "$RUNNER_TEMP/cliptate-identities.txt" "$APPLE_TEAM_ID" "$KEYCHAIN_PATH" "$GITHUB_OUTPUT" <<'PY'
import re, sys
from pathlib import Path
identities = re.findall(r'\b([A-F0-9]{40}) "Developer ID Application: .+ \(([A-Z0-9]{10})\)"', Path(sys.argv[1]).read_text())
matches = [fingerprint for fingerprint, team in identities if team == sys.argv[2]]
if len(matches) != 1:
    raise SystemExit('Import exactly one valid Developer ID Application identity for APPLE_TEAM_ID.')
with open(sys.argv[4], 'a') as output:
    output.write(f'signing-identity={matches[0]}\nsigning-keychain={sys.argv[3]}\n')
print(f'Validated Developer ID Application certificate for team {sys.argv[2]}.')
PY
