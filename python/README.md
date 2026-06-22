# treescope-cli (Python)

A Python command-line client **and MCP server** for the
[Treescope](https://github.com/everettjf/treescope) runtime view inspector — a sibling of the
[Node CLI](https://github.com/everettjf/treescope/tree/main/CLI), speaking the same loopback
HTTP + WebSocket protocol.

The Treescope runtime embeds a small server inside your app (DEBUG builds). This package lets you
inspect a running app's **UIKit / AppKit / SwiftUI** view hierarchy from a shell, a script, or — the
main motivation — a **coding agent / LLM** that needs to *see* the UI.

```console
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
pip install treescope-cli      # provides the `treescope` command
```

Requires Python 3.10+. Run without installing via `pipx run treescope-cli …` or
`python -m treescope_cli …` from a checkout.

## Prerequisites

The target app must be running with the Treescope server started (DEBUG builds):

```swift
import TreescopeServer
#if DEBUG
Treescope.start()
#endif
```

- **Simulator / macOS**: reachable on `127.0.0.1` directly.
- **Physical iOS device**: forward the port over USB first — `iproxy 50067 50067`.

The port is auto-discovered by scanning `50067…50082`; override with `--port`.

## Commands

| Command | Description |
| --- | --- |
| `treescope status` | Connect and print device info + capabilities |
| `treescope screenshot` | Save a PNG of the **whole current screen** (auto-selects the window; alias `shot`) |
| `treescope tree` | Print the view hierarchy as a compact tree |
| `treescope inspect <nodeID>` | Show all properties for one node |
| `treescope find <query>` | Search nodes by name / class / label / text |
| `treescope snapshot <nodeID>` | Save a rendered PNG of one node |
| `treescope set <nodeID> <keyPath> <value>` | Live-edit an editable attribute |
| `treescope mcp` | Run as an MCP server (stdio) for coding agents |

Global options: `--host`, `-p/--port`, `--timeout <ms>`, `--json` (machine-readable output, on every
command). `--json` works before *or* after the subcommand.

```bash
treescope screenshot -o /tmp/screen.png    # see the whole screen in one call
treescope tree --depth 3 --filter Login     # token-friendly, scoped
treescope find LoginButton
treescope inspect obj:42
treescope set obj:42 alpha 0.5              # value type inferred
treescope --json tree --depth 3             # parseable output for scripts/agents
```

## MCP server mode

`treescope mcp` runs the inspector as a [Model Context Protocol](https://modelcontextprotocol.io)
server over stdio. It exposes `treescope_status`, `treescope_screenshot` (whole-screen PNG inline),
`treescope_get_tree`, `treescope_inspect_node`, `treescope_find_nodes`, `treescope_get_snapshot`,
and `treescope_set_attribute`.

```bash
claude mcp add treescope -- treescope mcp
# or, without installing: claude mcp add treescope -- pipx run treescope-cli mcp
```

## Develop / test

```bash
pip install -e ".[test]"
pytest
```

The suite is self-contained: an aiohttp mock of the Treescope server (`tests/mock_server.py`)
implements the wire protocol, and the tests cover the formatters, every CLI command, and every MCP
tool over a real stdio MCP client.

## Protocol

The wire types mirror the Swift `TreescopeProtocol` module and the Node client; see
[`src/treescope_cli/protocol.py`](src/treescope_cli/protocol.py) and `client.py`.
