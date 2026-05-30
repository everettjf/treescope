# Treescope CLI

A command-line client for the [Treescope](../README.md) runtime view inspector.

The Treescope runtime embeds a small loopback HTTP + WebSocket server inside your
app (DEBUG builds). The browser viewer is one client of that server; this CLI is
another. It lets you inspect a running app's **UIKit / AppKit / SwiftUI** view
hierarchy from a shell, a script, or — the main motivation — a **coding agent /
LLM** that needs to "see" the UI.

```
$ treescope status
Connected to Treescope server v0.1.0 (protocol 1) at 127.0.0.1:50067

App:     MyApp (com.example.MyApp)
OS:      iOS 18.2
Device:  iPhone 16 Pro — iPhone17,1 (Simulator)
Screen:  393 x 852 @3x

Capabilities: snapshots, liveEditing, swiftUI, highlighting, pushUpdates
```

## Install

```bash
cd CLI
npm install
npm run build
npm link        # optional: puts `treescope` on your PATH
```

Requires Node 18+. Without `npm link`, run via `node dist/index.js …`.

## Prerequisites

Your app must be running with the Treescope server started (DEBUG builds):

```swift
import TreescopeServer
#if DEBUG
Treescope.start()
#endif
```

- **Simulator / macOS**: the server is reachable on `127.0.0.1` directly.
- **Physical iOS device**: forward the port over USB first:
  ```bash
  iproxy 50067 50067   # from libimobiledevice
  ```

The CLI auto-discovers the port by scanning `50067…50082`; override with `--port`.

## Commands

| Command | Description |
| --- | --- |
| `treescope status` | Connect and print device info + capabilities |
| `treescope tree` | Print the view hierarchy as a compact tree |
| `treescope inspect <nodeID>` | Show all properties for one node |
| `treescope find <query>` | Search nodes by name / class / label / text |
| `treescope snapshot <nodeID>` | Save a rendered PNG of a node |
| `treescope set <nodeID> <keyPath> <value>` | Live-edit an editable attribute |
| `treescope mcp` | Run as an MCP server (stdio) for coding agents — see [below](#mcp-server-mode) |

### Global options

```
--host <host>     server host (default 127.0.0.1)
-p, --port <n>    server port (default: auto-discover from 50067)
--timeout <ms>    network timeout (default 8000)
--json            emit machine-readable JSON instead of formatted text
```

### `tree`

```bash
treescope tree                      # full hierarchy
treescope tree --depth 4            # limit depth (token-friendly)
treescope tree --visible-only       # hide hidden / zero-size / transparent
treescope tree --filter LoginButton # only subtrees matching a substring
treescope tree --no-swiftui         # skip SwiftUI reflection
treescope tree --json               # raw HierarchySnapshot JSON
```

Output is one compact line per node:

```
UIWindow  ·  #obj:1  (0, 0, 390, 844)
└─ UIView  ContainerView  ·  #obj:2  (0, 0, 390, 844)
   ├─ UILabel  "Welcome back"  ·  #obj:3  (16, 60, 200, 24)
   └─ UIButton  "Log In"  LoginButton  ·  #obj:4  (16, 200, 358, 48)  hidden α0.50
```

`#obj:…` is the node ID — pass it to `inspect`, `snapshot`, or `set`.

### `inspect`

```bash
treescope inspect obj:3
treescope inspect obj:3 --json
```

Prints geometry plus every captured attribute, grouped by section, marking which
ones are live-editable and their key path.

### `find`

```bash
treescope find Button
treescope find "Welcome back" --limit 20 --json
```

Matches display name, class name, accessibility label, and string/enum attribute
values (e.g. label text). Returns node IDs and their path from the root.

### `snapshot`

```bash
treescope snapshot obj:4 -o button.png --scale 2
```

### `set`

```bash
treescope set obj:4 alpha 0.5      # number inferred
treescope set obj:4 isHidden true  # bool inferred
treescope set obj:3 text "Hi" -t string
```

Only attributes reported as `editable` by `inspect` can be set. Value type is
inferred (`bool` / `integer` / `number` / `string`); override with `--type`.

## Using it from a coding agent

The CLI is designed to be driven by an LLM/agent:

- `--json` on every command yields stable, parseable output.
- `tree --depth N` and `tree --filter …` keep responses small enough for a
  context window instead of dumping a 20k-node hierarchy.
- `find` lets the agent locate a node by what it knows (a label, a class) before
  drilling in with `inspect`.
- `snapshot` produces a PNG a multimodal model can look at.

A typical agent loop: `status` → `tree --depth 3` → `find <thing>` →
`inspect <id>` → optionally `snapshot <id>` or `set <id> …`.

## MCP server mode

`treescope mcp` runs the inspector as a [Model Context Protocol](https://modelcontextprotocol.io)
server over stdio, so agents like Claude Code can call it as tools — no shell
parsing required. It exposes:

| Tool | Purpose |
| --- | --- |
| `treescope_status` | Device info + capabilities |
| `treescope_get_tree` | Compact hierarchy (`maxDepth`, `visibleOnly`, `hideSystem`, `filter`, `includeSwiftUI`, `includeLayers`) |
| `treescope_inspect_node` | All properties for one node |
| `treescope_find_nodes` | Search by name / class / label / text |
| `treescope_get_snapshot` | Rendered PNG returned as inline image content (multimodal) |
| `treescope_set_attribute` | Live-edit an editable attribute |

Outputs are token-efficient: `treescope_get_tree` defaults to `maxDepth: 4` and
supports a `filter`, so an agent drills down with `find` / `inspect` rather than
pulling a whole hierarchy at once.

### Register with Claude Code

```bash
claude mcp add treescope -- node /absolute/path/to/treescope/CLI/dist/index.js mcp
```

Or in an MCP client config (`claude_desktop_config.json`, etc.):

```json
{
  "mcpServers": {
    "treescope": {
      "command": "node",
      "args": ["/absolute/path/to/treescope/CLI/dist/index.js", "mcp"]
    }
  }
}
```

The server auto-discovers the app's port (50067…50082). To pin host/port, add
them before `mcp`: `"args": [".../dist/index.js", "--port", "50067", "mcp"]`.

## Testing

```bash
npm test     # builds, then runs node --test
```

The suite is self-contained: a mock Treescope server (`test/mock-server.mjs`)
implements the wire protocol, and the tests exercise the formatters
(`format.test.mjs`), every CLI command (`cli.test.mjs`), and every MCP tool via a
real MCP client over stdio (`mcp.test.mjs`).

## Roadmap

- `--watch` mode subscribing to `hierarchyChanged` push events.
- Bonjour-based discovery in addition to the loopback port scan.

## Protocol

The wire types in [`src/protocol.ts`](src/protocol.ts) mirror the Swift
`TreescopeProtocol` module and the browser viewer's `Web/src/protocol.ts`. The
client (`src/client.ts`) is a Node port of `Web/src/client.ts`, correlating
responses to requests by envelope `id` over the same WebSocket protocol.
