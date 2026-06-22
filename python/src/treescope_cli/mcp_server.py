"""MCP server exposing the Treescope inspector as tools. Mirrors ``CLI/src/mcp.ts``.

Each tool connects to the in-app server fresh, fetches what it needs, and
disconnects — robust against the app restarting.
"""

from __future__ import annotations

import base64
from typing import Any

import mcp.types as types
from mcp.server import Server
from mcp.server.stdio import stdio_server

from . import __version__, format as fmt
from .cli import parse_value
from .discovery import ConnectionOptions, connect, fetch_hierarchy_snapshot
from .protocol import capability_names
from .screenshot import capture_screen

INSTRUCTIONS = (
    "Inspect a running app's UIKit/AppKit/SwiftUI view hierarchy via Treescope. "
    "To SEE the UI, call treescope_screenshot first — it returns a PNG of the whole "
    "current screen so you can look at it directly. Typical flow: treescope_status to "
    "confirm connectivity, treescope_screenshot to view the screen, treescope_get_tree "
    "(use a small maxDepth or a filter to stay token-efficient) for structure, "
    "treescope_find_nodes to locate something by name/label/text, then "
    "treescope_inspect_node for one node's full properties. treescope_get_snapshot "
    "renders one node; treescope_set_attribute live-edits an editable property (re-run "
    "treescope_screenshot afterwards to confirm the change)."
)

Content = list[types.TextContent | types.ImageContent]


def _text(s: str) -> Content:
    return [types.TextContent(type="text", text=s)]


def _tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="treescope_status",
            description="Connect to the running app and report device info (app, OS, device, "
                        "screen) and server capabilities. Use first to confirm an app is reachable.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="treescope_screenshot",
            description="Render the entire current screen to a PNG and return it inline, so you "
                        "can SEE the app's UI directly. Auto-selects the visible window — no node "
                        "id needed. Use this first to look at the screen, then treescope_get_tree / "
                        "treescope_find_nodes to drill in.",
            inputSchema={
                "type": "object",
                "properties": {
                    "scale": {"type": "number", "minimum": 0.5, "maximum": 4, "default": 2,
                              "description": "Render scale. Default 2."},
                },
            },
        ),
        types.Tool(
            name="treescope_get_tree",
            description="Fetch the view hierarchy as a compact one-line-per-node tree. Each line "
                        "includes the node id (#...) to pass to other tools. Keep maxDepth small "
                        "(default 4) or use a filter to avoid flooding context.",
            inputSchema={
                "type": "object",
                "properties": {
                    "maxDepth": {"type": "integer", "minimum": 0, "default": 4,
                                 "description": "Maximum depth to print; 0 = unlimited. Default 4."},
                    "visibleOnly": {"type": "boolean", "default": False,
                                    "description": "Hide hidden / zero-size / fully transparent nodes."},
                    "hideSystem": {"type": "boolean", "default": False,
                                   "description": "Hide system views (status bar, keyboard internals, etc.)."},
                    "filter": {"type": "string",
                               "description": "Only show subtrees whose name/class/label contains this substring."},
                    "includeSwiftUI": {"type": "boolean", "default": True, "description": "Reflect SwiftUI views."},
                    "includeLayers": {"type": "boolean", "default": False, "description": "Include CALayers."},
                },
            },
        ),
        types.Tool(
            name="treescope_inspect_node",
            description="Show all captured properties for one node (geometry plus every attribute "
                        "section, marking which are live-editable and their key path). Pass a node "
                        "id from treescope_get_tree.",
            inputSchema={
                "type": "object",
                "properties": {"nodeID": {"type": "string", "description": "Node id, e.g. 'obj:1234' or 'sui:...'."}},
                "required": ["nodeID"],
            },
        ),
        types.Tool(
            name="treescope_find_nodes",
            description="Search the hierarchy for nodes by display name, class name, accessibility "
                        "label, or string/enum attribute values (e.g. a label's text). Returns "
                        "matching node ids and their path.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Case-insensitive substring to search for."},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 500, "default": 25,
                              "description": "Max results. Default 25."},
                },
                "required": ["query"],
            },
        ),
        types.Tool(
            name="treescope_get_snapshot",
            description="Render a node to a PNG image and return it inline, so a multimodal model "
                        "can look at it. Pass a node id from treescope_get_tree.",
            inputSchema={
                "type": "object",
                "properties": {
                    "nodeID": {"type": "string", "description": "Node id to render."},
                    "scale": {"type": "number", "minimum": 0.5, "maximum": 4, "default": 2,
                              "description": "Render scale. Default 2."},
                },
                "required": ["nodeID"],
            },
        ),
        types.Tool(
            name="treescope_set_attribute",
            description="Live-edit an editable attribute on a node (e.g. alpha, isHidden, text). "
                        "Only attributes reported as editable by treescope_inspect_node can be set. "
                        "Use the key path shown there.",
            inputSchema={
                "type": "object",
                "properties": {
                    "nodeID": {"type": "string", "description": "Target node id."},
                    "keyPath": {"type": "string", "description": "Attribute key path, e.g. 'alpha' or 'isHidden'."},
                    "value": {"type": "string", "description": "New value as a string; type inferred unless valueType set."},
                    "valueType": {"type": "string", "enum": ["auto", "string", "number", "integer", "bool"],
                                  "default": "auto", "description": "Force a value type. Default 'auto'."},
                },
                "required": ["nodeID", "keyPath", "value"],
            },
        ),
    ]


def build_server(opts: ConnectionOptions) -> Server:
    server: Server = Server("treescope", version=__version__, instructions=INSTRUCTIONS)

    @server.list_tools()
    async def list_tools() -> list[types.Tool]:
        return _tools()

    @server.call_tool()
    async def call_tool(name: str, arguments: dict[str, Any]) -> Content:
        args = arguments or {}

        if name == "treescope_status":
            client, info = await connect(opts)
            await client.disconnect()
            caps = ", ".join(capability_names(info["capabilities"])) or "none"
            return _text(
                f"Connected to Treescope server v{info['serverVersion']} "
                f"(protocol {info['protocolVersion']}) at {client.host}:{client.port}\n\n"
                f"{fmt.render_device(info['device'])}\n\nCapabilities: {caps}"
            )

        if name == "treescope_screenshot":
            res = await capture_screen(opts, args.get("scale", 2))
            png = res["png"]
            return [
                types.TextContent(
                    type="text",
                    text=f"{res['device']['appName']} screen ({len(png)} bytes, "
                         f"scale {args.get('scale', 2)}, rendered from #{res['node_id']}).",
                ),
                types.ImageContent(type="image", data=base64.b64encode(png).decode("ascii"), mimeType="image/png"),
            ]

        if name == "treescope_get_tree":
            info, snapshot = await fetch_hierarchy_snapshot(opts, {
                "includeSwiftUI": args.get("includeSwiftUI", True),
                "includeLayers": args.get("includeLayers", False),
                "hideSystemViews": args.get("hideSystem", False),
            })
            flt = {
                "max_depth": args.get("maxDepth", 4),
                "visible_only": args.get("visibleOnly", False),
                "hide_system": args.get("hideSystem", False),
                "match": args.get("filter"),
            }
            body = fmt.render_tree(snapshot["roots"], flt) or "(no nodes matched)"
            return _text(f"{info['device']['appName']} — {fmt.snapshot_summary(snapshot)}\n\n{body}")

        if name == "treescope_inspect_node":
            _info, snapshot = await fetch_hierarchy_snapshot(opts, {"includeLayers": True})
            node = fmt.find_node(snapshot["roots"], args["nodeID"])
            if node is None:
                raise RuntimeError(f"node not found: {args['nodeID']} (it may have changed; re-run treescope_get_tree)")
            return _text(fmt.render_node(node))

        if name == "treescope_find_nodes":
            _info, snapshot = await fetch_hierarchy_snapshot(opts, {"includeLayers": True})
            results = fmt.find_nodes(snapshot["roots"], args["query"], args.get("limit", 25))
            if not results:
                return _text(f'No nodes match "{args["query"]}".')
            lines = []
            for r in results:
                label = f'  "{r["label"]}"' if r.get("label") else ""
                lines.append(f'#{r["id"]}  {r["displayName"]}{label}  [{r["className"]}]\n   {r["path"]}')
            return _text(f'{len(results)} match(es) for "{args["query"]}":\n\n' + "\n".join(lines))

        if name == "treescope_get_snapshot":
            client, _info = await connect(opts)
            try:
                png = await client.fetch_snapshot(args["nodeID"], args.get("scale", 2))
            finally:
                await client.disconnect()
            return [
                types.TextContent(type="text",
                                  text=f"Rendered {args['nodeID']} ({len(png)} bytes, scale {args.get('scale', 2)})."),
                types.ImageContent(type="image", data=base64.b64encode(png).decode("ascii"), mimeType="image/png"),
            ]

        if name == "treescope_set_attribute":
            av = parse_value(args["value"], args.get("valueType", "auto"))
            client, _info = await connect(opts)
            try:
                res = await client.set_attribute(args["nodeID"], args["keyPath"], av)
            finally:
                await client.disconnect()
            if res["success"]:
                return _text(f"OK: set {args['keyPath']} = {args['value']} on {args['nodeID']}")
            raise RuntimeError(f"server rejected edit: {res.get('message') or 'unknown reason'}")

        raise RuntimeError(f"unknown tool: {name}")

    return server


async def run_mcp_server(opts: ConnectionOptions) -> None:
    server = build_server(opts)
    async with stdio_server() as (read_stream, write_stream):
        init_options = server.create_initialization_options()
        await server.run(read_stream, write_stream, init_options)
