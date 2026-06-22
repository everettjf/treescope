"""A self-contained mock of the in-app Treescope server (HTTP /healthz + /snapshot
and the WebSocket JSON protocol), mirroring ``CLI/test/mock-server.mjs``.

Runs on its own event loop in a background thread so synchronous tests (and CLI
subprocesses) can talk to it. Use as a context manager:

    with MockServer() as server:
        ...  # server.port
"""

from __future__ import annotations

import asyncio
import base64
import json
import threading

from aiohttp import WSMsgType, web

# 1x1 transparent PNG.
PNG_1x1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)

DEVICE = {
    "appName": "MockApp",
    "bundleID": "com.example.MockApp",
    "processName": "MockApp",
    "osName": "iOS",
    "osVersion": "18.2",
    "deviceModel": "iPhone17,1",
    "deviceName": "Mock iPhone",
    "screenSize": {"width": 393, "height": 852},
    "screenScale": 3,
    "isSimulator": True,
}

SERVER_INFO = {
    "device": DEVICE,
    "serverVersion": "0.1.0",
    "protocolVersion": 1,
    # snapshots|liveEditing|swiftUI|highlighting|pushUpdates = 31
    "capabilities": 31,
}


def _node(node_id, display_name, class_name, frame, children=None, **extra):
    return {
        "id": node_id,
        "kind": extra.get("kind", "uiView"),
        "className": class_name,
        "displayName": display_name,
        "label": extra.get("label"),
        "frame": frame,
        "bounds": {"x": 0, "y": 0, "width": frame["width"], "height": frame["height"]},
        "opacity": extra.get("opacity", 1),
        "flags": extra.get("flags", 0),
        "zIndex": 0,
        "transform": None,
        "sections": extra.get("sections", []),
        "snapshotID": node_id if extra.get("snap") else None,
        "children": children or [],
    }


def mock_hierarchy():
    def r(x, y, w, h):
        return {"x": x, "y": y, "width": w, "height": h}

    return [
        _node("obj:1", "UIWindow", "UIWindow", r(0, 0, 393, 852), [
            _node("obj:2", "RootView", "UIView", r(0, 0, 393, 852), [
                _node("obj:3", "UILabel", "UILabel", r(16, 60, 200, 24), [], label="Welcome back", snap=True, sections=[{
                    "id": "text", "title": "Text", "attributes": [
                        {"id": "a1", "title": "text", "value": {"t": "string", "v": "Welcome back"}, "editable": True, "keyPath": "text"},
                        {"id": "a2", "title": "textColor", "value": {"t": "color", "v": {"red": 0, "green": 0, "blue": 0, "alpha": 1}}, "editable": True, "keyPath": "textColor"},
                        {"id": "a3", "title": "numberOfLines", "value": {"t": "integer", "v": 1}, "editable": False, "keyPath": None},
                    ],
                }]),
                _node("obj:4", "LoginButton", "UIButton", r(16, 200, 358, 48), [], label="Log In", opacity=0.5, flags=1, snap=True, sections=[{
                    "id": "layout", "title": "Layout", "attributes": [
                        {"id": "b1", "title": "alpha", "value": {"t": "number", "v": 0.5}, "editable": True, "keyPath": "alpha"},
                        {"id": "b2", "title": "isHidden", "value": {"t": "bool", "v": True}, "editable": True, "keyPath": "isHidden"},
                    ],
                }]),
                _node("obj:5", "UIImageView", "UIImageView", r(0, 0, 0, 0), [], flags=64),
            ]),
        ]),
    ]


# Renderable views (full-screen RootView obj:2, plus obj:3/obj:4) return a PNG;
# others — notably the window obj:1 — 404, like the real server. A screenshot
# capture therefore falls back from the window to its content view.
_RENDERABLE = {"obj:2", "obj:3", "obj:4"}


def _build_app() -> web.Application:
    async def healthz(_request):
        return web.Response(text="ok")

    async def snapshot(request):
        node_id = request.match_info["id"]
        if node_id in _RENDERABLE:
            return web.Response(body=PNG_1x1, content_type="image/png")
        return web.Response(status=404, text="not found")

    async def ws_handler(request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        async for msg in ws:
            if msg.type != WSMsgType.TEXT:
                continue
            env = json.loads(msg.data)
            m = env.get("message") or {}

            async def reply(message):
                await ws.send_str(json.dumps({"id": env["id"], "message": message}))

            t = m.get("t")
            if t == "handshake":
                await reply({"t": "handshakeAck", "info": SERVER_INFO})
            elif t == "fetchHierarchy":
                await reply({"t": "hierarchy", "snapshot": {
                    "device": DEVICE, "roots": mock_hierarchy(), "timestamp": 1, "serverVersion": "0.1.0",
                }})
            elif t == "setAttribute":
                known = m.get("nodeID") in {"obj:1", "obj:2", "obj:3", "obj:4", "obj:5"}
                await reply({"t": "attributeResult", "nodeID": m.get("nodeID"), "keyPath": m.get("keyPath"),
                             "success": known, "message": None if known else "unknown node"})
            elif t == "ping":
                await reply({"t": "pong"})
            elif t == "highlight":
                pass
            else:
                await reply({"t": "error", "code": 1, "message": f"unsupported message: {t}"})
        return ws

    app = web.Application()
    app.add_routes([
        web.get("/healthz", healthz),
        web.get("/snapshot/{id}", snapshot),
        web.get("/ws", ws_handler),
    ])
    return app


class MockServer:
    def __init__(self) -> None:
        self.port: int = 0
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._runner: web.AppRunner | None = None
        self._ready = threading.Event()

    def __enter__(self) -> "MockServer":
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        if not self._ready.wait(timeout=10):
            raise RuntimeError("mock server failed to start")
        return self

    def __exit__(self, *exc) -> None:
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread is not None:
            self._thread.join(timeout=10)

    def _run(self) -> None:
        loop = asyncio.new_event_loop()
        self._loop = loop
        asyncio.set_event_loop(loop)
        runner = web.AppRunner(_build_app())
        self._runner = runner
        loop.run_until_complete(runner.setup())
        site = web.TCPSite(runner, "127.0.0.1", 0)
        loop.run_until_complete(site.start())
        self.port = site._server.sockets[0].getsockname()[1]  # type: ignore[attr-defined]
        self._ready.set()
        try:
            loop.run_forever()
        finally:
            loop.run_until_complete(runner.cleanup())
            loop.close()
