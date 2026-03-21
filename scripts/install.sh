#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Claude Vision"
APP_BUNDLE="/Applications/${APP_NAME}.app"
CLI_NAME="claude-vision"
APP_BIN_NAME="claude-vision-app"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release

RELEASE_DIR="$PROJECT_DIR/.build/release"

# Create .app bundle
echo "Creating ${APP_NAME}.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy both binaries into the .app so they can find each other
cp "$RELEASE_DIR/$CLI_NAME" "$APP_BUNDLE/Contents/MacOS/$CLI_NAME"
cp "$RELEASE_DIR/$APP_BIN_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_BIN_NAME"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Claude Vision</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Vision</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude.vision</string>
    <key>CFBundleVersion</key>
    <string>0.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleExecutable</key>
    <string>claude-vision-app</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Claude Vision needs screen recording access to capture screenshots of the selected area.</string>
</dict>
</plist>
PLIST

# Code-sign the .app so macOS remembers permissions across rebuilds
echo "Code-signing..."
codesign --force --sign - --deep "$APP_BUNDLE"

# Symlink CLI to ~/.local/bin
mkdir -p "$HOME/.local/bin"
ln -sf "$APP_BUNDLE/Contents/MacOS/$CLI_NAME" "$HOME/.local/bin/$CLI_NAME"
ln -sf "$APP_BUNDLE/Contents/MacOS/$APP_BIN_NAME" "$HOME/.local/bin/$APP_BIN_NAME"

echo ""
echo "Installed:"
echo "  App:  $APP_BUNDLE"
echo "  CLI:  ~/.local/bin/$CLI_NAME -> $APP_BUNDLE/Contents/MacOS/$CLI_NAME"
echo ""
echo "Usage:"
echo "  Open \"${APP_NAME}\" from Applications/Spotlight"
echo "  Or: claude-vision start"
