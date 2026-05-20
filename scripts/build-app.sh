#!/bin/sh
set -eu

APP_NAME="ModDrag"
BINARY_NAME="mod-drag"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$BUILD_DIR/module-cache"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

xcrun swiftc \
  -O \
  -parse-as-library \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework IOKit \
  -module-cache-path "$MODULE_CACHE" \
  main.swift \
  -o "$MACOS_DIR/$BINARY_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>mod-drag</string>
  <key>CFBundleIdentifier</key>
  <string>dev.u1dm.ModDrag</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ModDrag</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.2</string>
  <key>CFBundleVersion</key>
  <string>0.1.2</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 u1dm</string>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
