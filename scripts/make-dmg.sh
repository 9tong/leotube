#!/bin/bash
# Builds a release LeoTube.app and packages it as build/LeoTube-<version>.dmg
# with a styled drag-to-Applications window.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/build-app.sh release

APP="build/LeoTube.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
VOLNAME="LeoTube"
DMG="build/LeoTube-$VERSION.dmg"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"
trap 'hdiutil detach "/Volumes/$VOLNAME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Stage contents
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift scripts/make-dmg-background.swift "$WORK/bg.png" 1
swift scripts/make-dmg-background.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

# Writable image to lay out the Finder window
hdiutil detach "/Volumes/$VOLNAME" -quiet 2>/dev/null || true
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -size 200m "$RW"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$RW"

# (time-limited so headless CI can't hang on Finder automation)
if ! perl -e 'alarm shift; exec @ARGV' 90 osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 562}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "LeoTube.app" of container window to {180, 200}
    set position of item "Applications" of container window to {480, 200}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "warning: Finder layout step failed (Automation permission?) — DMG will use default layout" >&2
fi

# Volume icon goes in after the Finder pass (Finder drops it otherwise).
cp Resources/AppIcon.icns "/Volumes/$VOLNAME/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOLNAME"
rm -rf "/Volumes/$VOLNAME/.fseventsd"
sync
hdiutil detach "/Volumes/$VOLNAME" -quiet
rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
