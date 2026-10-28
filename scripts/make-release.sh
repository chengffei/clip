#!/bin/bash
# Release build: universal Clip.app, then Clip-<version>.dmg and Clip-<version>.zip
# in dist/. The DMG window shows Clip, an Applications shortcut, an arrow between
# them and a note on Open Anyway (scripts/dmg-background.swift). Laying out the
# window drives Finder, so the first run asks to allow controlling Finder.
set -e
cd "$(dirname "$0")/.."

CONFIG=release UNIVERSAL=1 bash scripts/bundle.sh

APP="build/Clip.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VOLNAME="Clip $VERSION"
mkdir -p dist
DMG="dist/Clip-$VERSION.dmg"
ZIP="dist/Clip-$VERSION.zip"
WORK="build/dmg"

[ -d "/Volumes/$VOLNAME" ] && hdiutil detach -quiet "/Volumes/$VOLNAME" || true
rm -rf "$WORK" "$DMG" "$ZIP"
mkdir -p "$WORK/stage"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"

mkdir -p "$WORK/stage/.background" "$WORK/bg"
swift scripts/dmg-background.swift "$WORK/bg"
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" \
    -out "$WORK/stage/.background/background.tiff" 2>/dev/null

RW="$WORK/rw.dmg"
hdiutil create -volname "$VOLNAME" -srcfolder "$WORK/stage" -format UDRW -fs HFS+ -quiet "$RW"
hdiutil attach -readwrite -noverify -noautoopen -quiet "$RW"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Clip.app" of container window to {170, 180}
        set position of item "Applications" of container window to {470, 180}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "/Volumes/$VOLNAME"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -quiet -o "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
rm -rf "$WORK"

shasum -a 256 "$DMG" "$ZIP" | tee "dist/Clip-$VERSION.sha256"
