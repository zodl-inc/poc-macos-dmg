#!/bin/bash
# Build HelloWorld.app for macOS Apple Silicon
# Run this ON a Mac with Xcode command line tools installed.
# Usage: ./scripts/build.sh

set -e

APP_NAME="HelloWorld"
BUNDLE_ID="com.zodl.helloworld"
VERSION="1.0.0"
BUILD_DIR="build"

echo "==> Cleaning build dir..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

echo "==> Compiling Swift (arm64)..."
swiftc Sources/main.swift \
    -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx13.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)"

echo "==> Copying Info.plist..."
cp Resources/Info.plist "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"

echo "==> Ad-hoc signing (no Apple Developer account needed for local testing)..."
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"

echo "==> Building DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUILD_DIR/$APP_NAME.app" \
    -ov -format UDZO \
    -o "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo ""
echo "✅ Done!"
echo "   App:  $BUILD_DIR/$APP_NAME.app"
echo "   DMG:  $BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo ""
echo "To test: open $BUILD_DIR/$APP_NAME.app"
echo ""
echo "NOTE: For distribution you need to:"
echo "  1. Sign with a real Apple Developer ID (codesign --sign 'Developer ID Application: ...')"
echo "  2. Notarize with: xcrun notarytool submit ... --wait"
echo "  3. Staple: xcrun stapler staple ..."
