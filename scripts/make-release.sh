#!/bin/bash
# Release build: universal Clip.app, then Clip-<version>.dmg and Clip-<version>.zip
# in dist/. The DMG carries an Applications shortcut for drag-install.
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

hdiutil create -volname "$VOLNAME" -srcfolder "$WORK/stage" -format UDZO -imagekey zlib-level=9 -quiet "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
rm -rf "$WORK"

shasum -a 256 "$DMG" "$ZIP" | tee "dist/Clip-$VERSION.sha256"
