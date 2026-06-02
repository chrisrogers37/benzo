#!/bin/bash
set -euo pipefail

# Build, sign, notarize, and package Benzo as a DMG
# Prerequisites:
#   - Apple Developer certificate installed in Keychain
#   - Set APPLE_ID, APPLE_TEAM_ID, and APP_PASSWORD env vars (or pass as args)
#   - Xcode command line tools

VERSION=$(xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -showBuildSettings 2>/dev/null | grep MARKETING_VERSION | tr -d ' ' | cut -d= -f2)
ARCHIVE_PATH="build/Benzo.xcarchive"
EXPORT_PATH="build/export"
DMG_NAME="Benzo-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"

echo "=== Building Benzo v${VERSION} ==="

# Clean build directory
rm -rf build
mkdir -p build

# Archive
echo "→ Archiving..."
xcodebuild -project Benzo/Benzo.xcodeproj \
    -scheme Benzo \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    archive

# Export — requires a Developer ID Application certificate.
# When one isn't installed, fall back to the ad-hoc–signed .app already inside
# the archive (used for unsigned community releases).
echo "→ Exporting..."
mkdir -p "${EXPORT_PATH}"
cat > build/ExportOptions.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

if xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist build/ExportOptions.plist 2>build/export.log; then
    echo "  ↳ exported via Developer ID"
else
    echo "⚠ developer-id export failed — copying ad-hoc–signed .app from archive"
    grep -i "error" build/export.log || true
    rm -rf "${EXPORT_PATH}/Benzo.app"
    cp -R "${ARCHIVE_PATH}/Products/Applications/Benzo.app" "${EXPORT_PATH}/Benzo.app"
fi

# Notarize
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    echo "→ Notarizing..."
    xcrun notarytool submit "${EXPORT_PATH}/Benzo.app" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APP_PASSWORD}" \
        --wait

    echo "→ Stapling..."
    xcrun stapler staple "${EXPORT_PATH}/Benzo.app"
else
    echo "⚠ Skipping notarization (set APPLE_ID, APPLE_TEAM_ID, APP_PASSWORD)"
fi

# Create DMG
echo "→ Creating DMG..."
hdiutil create -volname "Benzo" \
    -srcfolder "${EXPORT_PATH}/Benzo.app" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Notarize the DMG too
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    echo "→ Notarizing DMG..."
    xcrun notarytool submit "${DMG_PATH}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APP_PASSWORD}" \
        --wait

    xcrun stapler staple "${DMG_PATH}"
fi

echo ""
echo "=== Done ==="
echo "DMG: ${DMG_PATH}"
echo "SHA256: $(shasum -a 256 "${DMG_PATH}" | cut -d' ' -f1)"
echo ""
echo "Upload to GitHub Releases:"
echo "  gh release create v${VERSION} ${DMG_PATH} --title 'Benzo v${VERSION}' --notes 'Release notes here'"
