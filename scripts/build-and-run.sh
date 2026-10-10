#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Cliptate.app"
case "$MODE" in
  run|build|--debug|--logs|--verify) ;;
  *) echo "usage: $0 [run|build|--debug|--logs|--verify]" >&2; exit 2 ;;
esac
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Select full Xcode with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer." >&2
  exit 1
fi
# Ad-hoc signing supports sandboxed local builds without a developer team.
xcodebuild -quiet -project "$ROOT_DIR/Cliptate.xcodeproj" -scheme Cliptate \
  -configuration "$CONFIGURATION" -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
case "$MODE" in
  build) echo "$APP_BUNDLE" ;;
  run) open "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/Cliptate" ;;
  --logs)
    open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "Cliptate"'
    ;;
  --verify)
    open "$APP_BUNDLE"
    sleep 2
    pgrep -x Cliptate >/dev/null
    ;;
esac
