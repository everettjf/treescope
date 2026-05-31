# Changelog

## Unreleased

- **Fix: live-editing numeric properties with whole numbers.** Setting a `Double`-backed property
  (`alpha`/`alphaValue`, `opacity`, `cornerRadius`, `borderWidth`) to a whole number such as `12`
  was rejected, because the value arrived as `.integer` while the handlers matched only `.number`.
  Integer values are now coerced to numbers across the UIKit/AppKit/CALayer live-edit handlers, and
  the rejection message no longer misreports a supported key path as "unsupported"
  ([#4](https://github.com/everettjf/treescope/issues/4)).
- **CLI: clearer snapshot error** when a node has no rendered snapshot (e.g. a window), instead of a
  bare `HTTP 404`. Tree connectors (`├─`/`└─`) now reflect the *rendered* siblings under
  `--filter` / `--visible-only` rather than the raw children.
- **Command-line client (`CLI/`).** A Node/TypeScript `treescope` CLI that speaks the same
  loopback protocol as the browser viewer, for inspecting a running app from a shell or a script:
  `status`, `tree` (with `--depth`/`--visible-only`/`--filter`), `inspect`, `find`, `snapshot`, and
  `set` (live edit). Auto-discovers the server port; `--json` on every command for scripting.
- **MCP server mode (`treescope mcp`).** Runs the inspector as a
  [Model Context Protocol](https://modelcontextprotocol.io) server over stdio so coding agents
  (e.g. Claude Code) can call it as tools — `treescope_status`, `treescope_get_tree`,
  `treescope_inspect_node`, `treescope_find_nodes`, `treescope_get_snapshot` (inline PNG), and
  `treescope_set_attribute`. Outputs are token-efficient (small default depth + filter).
- **Tests.** A self-contained CLI test suite (mock server + a real MCP client over stdio) covering
  the formatters, every CLI command, and every MCP tool. Verified end-to-end against the running
  iOS/macOS demos.

## 0.1.0 — 2026-05-29

First release. An open alternative to Lookin, with first-class SwiftUI inspection.

- **Browser-based view inspector.** The inspected app serves a zero-install web viewer over
  loopback HTTP + WebSocket (`GET /` viewer, `GET /snapshot/{id}` PNG, `GET /ws` JSON protocol).
  The embedded HTTP/1.1 + WebSocket server is built only on `Network.framework` + `CryptoKit` — no
  third-party dependencies enter your app, and it is intended to be Debug-only.
- **Unified hierarchy** of UIKit/AppKit views, SwiftUI nodes, and CALayers in one tree, colour-coded
  by framework, with search/filter, hide-system-views, and full keyboard navigation.
- **Open SwiftUI inspection** via `Mirror` on the opened `any View`: unwraps combinators, descends
  custom `body`, extracts Text/Image/Color, modifiers, and `@State` — using only public reflection.
  Reference-typed observable state is surfaced live.
- **Interactive canvas.** Wireframe + rendered snapshots and an exploded 3D layer view (on by
  default) with drag-to-orbit and angle/depth controls. Figma-style navigation: two-finger swipe /
  scroll to pan in any direction, trackpad pinch or ⌘-scroll to zoom toward the cursor, drag
  anywhere to pan, tap to select. Floating zoom / angle / reset controls.
- **Property inspector** with typed sections, live editing of common view and layer properties,
  on-device highlight, and hover sync with the tree.
- **Default port `50067`** (scans forward on conflict; override via `Treescope.start(preferredPort:)`).
- **Examples.** Package-adopting iOS Simulator and macOS apps under `Examples/`, each with a
  `./run.sh` and a headless WebSocket verifier.
- **One-click release** via `deploy.sh`, and a GitHub Pages site at
  https://everettjf.github.io/treescope/.
