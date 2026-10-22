#!/bin/bash
set -e

# Build configuration
# - CONFIG=debug|release  (default: debug)
CONFIG="${CONFIG:-debug}"
for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="release" ;;
        --debug)   CONFIG="debug" ;;
    esac
done

# SwiftPM from Command Line Tools lacks the SwiftUI macro plugin; use Xcode's toolchain.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_NAME="Clip.app"
APP_DIR="build/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building Clip ($CONFIG)..."
swift build -c "$CONFIG"
BUILD_BIN=".build/$CONFIG/Clip"
if [ ! -f "$BUILD_BIN" ]; then
    echo "error: app binary not found at $BUILD_BIN" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BUILD_BIN" "$MACOS/Clip"
cp "Clip/App/Info.plist" "$CONTENTS/Info.plist"
bash scripts/inject-build-metadata.sh "$CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "design/menuBarIcon.svg" "$RESOURCES/MenuBarIcon.svg"
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$RESOURCES/"
done

# PermissionFlow uses Bundle.module for its panel strings.
BUILD_DIR="$(dirname "$BUILD_BIN")"
PERMISSION_FLOW_BUNDLE="$BUILD_DIR/Clip_PermissionFlow.bundle"
if [ ! -d "$PERMISSION_FLOW_BUNDLE" ]; then
    echo "error: missing SwiftPM resource bundle: $PERMISSION_FLOW_BUNDLE" >&2
    exit 1
fi
cp -R "$PERMISSION_FLOW_BUNDLE" "$RESOURCES/"

# Code signing: use the personal Apple Development certificate so TCC grants
# (Screen Recording / Accessibility) survive rebuilds. Falls back to ad-hoc.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development: chengffei@outlook.com (3477T28C36)}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --entitlements "$SCRIPT_DIR/Clip.entitlements" \
        --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "warning: '$SIGN_IDENTITY' not found — ad-hoc signing (TCC grants reset on each rebuild)." >&2
    codesign --force --entitlements "$SCRIPT_DIR/Clip.entitlements" --sign - "$APP_DIR"
fi

echo "Built and signed $APP_DIR"
