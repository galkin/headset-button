#!/bin/bash
# Builds build/Headset Button.app with xcodebuild and ad-hoc signs it.
# Usage: scripts/build-app.sh [Debug|Release]   (default: Release)
# Optional env: VERSION (CFBundleShortVersionString, e.g. 1.2.0) and BUILD_NUMBER
# (CFBundleVersion); without them the values in Resources/Info.plist are kept.
set -euo pipefail

CONFIG="${1:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
APP="$ROOT/build/Headset Button.app"
BUNDLE_ID="in.galk.HeadsetButton"

cd "$ROOT"
xcodebuild build \
    -scheme HeadsetButton \
    -configuration "$CONFIG" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -quiet

PRODUCTS="$DERIVED/Build/Products/$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/HeadsetButton" "$APP/Contents/MacOS/HeadsetButton"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
# App icon (CFBundleIconFile = AppIcon); rebuild it with scripts/make-icon.sh.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: Resources/AppIcon.icns missing; the app gets the generic icon" >&2
fi
# SwiftPM resource bundles, if any.
for b in "$PRODUCTS"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Ad-hoc sign with an explicit designated requirement that names only the
# bundle id. The default ad-hoc requirement pins the cdhash, which changes on
# every build and would invalidate a TCC (Accessibility) grant.
codesign --force --deep --sign - \
    --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP"

echo "Built $APP ($(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist") build $(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist"))"
