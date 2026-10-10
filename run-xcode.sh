#!/usr/bin/env bash
# Compatibility entry point; maintained build logic lives in scripts/.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT_DIR/scripts/build-and-run.sh" "$@"
