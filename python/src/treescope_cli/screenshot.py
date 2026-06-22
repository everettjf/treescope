"""Whole-screen capture. Mirrors ``CLI/src/screenshot.ts``."""

from __future__ import annotations

from typing import Any

from .discovery import ConnectionOptions, connect
from .protocol import DEFAULT_HIERARCHY_OPTIONS, Flag


def _area(r: dict) -> float:
    return max(0.0, r.get("width", 0)) * max(0.0, r.get("height", 0))


def _renderable(node: dict) -> bool:
    return (
        (node.get("flags", 0) & (Flag.hidden | Flag.zeroSize)) == 0
        and node.get("opacity", 1) > 0.001
        and _area(node.get("frame", {})) > 0
    )


def pick_screenshot_nodes(roots: list[dict]) -> list[str]:
    """Ordered node ids to try when capturing the whole screen.

    Prefers the largest visible root window, then its largest first-level
    children as a fallback — a UIWindow renders directly on iOS, whereas an
    NSWindow root is not itself a view, so its contentView (a child) renders on
    macOS.
    """
    ids: list[str] = []
    sorted_roots = sorted((r for r in roots if _renderable(r)), key=_area_of_frame, reverse=True)
    for root in sorted_roots:
        ids.append(root["id"])
        kids = sorted((c for c in root.get("children", []) if _renderable(c)), key=_area_of_frame, reverse=True)
        for kid in kids[:3]:
            ids.append(kid["id"])
    # de-duplicate, preserving order
    seen: set[str] = set()
    out: list[str] = []
    for i in ids:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out


def _area_of_frame(node: dict) -> float:
    return _area(node.get("frame", {}))


async def capture_screen(opts: ConnectionOptions, scale: float) -> dict[str, Any]:
    """Capture a PNG of the current screen in one round-trip.

    Returns ``{"png": bytes, "node_id": str, "device": dict}``.
    """
    client, info = await connect(opts)
    try:
        snapshot = await client.fetch_hierarchy({
            **DEFAULT_HIERARCHY_OPTIONS,
            "includeSwiftUI": False,
            "includeLayers": False,
        })
        candidates = pick_screenshot_nodes(snapshot.get("roots", []))
        if not candidates:
            raise RuntimeError("no visible on-screen window to capture (is the app foregrounded?)")
        last_err: Exception | None = None
        for node_id in candidates:
            try:
                png = await client.fetch_snapshot(node_id, scale)
                return {"png": png, "node_id": node_id, "device": info["device"]}
            except Exception as exc:
                last_err = exc
        raise RuntimeError(
            f"could not capture the screen (tried {len(candidates)} root node(s)): {last_err}"
        )
    finally:
        await client.disconnect()
