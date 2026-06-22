# Changelog

## Unreleased

- **Python client published to PyPI** as [`treescope-cli`](https://pypi.org/project/treescope-cli/).
  A full Python port of the CLI and MCP server speaking the same loopback protocol — `treescope
  status / screenshot / tree / inspect / find / snapshot / set` and `treescope mcp` (7 tools,
  inline-PNG screenshot). Async `websockets` client; the MCP server uses the official `mcp` SDK.
  Self-contained test suite (aiohttp mock server) covering the formatters, every CLI command, and
  every MCP tool over a real stdio MCP client — 29 tests. Install with `pip install treescope-cli`;
  register with `claude mcp add treescope -- treescope mcp`.

## 0.2.0 — 2026-06-21

- **`treescope screenshot` (alias `shot`).** Capture a PNG of the *whole current screen* in one
  command — it auto-selects the visible window and falls back to its content view (so it works on
  iOS where a `UIWindow` renders directly and on macOS where the `NSWindow` root does not). This is
  the fastest way for a coding agent to **see** the UI without first walking the tree for a node id.
- **MCP `treescope_screenshot` tool.** The same whole-screen capture as an inline PNG, so a
  multimodal agent can look at the screen directly; the server instructions now steer agents to call
  it first. Added to the MCP test suite.
- **Treescope Skill (`.claude/skills/treescope/`).** A Claude Code skill that teaches an agent the
  inspect loop (`status → screenshot → tree/find → inspect → set → re-screenshot`), how to resolve
  the `treescope` command (`npx treescope-cli` / local build), and how to diagnose "app not running
  / wrong port". Copy it into your own project's `.claude/skills/` to give agents UI sight there too.
- **CLI published to npm** as [`treescope-cli`](https://www.npmjs.com/package/treescope-cli).
  Completed the `package.json` publish metadata (`repository` with the `CLI` subdirectory,
  `homepage`, `bugs`, `author`) and ship `LICENSE` in the package, so the CLI and MCP server install
  with `npx -y treescope-cli` / `npm i -g treescope-cli` — no local build.

## 0.1.1 — 2026-05-30

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
