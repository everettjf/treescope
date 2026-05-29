# Treescope

> An open-source runtime **view inspector** for SwiftUI + UIKit/AppKit.
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
open.

---

## Components

| Module | Role |
|---|---|
| **`TreescopeProtocol`** | Pure-Foundation shared data model + length-prefixed JSON wire protocol. |
| **`TreescopeServer`** | The **debug-only runtime** you embed in your app. Captures UIKit/AppKit/SwiftUI and serves it over a loopback TCP socket. |
| **`TreescopeViewerCore`** | Client connection + observable session model powering the viewer. |
| **`TreescopeApp`** | The native macOS viewer GUI (tree, canvas, inspector, 3D). |
| **`TreescopeDemo`** | A sample SwiftUI app that embeds the server (also runs a built-in self-test). |

Everything is Swift. MIT licensed.

---

## How it works

```
┌─────────────────────────── Your app (Debug build) ───────────────────────────┐
│  TreescopeServer                                                              │
│    • CaptureEngine        walks UIWindow/NSWindow → views → layers            │
│    • SwiftUIReflector     opens `any View`, unwraps ModifiedContent /         │
│                           TupleView / Group / _ConditionalContent, descends   │
│                           custom `body`, reads @State, modifiers, Text…       │
│    • TransportServer      NWListener on 127.0.0.1 (+ Bonjour), framed JSON    │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                     │  loopback TCP (works for the iOS Simulator)
┌────────────────────────────────────▼──────────────────────────────────────────┐
│  TreescopeApp (macOS)                                                          │
│    • TransportClient / InspectorSession   async request/response, snapshots    │
│    • Tree outline · Canvas (snapshot + wireframe + 3D) · Property inspector    │
└────────────────────────────────────────────────────────────────────────────────┘
```

### SwiftUI inspection

Treescope reflects SwiftUI **without** any private API on the primary path:

- Opens the existential `any View` and inspects the concrete type with `Mirror`.
- Structurally unwraps combinators: `ModifiedContent`, `TupleView`, `Group`, `AnyView`,
  `_ConditionalContent`, `Optional`.
- For **your** views (a real `body`), it descends into `body` to recover the declared tree.
- For framework primitives it scans stored properties to find child views and pulls out
  notable values (e.g. a `Text`'s string, a modifier's parameters, `@State` initial values).

A best-effort private `_viewDebugData` / `makeViewDebugData` bridge
(`ViewDebugDataExtractor`) is included for *resolved* SwiftUI geometry; it is fully guarded and
falls back gracefully when the private API is absent on a given OS. Because the server is
**Debug-only**, any private-API use carries no App Store review risk.

> **What you get where:** Directly-created hosting views (`UIHostingController` /
> `NSHostingView` — the common "SwiftUI inside a UIKit/AppKit app" case) yield the full
> **declaration** tree (VStack, Text with content, modifiers, `@State`). Pure SwiftUI-lifecycle
> window roots on macOS are opaque to `Mirror`, so there Treescope captures SwiftUI's *resolved*
> render tree. Full live-property reflection for the latter is the AttributeGraph roadmap item.

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
Treescope.start()      // listens on 127.0.0.1:47761 (scans forward if busy)
#endif
```

CocoaPods users: scope the pod to Debug so it is excluded from Release:

```ruby
pod 'Treescope', :configurations => ['Debug']
```

### 2. Run the viewer

```bash
swift run TreescopeApp
```

Pick a discovered server, or connect manually to `127.0.0.1:47761`.
(For the iOS Simulator, `127.0.0.1` on your Mac reaches the app because the simulator shares the
host network stack. Physical-device support over USB is on the roadmap.)

### Try it end-to-end

```bash
swift run TreescopeDemo     # a sample app that embeds the server
swift run TreescopeApp      # connect to 127.0.0.1:47761
```

---

## Features

- **Unified tree** of UIKit/AppKit views, CALayers (optional) and SwiftUI nodes, colour-coded by framework.
- **Property inspector** with typed rendering: colours, geometry, booleans, enums, nested values.
- **Live editing** of common properties (alpha/opacity, hidden, cornerRadius, background colour, text…).
- **Canvas** with rendered per-view snapshots, frame wireframes, click-to-select, zoom, and an
  **exploded 3D** layer view.
- **On-device highlight** of the selected view.
- **Search & filter**, hide-system-views, auto-expand.
- **Zero-config discovery** via Bonjour, plus manual host/port.

---

## Building & testing

```bash
swift build            # all targets (macOS)
swift test             # 47 tests: protocol, reflector, capture, transport, e2e

# verify the embeddable server compiles for iOS
xcodebuild -scheme TreescopeServer -destination 'generic/platform=iOS Simulator' build
```

The test suite includes a real end-to-end pipeline test (capture a live `NSHostingView`
SwiftUI tree → serialize → transport over loopback TCP → decode in the client) and a built-in
runtime self-probe in the demo app (`TREESCOPE_PROBE=1 swift run TreescopeDemo`).

---

## Roadmap

- **AttributeGraph (Path C):** live `@State`/resolved values for pure-SwiftUI window roots.
- **USB transport** for physical devices (Peertalk-style tunnel).
- CALayer deep inspection, measurement guides, snapshot diffing.

## License

MIT — see [LICENSE](LICENSE). Built from scratch; no code copied from Lookin/LookInside
(LookInside's client is GPL-3.0 and its server is closed source).
