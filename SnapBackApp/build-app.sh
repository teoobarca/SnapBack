#!/bin/bash
# Build SnapBack menu bar app into a proper .app bundle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SnapBack"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Building SnapBack menu bar app..."

# Build release version
cd "$SCRIPT_DIR"
swift build -c release

# Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/SnapBackApp" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
SNAPBACK_CLI_PATH="${SNAPBACK_CLI_PATH:-}"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SnapBack</string>
    <key>CFBundleIdentifier</key>
    <string>com.snapback.menubar</string>
    <key>CFBundleName</key>
    <string>SnapBack</string>
    <key>CFBundleDisplayName</key>
    <string>SnapBack</string>
    <key>CFBundleVersion</key>
    <string>1.2</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [[ -n "$SNAPBACK_CLI_PATH" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SnapBackCLIPath string $SNAPBACK_CLI_PATH" \
    "$APP_BUNDLE/Contents/Info.plist"
fi

echo "✓ Built: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -r '$APP_BUNDLE' /Applications/"
echo ""
echo "To add to Login Items:"
echo "  1. Open System Settings → General → Login Items"
echo "  2. Click + and select SnapBack.app"
echo ""
echo "Or run directly:"
echo "  open '$APP_BUNDLE'"
