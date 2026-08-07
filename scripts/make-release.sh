#!/bin/bash
# Generate appcast.xml for Sparkle auto-update and upload to GitHub Releases.
# Requires: sparkle's generate_appcast tool, gh CLI, and a signed+notarized DMG.
# Usage: ./scripts/make-release.sh 1.0.1

set -e

VERSION="${1:?Usage: $0 <version>}"
DMG="build/HelloWorld-$VERSION.dmg"
APPCAST="appcast.xml"
REPO="zodl-inc/poc-macos-dmg"

if [ ! -f "$DMG" ]; then
    echo "ERROR: $DMG not found. Run build.sh first."
    exit 1
fi

echo "==> Creating GitHub Release v$VERSION..."
gh release create "v$VERSION" "$DMG" \
    --repo "$REPO" \
    --title "HelloWorld v$VERSION" \
    --notes "Release v$VERSION" \
    --latest

DMG_URL=$(gh release view "v$VERSION" --repo "$REPO" --json assets \
    --jq '.assets[] | select(.name | endswith(".dmg")) | .browserDownloadUrl')
echo "DMG URL: $DMG_URL"

echo "==> Generating appcast entry..."
# Sparkle's generate_appcast handles EdDSA signature + length automatically.
# If you don't have it: brew install sparkle
SPARKLE_BIN="$(brew --prefix sparkle 2>/dev/null)/bin"
if [ -d "$SPARKLE_BIN" ]; then
    "$SPARKLE_BIN/generate_appcast" build/ --download-url-prefix \
        "https://github.com/$REPO/releases/download/v$VERSION/"
else
    echo "WARNING: Sparkle not found. Generating minimal appcast manually..."
    DMG_SIZE=$(stat -f%z "$DMG")
    cat > "$APPCAST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>HelloWorld</title>
        <item>
            <title>HelloWorld $VERSION</title>
            <sparkle:version>$(echo $VERSION | tr -d '.')</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <pubDate>$(date -R)</pubDate>
            <enclosure
                url="$DMG_URL"
                sparkle:version="$(echo $VERSION | tr -d '.')"
                sparkle:shortVersionString="$VERSION"
                length="$DMG_SIZE"
                type="application/octet-stream"
                sparkle:edSignature="SIGN_WITH_generate_appcast" />
        </item>
    </channel>
</rss>
EOF
fi

echo "==> Committing appcast.xml to repo (served via GitHub raw)..."
git add appcast.xml
git commit -m "release: update appcast to v$VERSION"
git push origin main

echo ""
echo "✅ Release done!"
echo "   GitHub Release: https://github.com/$REPO/releases/tag/v$VERSION"
echo "   Appcast URL:    https://raw.githubusercontent.com/$REPO/main/appcast.xml"
