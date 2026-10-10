#!/usr/bin/env bash
# Compatibility entry point for building and launching the app.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT_DIR/scripts/build-and-run.sh" "$@"
