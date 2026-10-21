#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build
BIN="$ROOT/.build/debug/OpenMargin"
APP="$ROOT/OpenMargin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/OpenMargin"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier com.nsgarv.openmargin "$APP"
else
  codesign --force --sign - --identifier com.nsgarv.openmargin "$APP"
fi
echo "$APP"
