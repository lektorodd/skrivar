#!/bin/bash
# Build Skrivar.app — native Swift menubar app
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Skrivar"
APP_DIR="$SCRIPT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building Swift binary..."
swift build 2>&1

echo "Creating $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy the compiled binary
cp .build/debug/Skrivar "$MACOS_DIR/Skrivar"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Skrivar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Skrivar needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

echo "✅ Built: $APP_DIR"
echo ""
echo "To run:     open dist/Skrivar.app"
echo "To install: cp -r dist/Skrivar.app /Applications/"
