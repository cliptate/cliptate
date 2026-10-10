#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
python3 - "$RUNNER_TEMP/cliptate-keychains.json" <<'PY'
import json, subprocess, sys
from pathlib import Path
state = Path(sys.argv[1])
if state.exists():
    subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *json.loads(state.read_text())], check=True)
    state.unlink()
PY
if [[ -f "$RUNNER_TEMP/cliptate-signing.keychain-db" ]]; then
  security delete-keychain "$RUNNER_TEMP/cliptate-signing.keychain-db"
fi
rm -f "$RUNNER_TEMP/cliptate-signing.p12" "$RUNNER_TEMP/cliptate-identities.txt" \
  "$RUNNER_TEMP/cliptate-notary-result.json"
