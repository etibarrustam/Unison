#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# CONFIG=release for optimized installs (Homebrew uses this).
CONFIG="${CONFIG:-debug}"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/Unison"

APP="build/Unison.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Unison"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Unison</string>
  <key>CFBundleIdentifier</key><string>com.unison.app</string>
  <key>CFBundleExecutable</key><string>Unison</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Unison redistributes the sound your Mac plays across your speakers by their positions. It never uses the microphone.</string>
</dict>
</plist>
PLIST

# Stable designated requirement so TCC grants survive rebuilds.
codesign --force --deep --sign - \
  --identifier com.unison.app \
  -r='designated => identifier "com.unison.app"' \
  "$APP"
echo "Built $APP"
