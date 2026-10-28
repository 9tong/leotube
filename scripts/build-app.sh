#!/bin/bash
# Builds LeoTube.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/LeoTube.app"
cd "$ROOT"

swift build -c "$CONFIG" --product LeoTube
BIN="$(swift build -c "$CONFIG" --show-bin-path)/LeoTube"

# App icon: Resources/AppIcon.png (1024², transparent) → AppIcon.icns.
# Regenerate it from the artwork with: swift scripts/prepare-icon.swift Resources/AppIcon-source.png Resources/AppIcon.png
if [ ! -f Resources/AppIcon.icns ] || [ Resources/AppIcon.png -nt Resources/AppIcon.icns ]; then
  TMP="$(mktemp -d)"
  if [ -f Resources/AppIcon.png ]; then
    cp Resources/AppIcon.png "$TMP/icon.png"
  else
    swift scripts/make-icon.swift "$TMP/icon.png" >/dev/null
  fi
  mkdir -p "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LeoTube"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"  # Finder/File Provider metadata makes codesign refuse the bundle
codesign --force --deep --sign - --entitlements Resources/LeoTube.entitlements "$APP" >/dev/null
echo "Built $APP"
