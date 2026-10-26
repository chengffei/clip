#!/bin/bash
set -e

# Build configuration
# - CONFIG=debug|release  (default: debug)
# - UNIVERSAL=1           fat arm64 + x86_64 binary (default: host arch only)
CONFIG="${CONFIG:-debug}"
UNIVERSAL="${UNIVERSAL:-0}"
for arg in "$@"; do
    case "$arg" in
        --release)   CONFIG="release" ;;
        --debug)     CONFIG="debug" ;;
        --universal) UNIVERSAL=1 ;;
    esac
done

# SwiftPM from Command Line Tools lacks the SwiftUI macro plugin; use Xcode's toolchain.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_NAME="Clip.app"
APP_DIR="build/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [ "$UNIVERSAL" = "1" ]; then
    echo "Building Clip ($CONFIG, universal)..."
    swift build -c "$CONFIG" --arch arm64 --arch x86_64
    CONFIG_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
    # Xcode 26+ SwiftPM puts multi-arch products here; older toolchains used .build/apple/.
    BUILD_DIR=".build/out/Products/$CONFIG_CAP"
    [ -f "$BUILD_DIR/Clip" ] || BUILD_DIR=".build/apple/Products/$CONFIG_CAP"
else
    echo "Building Clip ($CONFIG)..."
    swift build -c "$CONFIG"
    BUILD_DIR=".build/$CONFIG"
fi
BUILD_BIN="$BUILD_DIR/Clip"
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
# Bundled OCR model (PP-OCRv6 small, Core ML) and its character list.
cp -R "Resources/OCRModels" "$RESOURCES/"
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$RESOURCES/"
done

# PermissionFlow uses Bundle.module for its panel strings.
PERMISSION_FLOW_BUNDLE="$BUILD_DIR/Clip_PermissionFlow.bundle"
if [ ! -d "$PERMISSION_FLOW_BUNDLE" ]; then
    echo "error: missing SwiftPM resource bundle: $PERMISSION_FLOW_BUNDLE" >&2
    exit 1
fi
cp -R "$PERMISSION_FLOW_BUNDLE" "$RESOURCES/"

# Code signing: the personal Apple Development certificate keeps TCC grants
# (Screen Recording / Accessibility) stable across rebuilds. Falls back to ad-hoc.
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

echo "Built and signed $APP_DIR ($(lipo -archs "$MACOS/Clip"))"
