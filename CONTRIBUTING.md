# Contributing to Treescope

Thanks for your interest! Treescope is an open-source (MIT) runtime view inspector for
SwiftUI + UIKit/AppKit with a browser-based viewer.

## Project layout

```
Sources/
  TreescopeProtocol/   Pure-Foundation wire model + JSON contract (mirrored by Web/src/protocol.ts)
  TreescopeServer/     Debug-only in-app runtime: capture engine + loopback HTTP/WebSocket server
Web/                   The browser viewer (React + TypeScript + Tailwind + shadcn/ui)
Examples/
  TreescopeiOSDemo/    A real iOS app for Simulator end-to-end testing (xcodegen)
Archive/               The superseded native macOS viewer (not built)
```

## Prerequisites

- Xcode 16+ / a recent Swift toolchain (developed against Swift 6.2, swift-tools 5.9).
- Node 18+ for the web viewer.
- Optional: [xcodegen](https://github.com/yonaskolb/XcodeGen) for the iOS example.

## Building & testing

```bash
swift build
swift test            # protocol, SwiftUI reflector, capture, live-state, WebSocket, HTTP e2e

# Web viewer
cd Web && npm install && npm run build

# iOS Simulator example (optional)
cd Examples/TreescopeiOSDemo && ./run.sh
```

The CI workflow (`.github/workflows/ci.yml`) runs `swift build` + `swift test` and the web
`tsc + vite build` on every push and PR — please make sure both are green.

## After changing the web viewer

The built viewer is committed at `Sources/TreescopeServer/Resources/viewer.html` so the Swift
package builds without Node. If you change anything under `Web/`, regenerate and commit it:

```bash
cd Web && npm run release   # tsc + vite build, then embed into the Swift resources
```

## After changing the wire protocol

`Sources/TreescopeProtocol` and `Web/src/protocol.ts` are two ends of the same JSON contract
(discriminated by a `t` field). Change both together, and bump
`ProtocolConstants.protocolVersion` for incompatible changes.

## Conventions

- Match the surrounding code's style; keep comments focused on the non-obvious "why".
- Add or update tests for behavioral changes.
- The embedded server links into other people's apps — keep `TreescopeServer` **dependency-free**
  (Apple frameworks only). Third-party libraries are fine in `Web/` (browser bundle only).
- The server is intended to be **Debug-only**; never make Release builds depend on it.

## Coordinate-space & capture notes

See the docstrings in `Sources/TreescopeServer/Platform/` and `SwiftUI/` — coordinate flipping
(AppKit), CALayer geometry, and SwiftUI `Mirror` reflection have subtle, documented constraints.

## License

By contributing, you agree your contributions are licensed under the MIT License.
