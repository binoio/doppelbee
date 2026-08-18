#!/bin/bash
# Build, sign, and notarize DuoBee for distribution
#
# Produces a signed, notarized, STAPLED build/export/DuoBee.app. That stapled
# bundle is what scripts/release.sh zips as the Sparkle update enclosure, so the
# app itself is notarized here rather than only the disk image.
#
# Prerequisites:
#   - Valid Apple Developer ID Application certificate installed
#   - Notarization credentials stored in the keychain:
#       xcrun notarytool store-credentials "<profile>" --apple-id <id> --team-id <team>
#   - Set TEAM_ID environment variable
#
# Usage:
#   TEAM_ID=<your-team-id> ./scripts/notarize.sh
#   TEAM_ID=<...> NOTARY_PROFILE=<profile> ./scripts/notarize.sh
#   TEAM_ID=<...> ./scripts/notarize.sh --use-existing-export
#   TEAM_ID=<...> ./scripts/notarize.sh --dmg
#
# --use-existing-export skips the clean rebuild and packages whatever is already
# at build/export/DuoBee.app. Use it to ship the exact bundle you tested: a
# rebuild from identical source is not byte-identical, because Xcode embeds
# build and signature timestamps.
#
# --dmg additionally builds, signs, notarizes, and staples a disk image. Sparkle
# updates do not use it; it is for the manual first-install download.

set -e

cd "$(dirname "$0")/.."

# Configuration
APP_NAME="DuoBee"
BUNDLE_ID="edu.princeton.orfe.duobee"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
NOTARIZE_ZIP="$BUILD_DIR/notarize.zip"
USE_EXISTING_EXPORT=false
MAKE_DMG=false

while [ $# -gt 0 ]; do
    case "$1" in
        --use-existing-export)
            USE_EXISTING_EXPORT=true
            ;;
        --dmg)
            MAKE_DMG=true
            ;;
        -h|--help)
            sed -n '2,26p' "$0"
            exit 0
            ;;
        *)
            echo "Error: unknown option '$1'"
            echo "Usage: TEAM_ID=<team> ./scripts/notarize.sh [--use-existing-export] [--dmg]"
            exit 1
            ;;
    esac
    shift
done

# Check for required environment variables
if [ -z "$TEAM_ID" ]; then
    echo "Error: TEAM_ID environment variable not set"
    echo "Usage: TEAM_ID=<your-team-id> ./scripts/notarize.sh"
    exit 1
fi

# Fail early rather than after a full archive build
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Error: no notarization credentials for profile '$NOTARY_PROFILE'"
    echo "Store them with:"
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id $TEAM_ID"
    exit 1
fi

if [ "$USE_EXISTING_EXPORT" = true ]; then
    if [ ! -d "$APP_PATH" ]; then
        echo "Error: --use-existing-export given but $APP_PATH does not exist"
        echo "Run without the flag to build it."
        exit 1
    fi
    echo "Using existing export at $APP_PATH (skipping rebuild)"
    rm -f "$NOTARIZE_ZIP"
else
    # Clean previous builds. DerivedData is preserved: it holds the resolved
    # Sparkle package artifacts, and re-resolving on every release is wasteful.
    echo "Cleaning previous builds..."
    rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$NOTARIZE_ZIP" "$BUILD_DIR/$APP_NAME"*.dmg
    mkdir -p "$BUILD_DIR"

    # Build and archive. -derivedDataPath is pinned so release.sh can find the
    # Sparkle CLI tools (generate_appcast) at a stable path instead of hunting
    # through a hashed DerivedData directory.
    echo "Building archive..."
    xcodebuild archive \
        -project DuoBee.xcodeproj \
        -scheme DuoBee \
        -archivePath "$ARCHIVE_PATH" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGN_IDENTITY="Developer ID Application" \
        DEVELOPMENT_TEAM="$TEAM_ID"

    # Export archive
    echo "Exporting archive..."
    cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"
fi

# Notarize the app itself. ditto (not zip) preserves the bundle's symlink
# structure, which Sparkle.framework's Versions/ layout depends on.
echo "Submitting app for notarization (this can take several minutes)..."
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
rm -f "$NOTARIZE_ZIP"

# Staple the ticket into the .app so it validates offline, including after
# Sparkle extracts it on a machine that has never seen this version.
echo "Stapling notarization ticket to the app..."
xcrun stapler staple "$APP_PATH"

echo "Verifying app..."
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute -v "$APP_PATH"

if [ "$MAKE_DMG" = true ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
    DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

    echo "Creating DMG..."
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_PATH" \
        -ov -format UDZO \
        "$DMG_PATH"

    echo "Signing DMG..."
    codesign --sign "Developer ID Application" \
        --timestamp \
        --options runtime \
        "$DMG_PATH"

    # The DMG is a separate distributable and needs its own ticket, even though
    # the app inside is already stapled.
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "Stapling DMG..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
echo ""
echo "Notarized build complete: $APP_PATH (version $VERSION)"
if [ "$MAKE_DMG" = true ]; then
    echo "Disk image: $BUILD_DIR/$APP_NAME-$VERSION.dmg"
fi
