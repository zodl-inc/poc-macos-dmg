#!/bin/bash
# Build Zodl.app, sign with Developer ID, create signed DMG.
# Requires: Xcode CLI tools + Developer ID Application cert in keychain.
set -e

APP_NAME="Zodl"
VERSION=$(defaults read "$(pwd)/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
BUILD_DIR="build"
IDENTITY="Developer ID Application: The Zerocoin Electric Coin Company LLC (RLPRR8CPQG)"

echo "==> Building $APP_NAME v$VERSION..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

swiftc Sources/main.swift Sources/Updater.swift \
    -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library

cp Resources/Info.plist "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"

echo "==> Signing with Developer ID..."
codesign --force --deep --options runtime \
    --sign "$IDENTITY" \
    "$BUILD_DIR/$APP_NAME.app"

codesign --verify --deep --strict "$BUILD_DIR/$APP_NAME.app" && echo "  Signature OK"

echo "==> Building signed DMG (with Applications symlink)..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME-$VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    -o "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Signing DMG..."
codesign --force --sign "$IDENTITY" "$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo ""
echo "✅ Done: build/$APP_NAME-$VERSION.dmg (signed)"
echo "   SHA256 + Ed25519 sig computed after notarization (staple modifies the DMG)"
