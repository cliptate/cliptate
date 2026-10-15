#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
CONFIGURATION="${CONFIGURATION:-Debug}"
# DERIVED_DATA_PATH remains accepted for existing local build invocations.
APP_BUILD_DIR="${APP_BUILD_DIR:-${DERIVED_DATA_PATH:-$ROOT_DIR/.build/app}/Build/Products}"
APP_NAME=Cliptate
if [[ "$CONFIGURATION" == Debug ]]; then
  APP_NAME="Cliptate Dev"
fi
APP_BUNDLE="$APP_BUILD_DIR/$CONFIGURATION/$APP_NAME.app"
export CONFIGURATION
case "$MODE" in
  run|build|--debug|--logs|--verify) ;;
  *) echo "usage: $0 [run|build|--debug|--logs|--verify]" >&2; exit 2 ;;
esac
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Select full Xcode with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer." >&2
  exit 1
fi
python3 "$ROOT_DIR/scripts/build-app.py" --output "$APP_BUNDLE"
if [[ "$MODE" != build ]]; then
  python3 "$ROOT_DIR/scripts/verify-development-permission-identity.py" "$APP_BUNDLE"
fi
case "$MODE" in
  build) echo "$APP_BUNDLE" ;;
  run) open "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs)
    open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify)
    open "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
esac
