"""``treescope`` command-line client. Mirrors ``CLI/src/index.ts``."""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
from typing import Any

from . import __version__
from . import format as fmt
from .discovery import ConnectionOptions, connect, fetch_hierarchy_snapshot
from .protocol import DEFAULT_PORT, LOOPBACK_HOST, capability_names
from .screenshot import capture_screen


def parse_value(raw: str, vtype: str) -> dict:
    if vtype == "string":
        return {"t": "string", "v": raw}
    if vtype == "bool":
        return {"t": "bool", "v": raw in ("true", "1")}
    if vtype == "integer":
        return {"t": "integer", "v": int(raw)}
    if vtype == "number":
        return {"t": "number", "v": float(raw)}
    # auto
    if raw in ("true", "false"):
        return {"t": "bool", "v": raw == "true"}
    if re.fullmatch(r"-?\d+", raw):
        return {"t": "integer", "v": int(raw)}
    if re.fullmatch(r"-?\d*\.\d+", raw):
        return {"t": "number", "v": float(raw)}
    return {"t": "string", "v": raw}


def _add_global(p: argparse.ArgumentParser, *, suppress: bool) -> None:
    """Add the global connection options, on both the top parser (with real
    defaults) and each subparser (suppressed, so they only override when passed).
    This lets options appear before *or* after the subcommand."""
    s = argparse.SUPPRESS
    p.add_argument("--host", default=(s if suppress else LOOPBACK_HOST), help="server host")
    p.add_argument("-p", "--port", type=int, default=(s if suppress else None),
                   help=f"server port (default: auto-discover from {DEFAULT_PORT})")
    p.add_argument("--timeout", type=int, default=(s if suppress else 8000),
                   help="network timeout in milliseconds")
    p.add_argument("--json", action="store_true", default=(s if suppress else False),
                   help="emit machine-readable JSON instead of formatted text")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="treescope",
        description="Command-line client for the Treescope runtime view inspector.\n"
                    "Inspect a running app's UIKit / AppKit / SwiftUI hierarchy from a shell or a coding agent.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", action="version", version=__version__)
    _add_global(parser, suppress=False)
    sub = parser.add_subparsers(dest="command", metavar="<command>")

    def add_cmd(name: str, help_text: str, **kw) -> argparse.ArgumentParser:
        sp = sub.add_parser(name, help=help_text, description=help_text, **kw)
        _add_global(sp, suppress=True)
        return sp

    add_cmd("status", "Connect and print device info + capabilities")

    sshot = add_cmd("screenshot", "Capture a PNG of the whole current screen (auto-selects the visible window)", aliases=["shot"])
    sshot.add_argument("-s", "--scale", type=float, default=2, help="render scale")
    sshot.add_argument("-o", "--output", default="screenshot.png", help="output file path")

    tree = add_cmd("tree", "Print the view hierarchy as a compact tree")
    tree.add_argument("-d", "--depth", type=int, default=0, help="maximum depth to print (0 = unlimited)")
    tree.add_argument("--visible-only", action="store_true", dest="visible_only", help="hide hidden / zero-size / transparent nodes")
    tree.add_argument("--no-system", action="store_true", dest="hide_system", help="hide system views")
    tree.add_argument("--filter", default=None, help="only show subtrees matching this substring")
    tree.add_argument("--no-swiftui", action="store_true", dest="no_swiftui", help="do not reflect SwiftUI views")
    tree.add_argument("--layers", action="store_true", help="include CALayers")

    insp = add_cmd("inspect", "Show all properties/attributes for a single node")
    insp.add_argument("nodeID")

    find = add_cmd("find", "Search nodes by class name, display name, label, or text content")
    find.add_argument("query")
    find.add_argument("-n", "--limit", type=int, default=50, help="maximum results")

    snap = add_cmd("snapshot", "Save a rendered PNG of a node")
    snap.add_argument("nodeID")
    snap.add_argument("-s", "--scale", type=float, default=2, help="render scale")
    snap.add_argument("-o", "--output", default="snapshot.png", help="output file path")

    setp = add_cmd("set", "Live-edit an editable attribute (e.g. `set <id> alpha 0.5`)")
    setp.add_argument("nodeID")
    setp.add_argument("keyPath")
    setp.add_argument("value")
    setp.add_argument("-t", "--type", choices=["auto", "string", "number", "integer", "bool"], default="auto", help="value type")

    add_cmd("mcp", "Run as a Model Context Protocol (MCP) server over stdio for coding agents")
    return parser


async def _dispatch(args: argparse.Namespace, opts: ConnectionOptions) -> int:
    cmd = args.command
    is_json = getattr(args, "json", False)

    if cmd == "status":
        client, info = await connect(opts)
        await client.disconnect()
        if is_json:
            print(json.dumps(info, indent=2))
            return 0
        print(f"Connected to Treescope server v{info['serverVersion']} "
              f"(protocol {info['protocolVersion']}) at {client.host}:{client.port}\n")
        print(fmt.render_device(info["device"]))
        caps = ", ".join(capability_names(info["capabilities"])) or "none"
        print(f"\nCapabilities: {caps}")
        return 0

    if cmd in ("screenshot", "shot"):
        res = await capture_screen(opts, args.scale)
        with open(args.output, "wb") as f:
            f.write(res["png"])
        if is_json:
            print(json.dumps({"output": args.output, "bytes": len(res["png"]), "nodeID": res["node_id"]}))
        else:
            print(f"Saved {res['device']['appName']} screen ({len(res['png'])} bytes, "
                  f"from #{res['node_id']}) to {args.output}")
        return 0

    if cmd == "tree":
        info, snapshot = await fetch_hierarchy_snapshot(opts, {
            "includeSwiftUI": not args.no_swiftui,
            "includeLayers": args.layers,
            "hideSystemViews": args.hide_system,
        })
        if is_json:
            print(json.dumps(snapshot, indent=2))
            return 0
        flt = {
            "max_depth": args.depth,
            "visible_only": args.visible_only,
            "hide_system": args.hide_system,
            "match": args.filter,
        }
        print(f"{info['device']['appName']} — {fmt.snapshot_summary(snapshot)}\n")
        print(fmt.render_tree(snapshot["roots"], flt))
        return 0

    if cmd == "inspect":
        _info, snapshot = await fetch_hierarchy_snapshot(opts, {"includeLayers": True})
        node = fmt.find_node(snapshot["roots"], args.nodeID)
        if node is None:
            raise RuntimeError(f"node not found: {args.nodeID} (it may have changed; re-run `treescope tree`)")
        if is_json:
            print(json.dumps(node, indent=2))
            return 0
        print(fmt.render_node(node))
        return 0

    if cmd == "find":
        _info, snapshot = await fetch_hierarchy_snapshot(opts, {"includeLayers": True})
        results = fmt.find_nodes(snapshot["roots"], args.query, args.limit)
        if is_json:
            print(json.dumps(results, indent=2))
            return 0
        if not results:
            print(f'No nodes match "{args.query}".')
            return 0
        print(f'{len(results)} match(es) for "{args.query}":\n')
        for r in results:
            label = f'  "{r["label"]}"' if r.get("label") else ""
            print(f'  #{r["id"]}  {r["displayName"]}{label}  [{r["className"]}]')
            print(f'     {r["path"]}')
        return 0

    if cmd == "snapshot":
        client, _info = await connect(opts)
        try:
            png = await client.fetch_snapshot(args.nodeID, args.scale)
            with open(args.output, "wb") as f:
                f.write(png)
            if is_json:
                print(json.dumps({"output": args.output, "bytes": len(png)}))
            else:
                print(f"Saved {len(png)} bytes to {args.output}")
        finally:
            await client.disconnect()
        return 0

    if cmd == "set":
        av = parse_value(args.value, args.type)
        client, _info = await connect(opts)
        try:
            res = await client.set_attribute(args.nodeID, args.keyPath, av)
            if is_json:
                print(json.dumps(res))
            elif res["success"]:
                print(f"OK: set {args.keyPath} = {args.value}")
            else:
                raise RuntimeError(f"server rejected edit: {res.get('message') or 'unknown reason'}")
        finally:
            await client.disconnect()
        return 0

    if cmd == "mcp":
        from .mcp_server import run_mcp_server
        await run_mcp_server(opts)
        return 0

    raise RuntimeError(f"unknown command: {cmd}")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        parser.print_help()
        return 1
    opts = ConnectionOptions(
        host=getattr(args, "host", LOOPBACK_HOST),
        port=getattr(args, "port", None),
        timeout=getattr(args, "timeout", 8000) / 1000,
    )
    try:
        return asyncio.run(_dispatch(args, opts)) or 0
    except Exception as exc:  # noqa: BLE001 — top-level CLI error reporting
        msg = str(exc)
        if getattr(args, "json", False):
            print(json.dumps({"error": msg}), file=sys.stderr)
        else:
            print(f"treescope: {msg}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
