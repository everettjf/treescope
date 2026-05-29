# Treescope

> An open-source runtime **view inspector** for SwiftUI + UIKit/AppKit, viewed in your **browser**.
> A free alternative to Lookin / LookInside — with first-class, open SwiftUI tree inspection.
>
> *Put your SwiftUI tree under the scope.*

![Treescope browser viewer](docs/viewer-screenshot.png)

Treescope captures the live view hierarchy of a running iOS/macOS/tvOS app — UIKit, AppKit,
**SwiftUI, and CALayers** — and serves it to a **browser-based viewer** where you can browse the
tree, inspect properties, see frames/snapshots, view an exploded 3D layer view, and edit some
properties live. No app to install: the inspected app hosts the viewer itself over loopback HTTP.

The original [Lookin](https://github.com/QMUI/LookinServer) is open source but **UIKit-only**.
Its successor [LookInside](https://github.com/LookInsideApp/LookInside) adds SwiftUI inspection —
but ships that capability as a **closed-source signed binary**. Treescope makes the SwiftUI part
open, and delivers the whole viewer as a zero-install web app.

---

## Why a browser viewer?

- **Zero install, cross-platform.** Anyone opens `http://127.0.0.1:47761` — macOS, Linux, Windows.
  No Xcode, no second app to build.
- **Easy to share.** It's a URL. Screenshots and bug reports just work.
- **Zero dependencies in your app.** The embedded server is a tiny HTTP/1.1 + WebSocket
  implementation built directly on `Network.framework` + `CryptoKit`. Adding Treescope does **not**
  pull Vapor/NIO or anything else into your app.

---

## Components

| Module | Role |
|---|---|
| **`TreescopeProtocol`** | Pure-Foundation shared data model + a clean, discriminated JSON wire contract mirrored by the TypeScript client. |
| **`TreescopeServer`** | The **debug-only runtime** you embed in your app. Captures UIKit/AppKit/SwiftUI/CALayer and serves the viewer + protocol over loopback HTTP + WebSocket. Bundles the built viewer as a resource. |
| **`Web/`** | The browser viewer: React + TypeScript + Tailwind + shadcn/ui. Builds to a single self-contained HTML embedded into `TreescopeServer`. |
| **`TreescopeDemo`** | A sample SwiftUI app that embeds the server (also runs a self-test probe). |
| **`Examples/TreescopeiOSDemo`** | A real iOS app for Simulator end-to-end testing (UIKit + SwiftUI + keyboard). |
| **`Archive/`** | The previous native-SwiftUI macOS viewer + client core, kept for reference. Not built. |

Everything is Swift + TypeScript. MIT licensed.

---

## How it works

```
┌─────────────────────────── Your app (Debug build) ───────────────────────────┐
│  TreescopeServer                                                              │
│    • CaptureEngine        walks UIWindow/NSWindow → views → layers            │
│    • SwiftUIReflector     opens `any View`, unwraps ModifiedContent /         │
│                           TupleView / Group / _ConditionalContent, descends   │
│                           custom `body`, reads @State, modifiers, Text…       │
│    • LayerCapture         walks standalone CALayers → resolved geometry       │
│    • HTTPServer           NWListener on 127.0.0.1 (+ Bonjour):                │
│        GET /              → the bundled browser viewer (single HTML)          │
│        GET /snapshot/{id} → a rendered PNG of a node                          │
│        GET /ws            → WebSocket carrying the JSON inspector protocol     │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                     │  loopback HTTP/WS (works for the iOS Simulator)
┌────────────────────────────────────▼──────────────────────────────────────────┐
│  Any browser  →  http://127.0.0.1:47761                                        │
│    Tree outline · Canvas (snapshot + wireframe + exploded 3D) · Inspector      │
└────────────────────────────────────────────────────────────────────────────────┘
```

### SwiftUI inspection

Treescope reflects SwiftUI **without** any private API on the primary path:

- Opens the existential `any View` and inspects the concrete type with `Mirror`.
- Structurally unwraps combinators: `ModifiedContent`, `TupleView`, `Group`, `AnyView`,
  `_ConditionalContent`, `Optional`.
- For **your** views (a real `body`), it descends into `body` to recover the declared tree.
- For framework primitives it scans stored properties to find child views and pulls out
  notable values (e.g. a `Text`'s string, a modifier's parameters, `@State` values).

**Live values.** Once a view is hosted, SwiftUI installs `@State`/`@StateObject`/… onto a live
AttributeGraph location. Treescope reads reference-typed observable state genuinely live: an
`@ObservedObject`/`ObservableObject` model is shared by reference, so its current `@Published`
fields are surfaced and marked `(live)` (a model mutation shows up on the next capture). Value-typed
`@State` on the reflected `rootView` copy isn't graph-backed there, so it shows its declared value.

> **What you get where:** Directly-created hosting views (`UIHostingController` /
> `NSHostingView` — the common "SwiftUI inside a UIKit/AppKit app" case) yield the full
> **declaration** tree (VStack, Text with content, modifiers, `@State`). The CALayer walk gives
> SwiftUI hosting views real *resolved* rendered geometry on the canvas. The one remaining gap: a
> **pure-SwiftUI-lifecycle macOS window root** (`AppKitWindowHostingView`) has an empty `Mirror`,
> so its declaration tree isn't reachable there (the resolved render tree still is).

A best-effort private `_viewDebugData` / `makeViewDebugData` probe (`ViewDebugDataExtractor`) is
included and fully guarded; because the server is **Debug-only**, any private-API use carries no
App Store review risk.

---

## Quick start

### 1. Add the server to your app (Debug only)

`Package.swift`:

```swift
.product(name: "TreescopeServer", package: "treescope")
```

Start it once, early, guarded for Debug:

```swift
import TreescopeServer

#if DEBUG
Treescope.start()      // serves http://127.0.0.1:47761 (scans forward if busy)
#endif
```

CocoaPods users: scope the pod to Debug so it is excluded from Release:

```ruby
pod 'Treescope', :configurations => ['Debug']
```

### 2. Open the viewer

Run your app, then open **`http://127.0.0.1:47761`** in any browser.

(For the iOS Simulator, `127.0.0.1` on your Mac reaches the app because the simulator shares the
host network stack.)

### Try it end-to-end

```bash
swift run TreescopeDemo     # a sample app that embeds the server
open http://127.0.0.1:47761 # inspect it in your browser
```

---

## Features

- **Unified tree** of UIKit/AppKit views, SwiftUI nodes, and CALayers, colour-coded by framework,
  with search/filter, hide-system-views, keyboard navigation (↑/↓/←/→) and match highlighting.
- **Property inspector** with typed rendering: colours, geometry, booleans, enums, nested values.
- **Live editing** of common properties (alpha/opacity, hidden, cornerRadius, border, background
  colour, text, layer properties…), for views *and* layers.
- **Canvas** with rendered per-node snapshots, frame wireframes, click-to-select, zoom/pan, an
  **exploded 3D** layer view, and hover ↔ tree sync.
- **On-device highlight** of the selected view or layer.
- **Zero-install browser viewer**, served by the app itself.

---

## Building & testing

### Swift package

```bash
swift build            # TreescopeServer + TreescopeDemo (macOS)
swift test             # protocol round-trip, SwiftUI reflector, live-state, AppKit capture,
                       # WebSocket framing, and a real HTTP/WS end-to-end test

# verify the embeddable server compiles for iOS
xcodebuild -scheme TreescopeServer -destination 'generic/platform=iOS Simulator' build
```

There's also a runtime self-probe in the demo (`TREESCOPE_PROBE=1 swift run TreescopeDemo`) and a
real iOS Simulator example with a headless WebSocket verifier under `Examples/TreescopeiOSDemo`.

### Browser viewer

The built viewer is committed at `Sources/TreescopeServer/Resources/viewer.html`, so the Swift
package builds out of the box. To rebuild it after changing anything under `Web/`:

```bash
cd Web
npm install
npm run release        # tsc + vite build → single HTML → embed into TreescopeServer
```

---

## Roadmap

- **Pure-SwiftUI-lifecycle macOS window root:** recover the declaration tree from
  `AppKitWindowHostingView` (empty `Mirror`) — the last reflection gap. (Live `@State`/property
  reading for reflectable hosting views is **done**.)
- Measurement guides, snapshot diffing, multi-window switching.

(USB transport for physical devices is intentionally **not** pursued — the simulator + loopback
covers the primary workflow, and Xcode's own View Hierarchy debugger covers on-device.)

## License

MIT — see [LICENSE](LICENSE). Built from scratch; no code copied from Lookin/LookInside
(LookInside's client is GPL-3.0 and its server is closed source).
