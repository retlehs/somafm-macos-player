#!/bin/bash

# Build script for SomaFM macOS app
set -e

echo "🎵 Building SomaFM Player..."

# Parse arguments
SKIP_INTERACTIVE=false
CREATE_ZIP=false
SKIP_CLEAN=false
NOTARIZE=false
CREATE_DMG=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ci) SKIP_INTERACTIVE=true; CREATE_ZIP=true ;;
        --zip) CREATE_ZIP=true ;;
        --dmg) CREATE_DMG=true ;;
        --notarize) NOTARIZE=true ;;
        --skip-clean) SKIP_CLEAN=true ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --ci          CI mode: non-interactive, creates zip"
            echo "  --zip         Create zip archive"
            echo "  --dmg         Create DMG disk image"
            echo "  --notarize    Notarize the app (requires APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD)"
            echo "  --skip-clean  Skip cleaning previous builds"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

APP_NAME="SomaFM Menu Bar Player"
BUNDLE_ID="com.benword.somafm-menubar-player"

# Colors for output (disabled in CI)
if [ -n "$CI" ] || [ "$SKIP_INTERACTIVE" = true ]; then
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Clean previous builds
if [ "$SKIP_CLEAN" = false ]; then
    echo "🧹 Cleaning previous builds..."
    rm -rf build
    swift package clean
fi

# Build release version
echo "🔨 Building release version..."
swift build -c release

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "build/${APP_NAME}.app/Contents/MacOS"
mkdir -p "build/${APP_NAME}.app/Contents/Resources"

# Copy binary with correct name to match CFBundleExecutable
cp .build/release/SomaFM "build/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp Info.plist "build/${APP_NAME}.app/Contents/"

# Copy entitlements for signing reference
cp SomaFM.entitlements "build/${APP_NAME}.app/Contents/"

# Copy Privacy Manifest if it exists
if [ -f PrivacyInfo.xcprivacy ]; then
    cp PrivacyInfo.xcprivacy "build/${APP_NAME}.app/Contents/Resources/"
fi

# Copy icon if it exists
if [ -f Icon.icns ]; then
    echo "🎨 Adding app icon..."
    cp Icon.icns "build/${APP_NAME}.app/Contents/Resources/"
fi

# Sign the app
sign_app() {
    local identity="$1"
    echo "🔏 Signing app with: ${identity}..."
    codesign --deep --force --verify --verbose \
        --options runtime \
        --entitlements SomaFM.entitlements \
        --sign "$identity" \
        "build/${APP_NAME}.app"
    echo -e "${GREEN}✅ App signed successfully${NC}"
}

if [ -n "$CODESIGN_IDENTITY" ]; then
    sign_app "$CODESIGN_IDENTITY"
elif security find-identity -p codesigning -v 2>/dev/null | grep -q "Developer ID Application"; then
    IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -1 | awk '{print $2}')
    sign_app "$IDENTITY"
else
    echo -e "${YELLOW}⚠️  No Developer ID certificate found. App will not be signed.${NC}"
    echo "   Set CODESIGN_IDENTITY env var or install a Developer ID certificate."
    if [ "$NOTARIZE" = true ]; then
        echo -e "${RED}❌ Cannot notarize unsigned app${NC}"
        exit 1
    fi
fi

# Verify the app bundle
echo "🔍 Verifying app bundle..."
if [ ! -f "build/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" ]; then
    echo -e "${RED}❌ Failed to create app bundle${NC}"
    exit 1
fi
echo -e "${GREEN}✅ App bundle created successfully!${NC}"

# Create ZIP
if [ "$CREATE_ZIP" = true ] || [ "$NOTARIZE" = true ]; then
    echo "📦 Creating ZIP archive..."
    cd build
    /usr/bin/ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
    cd ..
    echo -e "${GREEN}✅ ZIP created: build/${APP_NAME}.zip${NC}"
fi

# Notarize
if [ "$NOTARIZE" = true ]; then
    echo "📤 Submitting for notarization..."

    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
        echo -e "${RED}❌ Notarization requires APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD env vars${NC}"
        echo "   Generate an app-specific password at https://appleid.apple.com/account/manage"
        exit 1
    fi

    xcrun notarytool submit "build/${APP_NAME}.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "build/${APP_NAME}.app"

    echo -e "${GREEN}✅ App notarized and stapled successfully${NC}"

    # Re-create ZIP with stapled app
    echo "📦 Re-creating ZIP with stapled app..."
    rm -f "build/${APP_NAME}.zip"
    cd build
    /usr/bin/ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
    cd ..
fi

# Print SHA256 for the ZIP
if [ -f "build/${APP_NAME}.zip" ]; then
    SHA256=$(shasum -a 256 "build/${APP_NAME}.zip" | awk '{print $1}')
    echo "📝 SHA256: $SHA256"
fi

# Create DMG
if [ "$CREATE_DMG" = true ]; then
    echo "💿 Creating DMG..."
    mkdir -p build/dmg
    cp -r "build/${APP_NAME}.app" build/dmg/
    ln -s /Applications build/dmg/Applications

    hdiutil create -volname "SomaFM Player" \
                   -srcfolder build/dmg \
                   -ov \
                   -format UDZO \
                   "build/SomaFM.dmg"

    rm -rf build/dmg

    if [ "$NOTARIZE" = true ]; then
        echo "📤 Notarizing DMG..."
        xcrun notarytool submit "build/SomaFM.dmg" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --wait
        xcrun stapler staple "build/SomaFM.dmg"
    fi

    echo -e "${GREEN}✅ DMG created: build/SomaFM.dmg${NC}"
fi

# Interactive mode hints
if [ "$SKIP_INTERACTIVE" = false ]; then
    echo ""
    echo "📍 Location: $(pwd)/build/${APP_NAME}.app"
    echo ""
    echo "To install:"
    echo "  cp -r \"build/${APP_NAME}.app\" /Applications/"
    echo ""
    echo "Or run directly:"
    echo "  open \"build/${APP_NAME}.app\""
fi

echo ""
echo "🎉 Build complete!"
exit 0
