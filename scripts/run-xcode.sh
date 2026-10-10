#!/usr/bin/env bash
# Xcode entry point; delegates to the shared build logic.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/build-and-run.sh" "$@"
