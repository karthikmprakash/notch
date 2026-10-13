#!/bin/bash
# Builds Notch.app into build/Notch.app
#   ./build.sh            -> release build
#   ./build.sh debug      -> debug build
#   ./build.sh release run-> build, then quit any running copy and open the app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
RUN="no"
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    run) RUN="yes" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# NOTCH_UNIVERSAL=1 builds arm64 + x86_64 (used by the release workflow).
# NOTCH_SIGN_IDENTITY overrides the signing identity (CI sets "Developer ID Application: ...").
if [ "${NOTCH_UNIVERSAL:-0}" = "1" ]; then
  echo "==> swift build -c $CONFIG (arm64 + x86_64)"
  swift build -c "$CONFIG" --arch arm64 --arch x86_64
  case "$CONFIG" in
    release) BIN=".build/apple/Products/Release/Notch" ;;
    *)       BIN=".build/apple/Products/Debug/Notch" ;;
  esac
else
  echo "==> swift build -c $CONFIG"
  swift build -c "$CONFIG"
  BIN=".build/$CONFIG/Notch"
fi

[ -f "$BIN" ] || { echo "build product missing: $BIN" >&2; exit 1; }
APP="build/Notch.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign with a stable identity when one exists: TCC permissions (Automation,
# Calendar, ...) are remembered per signature, so an ad-hoc signature means
# macOS asks again after every rebuild.
IDENTITY="${NOTCH_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
if [ -n "$IDENTITY" ]; then
  echo "==> codesign with $IDENTITY"
  codesign --force --options runtime --sign "$IDENTITY" --identifier dev.kmp.notch "$APP"
else
  echo "==> codesign ad-hoc (no signing identity found)"
  codesign --force --sign - --identifier dev.kmp.notch "$APP"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo
echo "built: $APP"
if [ "$RUN" = "yes" ]; then
  pkill -x Notch 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "launched. Look at the menu bar (a small notch icon) and at the notch."
else
  echo "run:   open $APP      (quit with the menu bar icon, or: pkill -x Notch)"
fi
