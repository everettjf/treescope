"""Async WebSocket client to the in-app Treescope server.

Correlates responses to requests by envelope ``id`` (server-pushed events use
id 0 and are skipped). Mirrors ``CLI/src/client.ts``.
"""

from __future__ import annotations

import asyncio
import json
import urllib.error
import urllib.request
from typing import Any
from urllib.parse import quote

import websockets

from . import __version__
from .protocol import PROTOCOL_VERSION


class Client:
    def __init__(
        self,
        host: str,
        port: int,
        client_name: str = "Treescope Python CLI",
        client_version: str = __version__,
    ) -> None:
        self.host = host
        self.port = port
        self._client_name = client_name
        self._client_version = client_version
        self._ws: Any = None
        self._next_id = 0

    @property
    def http_base(self) -> str:
        return f"http://{self.host}:{self.port}"

    async def connect(self, timeout: float = 8.0) -> None:
        self._ws = await websockets.connect(
            f"ws://{self.host}:{self.port}/ws", open_timeout=timeout
        )

    async def disconnect(self) -> None:
        if self._ws is not None:
            await self._ws.close()
            self._ws = None

    async def _recv_until(self, message_id: int) -> dict:
        while True:
            raw = await self._ws.recv()
            env = json.loads(raw)
            if env.get("id") == message_id:
                return env["message"]

    async def _request(self, message: dict, timeout: float = 30.0) -> dict:
        if self._ws is None:
            raise RuntimeError("not connected")
        self._next_id += 1
        message_id = self._next_id
        await self._ws.send(json.dumps({"id": message_id, "message": message}))
        try:
            return await asyncio.wait_for(self._recv_until(message_id), timeout)
        except asyncio.TimeoutError as exc:
            raise RuntimeError("request timed out") from exc

    async def handshake(self) -> dict:
        r = await self._request({
            "t": "handshake",
            "client": {
                "name": self._client_name,
                "version": self._client_version,
                "protocolVersion": PROTOCOL_VERSION,
            },
        })
        if r.get("t") == "handshakeAck":
            return r["info"]
        raise RuntimeError(r.get("message") if r.get("t") == "error" else "unexpected handshake response")

    async def fetch_hierarchy(self, options: dict) -> dict:
        r = await self._request({"t": "fetchHierarchy", "options": options})
        if r.get("t") == "hierarchy":
            return r["snapshot"]
        raise RuntimeError(r.get("message") if r.get("t") == "error" else "unexpected hierarchy response")

    async def set_attribute(self, node_id: str, key_path: str, value: dict) -> dict:
        r = await self._request({
            "t": "setAttribute",
            "nodeID": node_id,
            "keyPath": key_path,
            "value": value,
        })
        if r.get("t") == "attributeResult":
            return {"success": r.get("success", False), "message": r.get("message")}
        raise RuntimeError(r.get("message") if r.get("t") == "error" else "unexpected setAttribute response")

    def snapshot_url(self, node_id: str, scale: float = 2) -> str:
        return f"{self.http_base}/snapshot/{quote(node_id, safe='')}?scale={scale}"

    async def fetch_snapshot(self, node_id: str, scale: float = 2) -> bytes:
        url = self.snapshot_url(node_id, scale)

        def _get() -> bytes:
            try:
                with urllib.request.urlopen(url) as res:
                    return res.read()
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    raise RuntimeError(
                        f"no rendered snapshot available for node '{node_id}' "
                        "(it may not be a renderable view/layer — windows and "
                        "value-typed SwiftUI nodes have none)"
                    ) from exc
                raise RuntimeError(f"snapshot request failed (HTTP {exc.code})") from exc

        return await asyncio.to_thread(_get)
