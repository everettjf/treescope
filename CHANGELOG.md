# Changelog

## Unreleased

- **Pure-SwiftUI window roots fully captured.** A pure-`App`/`WindowGroup` macOS window root
  (`AppKitWindowHostingView`, empty leaf `Mirror`) now yields its real declaration tree, via
  superclass-mirror traversal + descending SwiftUI's `LazyView` thunk wrapper. The last reflection
  gap is closed; all capture is still public-API-only.
- **Interactive exploded 3D canvas.** Drag-to-orbit (X/Y), per-axis angle sliders, layer-depth
  control, ⌥-drag pan, double-click reset, layered snapshots with depth shadows.
- **Web viewer UX overhaul** (React + Tailwind + shadcn/ui): connection overlay with retry,
  ancestor breadcrumbs, a Chart.js node-kind stats popover, full keyboard nav + shortcuts dialog
  (`?`), focus-selected (`F`), search match count + highlight, copy-to-clipboard, persisted layout.
- **GitHub Pages site** (landing + tutorial) at https://everettjf.github.io/treescope/, deployed
  from `docs/` via Actions.
- **Docs:** README badges + website link; CONTRIBUTING layout map; removed dead
  `ViewDebugDataExtractor`.
- **iOS Simulator example** verified end-to-end (120 nodes: UIKit + SwiftUI + CALayer).

## 0.1.0

First tagged release.

- **Browser-based viewer.** The inspected app serves a zero-install web viewer over loopback
  HTTP + WebSocket (`GET /` viewer, `GET /snapshot/{id}` PNG, `GET /ws` JSON protocol). The
  embedded HTTP/1.1 + WebSocket server is built only on `Network.framework` + `CryptoKit` — no
  third-party dependencies in the code you link into your app.
- **SwiftUI inspection** via `Mirror` on the opened existential: unwraps combinators, descends
  custom `body`, extracts `Text`/`Image`/`Color`, modifiers, and property wrappers — **without
  private API** on the primary path.
- **Live values** for reference-typed `@ObservedObject`/`ObservableObject` models (current
  `@Published` fields, tracked across mutation); value-typed `@State` shows its declared value.
- **UIKit + AppKit** capture with typed property sections, snapshots, on-device highlight, and
  live editing of common properties.
- **CALayer** traversal (forced on for SwiftUI hosts to give the canvas real resolved geometry),
  with layer property inspection, live editing, snapshot, and highlight.
- **Viewer UI** (React + Tailwind + shadcn/ui): tree with search/filter/keyboard nav, canvas with
  wireframe + snapshot + exploded-3D + zoom/pan, property inspector with live editing, hover sync.
- **iOS Simulator example** (`Examples/TreescopeiOSDemo`) with a headless WebSocket verifier.

USB physical-device transport is intentionally out of scope (simulator + loopback covers the
primary workflow; Xcode's View Hierarchy covers on-device).
