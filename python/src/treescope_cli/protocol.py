"""Wire protocol constants + value helpers, mirroring ``Sources/TreescopeProtocol``
(kept in sync with ``CLI/src/protocol.ts`` and ``Web/src/protocol.ts``).

Messages and nodes are passed around as plain ``dict`` objects parsed from JSON;
the discriminator is the ``"t"`` field, matching the server's custom Swift Codable.
"""

from __future__ import annotations

from typing import Any

DEFAULT_PORT = 50067
PORT_SCAN_COUNT = 16
PROTOCOL_VERSION = 1
LOOPBACK_HOST = "127.0.0.1"

DEFAULT_HIERARCHY_OPTIONS: dict[str, Any] = {
    "includeSwiftUI": True,
    "includeLayers": False,
    "hideSystemViews": False,
    "requestSnapshots": False,
    "maxDepth": 0,  # 0 = server default / unlimited
}


class Flag:
    """Bit flags matching ``ViewFlags``."""

    hidden = 1 << 0
    clipsToBounds = 1 << 1
    userInteraction = 1 << 2
    systemView = 1 << 3
    hostsSwiftUI = 1 << 4
    hasSnapshot = 1 << 5
    zeroSize = 1 << 6
    offscreen = 1 << 7


def has_flag(node: dict, flag: int) -> bool:
    return (node.get("flags", 0) & flag) != 0


_CAPABILITIES = [
    ("snapshots", 1 << 0),
    ("liveEditing", 1 << 1),
    ("swiftUI", 1 << 2),
    ("highlighting", 1 << 3),
    ("pushUpdates", 1 << 4),
]


def capability_names(bits: int) -> list[str]:
    return [name for name, bit in _CAPABILITIES if (bits & bit) != 0]


def hex_color(c: dict) -> str:
    def h(v: float) -> str:
        return format(round(max(0.0, min(1.0, v)) * 255), "02x")

    if c.get("alpha", 1) >= 1:
        return f"#{h(c['red'])}{h(c['green'])}{h(c['blue'])}".upper()
    return f"#{h(c['red'])}{h(c['green'])}{h(c['blue'])}{h(c['alpha'])}".upper()


def display_value(v: dict) -> str:
    """Compact display string for an attribute value (mirrors ``displayValue``)."""
    t = v.get("t")
    if t == "string":
        return v["v"]
    if t == "number":
        n = float(v["v"])
        return f"{n:.1f}" if n.is_integer() else f"{n:.6g}"
    if t == "integer":
        return str(v["v"])
    if t == "bool":
        return "true" if v["v"] else "false"
    if t == "enum":
        return v["v"]
    if t == "reference":
        return v["v"]
    if t == "null":
        return "nil"
    if t == "color":
        return hex_color(v["v"])
    if t == "point":
        return f"({v['v']['x']:.1f}, {v['v']['y']:.1f})"
    if t == "size":
        return f"{v['v']['width']:.1f} x {v['v']['height']:.1f}"
    if t == "rect":
        r = v["v"]
        return f"{{{r['x']:.1f}, {r['y']:.1f}, {r['width']:.1f}, {r['height']:.1f}}}"
    if t == "insets":
        i = v["v"]
        return f"({i['top']:.0f}, {i['left']:.0f}, {i['bottom']:.0f}, {i['right']:.0f})"
    if t == "image":
        return f"Image {v['w']}x{v['h']}"
    if t == "nested":
        return f"{{ {len(v['v'])} fields }}"
    return ""
