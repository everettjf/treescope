# TreescopeiOSDemo

A real **iOS** app that embeds `TreescopeServer`, used to verify capture on the iOS Simulator
(UIKit + SwiftUI + keyboard). It mixes a SwiftUI screen with a genuine UIKit subtree (label, text
field, button) bridged in via `UIViewControllerRepresentable`.

The Xcode project is generated with [xcodegen](https://github.com/yonaskolb/XcodeGen) from
`project.yml` (so it isn't committed). It depends on the local SwiftPM package at the repo root.

## Run it

```bash
cd Examples/TreescopeiOSDemo
./run.sh                       # generate + build + boot sim + install + launch + verify
```

Or step by step (substitute any installed simulator for `$DEV`):

```bash
DEV="iPhone 17 Pro"   # any device from `xcrun simctl list devices available`
xcodegen generate
xcodebuild -project TreescopeiOSDemo.xcodeproj -scheme TreescopeiOSDemo \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=$DEV" \
  -derivedDataPath build build
xcrun simctl boot "$DEV"
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/TreescopeiOSDemo.app
xcrun simctl launch booted com.treescope.iosdemo
```

Then open **http://127.0.0.1:47761** in a browser on the host Mac — the Simulator shares the host
network stack, so loopback reaches the app.

## Verify headlessly

`verify.mjs` connects over WebSocket, handshakes, fetches the hierarchy, and prints a summary:

```bash
node verify.mjs
# VERIFY: handshake ok — TreescopeiOSDemo on iOS 26.2 (sim=true)
# VERIFY: captured 96 nodes — 85 UIKit, 1 SwiftUI, 10 CALayer
# VERIFY: labels seen: uikit.card | uikit.title | uikit.textField | uikit.count | uikit.button
# VERIFY SUCCEEDED ✅
```

(Exact counts vary by device/OS; the above is a real run on an iPhone 17 Pro, iOS 26.2.)
