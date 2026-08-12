#!/bin/bash
# Build Zodl.app for macOS Apple Silicon (local testing, no signing)
set -e

APP_NAME="Zodl"
BUNDLE_ID="com.zodl.poc-autoupdate"
VERSION="${1:-1.0.0}"
BUILD_DIR="build"

echo "==> Cleaning build dir..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

echo "==> Compiling Swift (arm64)..."
swiftc Sources/main.swift Sources/Updater.swift \
    -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library

echo "==> Writing Info.plist (version=$VERSION)..."
sed "s/1\.0\.0/$VERSION/g; s|<string>1</string>|<string>$(echo $VERSION | tr -d .)</string>|g" \
    Resources/Info.plist > "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"

echo "==> Building DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUILD_DIR/$APP_NAME.app" \
    -ov -format UDZO \
    -o "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo ""
echo "✅ Done: $BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo "   Test: open $BUILD_DIR/$APP_NAME.app"
