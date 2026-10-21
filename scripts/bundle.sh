#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build
BIN="$ROOT/.build/debug/OpenMargin"
APP="$ROOT/OpenMargin.app"
PNG="$ROOT/Assets/AppIcon.png"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenMargin"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$PNG" ]]; then
  ICONSET="$ROOT/.build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  make_icon() {
    sips -z "$1" "$1" "$PNG" --out "$ICONSET/$2" >/dev/null
  }
  make_icon 16 icon_16x16.png
  make_icon 32 icon_16x16@2x.png
  make_icon 32 icon_32x32.png
  make_icon 64 icon_32x32@2x.png
  make_icon 128 icon_128x128.png
  make_icon 256 icon_128x128@2x.png
  make_icon 256 icon_256x256.png
  make_icon 512 icon_256x256@2x.png
  make_icon 512 icon_512x512.png
  make_icon 1024 icon_512x512@2x.png
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier com.nsgarv.openmargin "$APP"
else
  codesign --force --sign - --identifier com.nsgarv.openmargin "$APP"
fi
echo "$APP"
