# Changelog

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

Known gap: a pure-SwiftUI-lifecycle macOS window root (`AppKitWindowHostingView`) has an empty
`Mirror`, so its declaration tree isn't reachable there. USB physical-device transport is
intentionally out of scope.
