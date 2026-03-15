#!/bin/bash
# Build Skrivar.app — native Swift menubar app
# Usage: ./build_app.sh [version]
#   version: e.g. "0.4.0" — defaults to git tag or "0.0.0-dev"
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Skrivar"
APP_DIR="$SCRIPT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Determine version: argument > git tag > fallback
if [ -n "$1" ]; then
    VERSION="$1"
elif git describe --tags --exact-match HEAD 2>/dev/null | grep -q '^v'; then
    VERSION=$(git describe --tags --exact-match HEAD | sed 's/^v//')
else
    VERSION="0.0.0-dev"
fi

echo "Building $APP_NAME v$VERSION..."

# Build release binary
CONFIGURATION="${BUILD_CONFIG:-release}"
echo "Configuration: $CONFIGURATION"
swift build -c "$CONFIGURATION" 2>&1

echo "Creating $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy the compiled binary
cp ".build/$CONFIGURATION/Skrivar" "$MACOS_DIR/Skrivar"

# Copy app icon if available
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    ICON_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    ICON_ENTRY=""
fi

# Create Info.plist with dynamic version
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Skrivar</string>
    <key>CFBundleDisplayName</key>
    <string>Skrivar</string>
    <key>CFBundleIdentifier</key>
    <string>com.skrivar.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>Skrivar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Skrivar needs microphone access to record speech for transcription.</string>
$ICON_ENTRY
</dict>
</plist>
PLIST

echo "✅ Built: $APP_DIR (v$VERSION)"

# Create distributable .zip
if [ "${CREATE_ZIP:-true}" = "true" ]; then
    ZIP_PATH="$SCRIPT_DIR/dist/Skrivar-v${VERSION}.zip"
    cd "$SCRIPT_DIR/dist"
    zip -r -q "$ZIP_PATH" "$APP_NAME.app"
    cd "$SCRIPT_DIR"
    echo "📦 Zip: $ZIP_PATH"
fi

echo ""
echo "To run:     open dist/Skrivar.app"
echo "To install: cp -r dist/Skrivar.app /Applications/"
