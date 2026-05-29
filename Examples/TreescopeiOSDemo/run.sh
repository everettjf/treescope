#!/usr/bin/env bash
# Generate, build, boot, install, launch, and verify the iOS demo on a Simulator.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${TS_DEVICE:-iPhone 16 Pro}"
BUNDLE="com.treescope.iosdemo"

echo "▸ Generating project…"
xcodegen generate

echo "▸ Building for $DEVICE…"
xcodebuild -project TreescopeiOSDemo.xcodeproj -scheme TreescopeiOSDemo \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build build | tail -3

APP="build/Build/Products/Debug-iphonesimulator/TreescopeiOSDemo.app"

echo "▸ Booting $DEVICE…"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "▸ Installing + launching…"
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" "$BUNDLE"

echo "▸ Waiting for the server…"
sleep 5

echo "▸ Verifying over WebSocket…"
node verify.mjs

echo "▸ Open http://127.0.0.1:47761 in your browser to inspect the running app."
