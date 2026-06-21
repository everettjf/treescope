---
name: treescope
description: See and inspect a running iOS/macOS/tvOS app's live UI (UIKit / AppKit / SwiftUI / CALayer) from the terminal. Use when asked to look at the app's screen, debug a layout, find why a view is invisible/misplaced, check a SwiftUI view's state/modifiers, read a view's properties, or live-tweak a property (alpha, hidden, text, color, cornerRadius…) and see the result. Requires the app to be running with the Treescope server embedded (DEBUG).
---

# Treescope — let an agent *see* and inspect a running app's UI

Treescope embeds a tiny loopback HTTP/WebSocket server in a DEBUG build of an iOS/macOS/tvOS
app. This skill drives the `treescope` CLI (a client of that server) so you can **look at the
screen as an image** and inspect/modify the live view hierarchy — UIKit, AppKit, SwiftUI, and
CALayers — without a browser.

## When to use this

- "What does the app look like right now?" / "Show me the screen."
- "Why is this button invisible / off-screen / the wrong size?"
- "What's the SwiftUI view tree / this view's modifiers / its `@State`?"
- "Set this view's alpha to 0.5 / hide it / change its text" and confirm the effect.

## Prerequisite: the app must be running with the server started

The target app must call `Treescope.start()` in a DEBUG build (Simulator, macOS, or a device
with `iproxy 50067 50067`). If nothing is running, the CLI says so — tell the user to launch
the app; don't guess.

## Getting the `treescope` command

Use the first of these that works (check once, reuse it):

1. **On PATH:** `treescope status` (if the user ran `npm link`).
2. **Via npx:** `npx -y treescope-cli status`.
3. **From a local checkout:** `node <repo>/CLI/dist/index.js status`. If `dist/` is missing,
   build it once: `cd <repo>/CLI && npm install && npm run build`.

Below, `treescope` stands for whichever form you resolved.

## The core loop

```
status        →  confirm an app is reachable (device, OS, capabilities)
screenshot    →  SEE the whole screen as a PNG, then read/view that file
tree / find   →  locate the node you care about (get its #id)
inspect <id>  →  read all properties + which are editable (and their keyPath)
set <id> …    →  live-edit a property
screenshot    →  re-capture to confirm the change
```

### 1. See the screen (do this first)

```bash
treescope screenshot -o /tmp/treescope.png      # auto-selects the visible window
```

Then **Read `/tmp/treescope.png`** — you can look at it directly. This is the fastest way to
understand the current UI. Re-run after any change to verify it visually.

### 2. Read the structure (token-efficient)

A full hierarchy can be thousands of nodes. Keep it small:

```bash
treescope tree --depth 3                 # shallow overview
treescope tree --filter Login            # only subtrees matching a substring
treescope tree --visible-only            # drop hidden / zero-size / transparent
treescope --json tree --depth 3          # machine-readable
```

Each line ends with `#obj:…` (or `#sui:…`) — that's the node id for the other commands.

### 3. Find a specific node

```bash
treescope find LoginButton               # by name / class / accessibility label / text
treescope --json find "Welcome back"
```

### 4. Inspect one node

```bash
treescope inspect obj:42                  # geometry + every attribute, grouped
```

Editable attributes are marked `(editable: <keyPath>)` — that keyPath is what `set` takes.

### 5. Live-edit, then re-screenshot

```bash
treescope set obj:42 alpha 0.5            # type inferred (number)
treescope set obj:42 isHidden false       # bool
treescope set obj:42 text "Hello" -t string
treescope screenshot -o /tmp/after.png    # confirm visually
```

Only attributes reported `editable` by `inspect` can be set; the server rejects others.

## Diagnosing "I can't see anything"

- **`No Treescope server found …`** → the app isn't running with `Treescope.start()`, or it's
  on a different port. Ask the user to run it; for a physical device, `iproxy 50067 50067`.
  Pass `--port <n>` if `start()` logged a non-default port (it scans forward from 50067).
- **`screenshot` fails / blank** → the app may be backgrounded, or a pure-SwiftUI-lifecycle
  macOS window root may not render at the window level. Fall back to `tree`, pick a concrete
  view node, and `snapshot <id>` it instead.
- **A node id "not found"** → the hierarchy changed (navigation, re-render). Re-run `tree`/`find`
  to get fresh ids; they are per-capture.

## Conventions

- Prefer `screenshot` to "see", `tree --depth/--filter` to navigate — never dump a full tree.
- Add `--json` whenever you need to parse output programmatically.
- Node ids are valid only for the current capture; re-fetch after the UI changes.

## MCP alternative

If the user prefers tool-calls over shell, the same inspector is available as an MCP server —
register it once and call `treescope_screenshot`, `treescope_get_tree`, `treescope_find_nodes`,
`treescope_inspect_node`, `treescope_get_snapshot`, `treescope_set_attribute`, `treescope_status`:

```bash
claude mcp add treescope -- npx -y treescope-cli mcp
# or: claude mcp add treescope -- node <repo>/CLI/dist/index.js mcp
```
