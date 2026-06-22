"""End-to-end tests: every CLI command and every MCP tool against a mock server."""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys

import pytest

from mock_server import MockServer

CLI = [sys.executable, "-m", "treescope_cli"]


def run(port: int, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [*CLI, "--port", str(port), "--timeout", "4000", *args],
        capture_output=True, text=True,
    )


# ── CLI ──────────────────────────────────────────────────────────────────────

def test_status():
    with MockServer() as s:
        r = run(s.port, "status")
        assert r.returncode == 0
        assert "MockApp" in r.stdout
        assert "iOS 18.2" in r.stdout
        assert "liveEditing" in r.stdout


def test_status_json():
    with MockServer() as s:
        r = run(s.port, "--json", "status")
        info = json.loads(r.stdout)
        assert info["device"]["appName"] == "MockApp"
        assert info["protocolVersion"] == 1


def test_tree_and_depth_and_filter():
    with MockServer() as s:
        assert "#obj:4" in run(s.port, "tree").stdout
        assert "depth limit" in run(s.port, "tree", "--depth", "2").stdout
        out = run(s.port, "tree", "--filter", "login").stdout
        assert "LoginButton" in out and "UILabel" not in out


def test_tree_json_round_trips():
    with MockServer() as s:
        snap = json.loads(run(s.port, "--json", "tree").stdout)
        assert snap["roots"][0]["id"] == "obj:1"
        assert len(snap["roots"][0]["children"][0]["children"]) == 3


def test_find_and_json():
    with MockServer() as s:
        out = run(s.port, "find", "Welcome").stdout
        assert "#obj:3" in out and "UIWindow › RootView › UILabel" in out
        arr = json.loads(run(s.port, "--json", "find", "button").stdout)
        assert arr[0]["id"] == "obj:4"


def test_inspect_and_missing():
    with MockServer() as s:
        ok = run(s.port, "inspect", "obj:3")
        assert ok.returncode == 0 and "editable: text" in ok.stdout
        bad = run(s.port, "inspect", "obj:missing")
        assert bad.returncode == 1 and "node not found" in bad.stderr


def test_snapshot_and_window_404(tmp_path):
    with MockServer() as s:
        out = tmp_path / "snap.png"
        assert run(s.port, "snapshot", "obj:3", "-o", str(out)).returncode == 0
        assert out.read_bytes()[:4] == b"\x89PNG"
        win = run(s.port, "snapshot", "obj:1", "-o", str(tmp_path / "no.png"))
        assert win.returncode == 1 and "no rendered snapshot available" in win.stderr


def test_screenshot_falls_back_to_content_view(tmp_path):
    with MockServer() as s:
        out = tmp_path / "screen.png"
        r = run(s.port, "screenshot", "-o", str(out))
        assert r.returncode == 0
        assert "from #obj:2" in r.stdout  # window obj:1 has no snapshot → falls back
        assert out.read_bytes()[:4] == b"\x89PNG"
        res = json.loads(run(s.port, "--json", "shot", "-o", str(out)).stdout)
        assert res["nodeID"] == "obj:2" and res["bytes"] > 0


def test_set_known_and_unknown():
    with MockServer() as s:
        ok = run(s.port, "set", "obj:4", "alpha", "0.5")
        assert ok.returncode == 0 and "OK: set alpha = 0.5" in ok.stdout
        bad = run(s.port, "set", "obj:nope", "alpha", "0.5")
        assert bad.returncode == 1


def test_port_miss_is_clear():
    # Nothing listening on port 1.
    r = subprocess.run([*CLI, "--port", "1", "--timeout", "1500", "status"], capture_output=True, text=True)
    assert r.returncode == 1
    assert "No Treescope server responding" in r.stderr


# ── MCP ──────────────────────────────────────────────────────────────────────

def _mcp_call(port: int, coro_factory):
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    async def body():
        params = StdioServerParameters(
            command=sys.executable,
            args=["-m", "treescope_cli", "--port", str(port), "--timeout", "4000", "mcp"],
        )
        async with stdio_client(params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                return await coro_factory(session)

    return asyncio.run(body())


def _text(result) -> str:
    return "\n".join(c.text for c in result.content if c.type == "text")


def test_mcp_lists_all_tools():
    with MockServer() as s:
        names = _mcp_call(s.port, lambda sess: sess.list_tools())
        got = sorted(t.name for t in names.tools)
        assert got == [
            "treescope_find_nodes",
            "treescope_get_snapshot",
            "treescope_get_tree",
            "treescope_inspect_node",
            "treescope_screenshot",
            "treescope_set_attribute",
            "treescope_status",
        ]


def test_mcp_status_tree_find():
    with MockServer() as s:
        status = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_status", {}))
        assert "MockApp" in _text(status)
        tree = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_get_tree", {"maxDepth": 0}))
        assert "#obj:4" in _text(tree) and "5 nodes total" in _text(tree)
        found = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_find_nodes", {"query": "Welcome"}))
        assert "#obj:3" in _text(found)


def test_mcp_inspect_and_error():
    with MockServer() as s:
        ok = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_inspect_node", {"nodeID": "obj:3"}))
        assert not ok.isError and "editable: text" in _text(ok)
        bad = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_inspect_node", {"nodeID": "obj:missing"}))
        assert bad.isError


def test_mcp_screenshot_and_snapshot_return_png():
    with MockServer() as s:
        shot = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_screenshot", {}))
        assert not shot.isError and "from #obj:2" in _text(shot)
        img = next(c for c in shot.content if c.type == "image")
        assert img.mimeType == "image/png"

        snap = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_get_snapshot", {"nodeID": "obj:3"}))
        png = next(c for c in snap.content if c.type == "image")
        import base64
        assert base64.b64decode(png.data)[:4] == b"\x89PNG"


def test_mcp_set_attribute():
    with MockServer() as s:
        ok = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_set_attribute",
                                                           {"nodeID": "obj:4", "keyPath": "alpha", "value": "0.5"}))
        assert not ok.isError and "OK: set alpha" in _text(ok)
        bad = _mcp_call(s.port, lambda sess: sess.call_tool("treescope_set_attribute",
                                                            {"nodeID": "obj:nope", "keyPath": "alpha", "value": "0.5"}))
        assert bad.isError
