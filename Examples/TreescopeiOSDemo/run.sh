#!/usr/bin/env bash
# Generate, build, boot, install, launch, and verify the iOS demo on a Simulator.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="com.treescope.iosdemo"

# Pick a device: $TS_DEVICE if set, else the first available iPhone simulator.
DEVICE="${TS_DEVICE:-}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9][^(]*' | head -1 | sed 's/[[:space:]]*$//')
fi
if [ -z "$DEVICE" ]; then
  echo "No available iPhone simulator found. Set TS_DEVICE to one from:"
  xcrun simctl list devices available | grep iPhone
  exit 1
fi
echo "▸ Using device: $DEVICE"

echo "▸ Generating project…"
xcodegen generate

echo "▸ Building…"
xcodebuild -project TreescopeiOSDemo.xcodeproj -scheme TreescopeiOSDemo \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build build | tail -3

APP="build/Build/Products/Debug-iphonesimulator/TreescopeiOSDemo.app"

echo "▸ Booting…"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "▸ Installing + launching…"
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" "$BUNDLE"

echo "▸ Waiting for the server…"
sleep 6

echo "▸ Verifying over WebSocket…"
node verify.mjs

echo "▸ Open http://127.0.0.1:47761 in your browser to inspect the running app."
