#!/bin/bash
# Build TermGrid V2 and install to ~/Applications
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications/TermGrid-V2.app"
ICON_SRC="$PROJECT_DIR/Sources/TermGrid/Resources/Assets.xcassets/AppIcon.appiconset"

echo "Building TermGrid V2..."
cd "$PROJECT_DIR"
swift build -c debug

echo "Installing to $APP_DIR..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$PROJECT_DIR/.build/arm64-apple-macosx/debug/TermGrid" "$APP_DIR/Contents/MacOS/TermGrid"

# Copy resource bundle
cp -R "$PROJECT_DIR/.build/arm64-apple-macosx/debug/TermGrid_TermGrid.bundle" "$APP_DIR/Contents/Resources/"

# Build icns if needed
if [ ! -f "$APP_DIR/Contents/Resources/AppIcon.icns" ] || [ "$ICON_SRC/icon_1024x1024.png" -nt "$APP_DIR/Contents/Resources/AppIcon.icns" ]; then
    echo "Rebuilding icon..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_SRC/icon_16x16.png"     --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC/icon_32x32.png"      --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC/icon_32x32.png"      --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "$ICON_SRC/icon_64x64.png"      --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$ICON_SRC/icon_128x128.png"    --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC/icon_256x256.png"    --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC/icon_256x256.png"    --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC/icon_512x512.png"    --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC/icon_512x512.png"    --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC/icon_1024x1024.png"  --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Write Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TermGrid</string>
    <key>CFBundleIdentifier</key>
    <string>com.samuel-tucker.termgrid-v2</string>
    <key>CFBundleName</key>
    <string>TermGrid V2</string>
    <key>CFBundleDisplayName</key>
    <string>TermGrid V2</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
PLIST

# Sign
echo "Signing..."
codesign --force --deep --sign - "$APP_DIR"

# Register with Launch Services (makes Spotlight find it)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"

echo "Done! TermGrid V2 installed and registered with Spotlight."
echo "Launch with: open '$APP_DIR' or search 'TermGrid' in Spotlight"
