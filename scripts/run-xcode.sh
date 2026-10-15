#!/usr/bin/env bash
# Legacy entry point; delegates to the SwiftPM app bundler.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/build-and-run.sh" "$@"
