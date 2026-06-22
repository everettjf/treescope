"""Server discovery + connection helpers. Mirrors ``CLI/src/discovery.ts``."""

from __future__ import annotations

import asyncio
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional

from .client import Client
from .protocol import (
    DEFAULT_HIERARCHY_OPTIONS,
    DEFAULT_PORT,
    LOOPBACK_HOST,
    PORT_SCAN_COUNT,
)


@dataclass
class ConnectionOptions:
    host: str = LOOPBACK_HOST
    port: Optional[int] = None  # explicit port; if None, scan
    timeout: float = 8.0        # seconds


async def probe(host: str, port: int, timeout: float) -> bool:
    """True if a Treescope server answers ``"ok"`` on ``/healthz``."""

    def _get() -> bool:
        try:
            with urllib.request.urlopen(f"http://{host}:{port}/healthz", timeout=timeout) as res:
                if res.status != 200:
                    return False
                return res.read().decode("utf-8", "replace").strip() == "ok"
        except Exception:
            return False

    return await asyncio.to_thread(_get)


async def discover_port(opts: ConnectionOptions) -> int:
    if opts.port is not None:
        if await probe(opts.host, opts.port, opts.timeout):
            return opts.port
        raise RuntimeError(
            f"No Treescope server responding at {opts.host}:{opts.port}. "
            "Is the app running with Treescope.start()?"
        )
    ports = [DEFAULT_PORT + i for i in range(PORT_SCAN_COUNT)]
    results = await asyncio.gather(*(probe(opts.host, p, opts.timeout) for p in ports))
    found = sorted(p for p, ok in zip(ports, results) if ok)
    if not found:
        last = DEFAULT_PORT + PORT_SCAN_COUNT - 1
        raise RuntimeError(
            f"No Treescope server found on {opts.host}:{DEFAULT_PORT}-{last}.\n"
            "  - Make sure the app is running with Treescope.start() (DEBUG builds).\n"
            f"  - For a physical device, forward the port over USB: iproxy {DEFAULT_PORT} {DEFAULT_PORT}\n"
            "  - Or pass --port explicitly."
        )
    return found[0]


async def connect(opts: ConnectionOptions) -> tuple[Client, dict]:
    """Discover, connect and handshake. Caller must ``await client.disconnect()``."""
    port = await discover_port(opts)
    client = Client(opts.host, port)
    await client.connect(opts.timeout)
    info = await client.handshake()
    return client, info


async def fetch_hierarchy_snapshot(
    opts: ConnectionOptions,
    hierarchy_options: Optional[dict] = None,
) -> tuple[dict, dict]:
    """Connect, fetch one hierarchy snapshot, disconnect. Returns (info, snapshot)."""
    client, info = await connect(opts)
    try:
        options: dict[str, Any] = {**DEFAULT_HIERARCHY_OPTIONS, **(hierarchy_options or {})}
        snapshot = await client.fetch_hierarchy(options)
        return info, snapshot
    finally:
        await client.disconnect()
