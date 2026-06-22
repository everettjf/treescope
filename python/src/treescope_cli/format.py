"""Pretty-printing of trees, nodes, search results. Mirrors ``CLI/src/format.ts``."""

from __future__ import annotations

from typing import Any, Optional

from .protocol import Flag, display_value


def _num(v: Any) -> str:
    if isinstance(v, (int, float)) and float(v).is_integer():
        return str(int(v))
    return str(v)


def _rect_str(r: dict) -> str:
    def n(v: float) -> str:
        return str(int(v)) if float(v).is_integer() else f"{v:.1f}"

    return f"({n(r['x'])}, {n(r['y'])}, {n(r['width'])}, {n(r['height'])})"


def _flag_str(node: dict) -> str:
    parts: list[str] = []
    f = node.get("flags", 0)
    if f & Flag.hidden:
        parts.append("hidden")
    if f & Flag.zeroSize:
        parts.append("zero")
    if f & Flag.offscreen:
        parts.append("offscreen")
    if f & Flag.hostsSwiftUI:
        parts.append("hostsSwiftUI")
    if f & Flag.systemView:
        parts.append("system")
    if node.get("opacity", 1) < 0.999:
        parts.append(f"α{node['opacity']:.2f}")
    return " ".join(parts)


def _is_visible(node: dict) -> bool:
    return (node.get("flags", 0) & (Flag.hidden | Flag.zeroSize)) == 0 and node.get("opacity", 1) > 0.001


def _truncate(s: str, n: int) -> str:
    return s[: n - 1] + "…" if len(s) > n else s


def _node_matches(node: dict, needle: str) -> bool:
    hay = f"{node['displayName']}\n{node['className']}\n{node.get('label') or ''}".lower()
    return needle in hay


def _subtree_matches(node: dict, needle: str) -> bool:
    if _node_matches(node, needle):
        return True
    return any(_subtree_matches(c, needle) for c in node.get("children", []))


def render_tree(roots: list[dict], flt: dict) -> str:
    """One compact line per node. ``flt`` keys: max_depth, visible_only, hide_system, match."""
    lines: list[str] = []
    needle = (flt.get("match") or "").lower() or None
    max_depth = flt.get("max_depth", 0)

    def should_render(node: dict) -> bool:
        if flt.get("visible_only") and not _is_visible(node):
            return False
        if flt.get("hide_system") and (node.get("flags", 0) & Flag.systemView):
            return False
        if needle and not _subtree_matches(node, needle):
            return False
        return True

    def walk(node: dict, depth: int, prefix: str, is_last: bool) -> None:
        branch = "" if depth == 0 else ("└─ " if is_last else "├─ ")
        flags = _flag_str(node)
        label = f'  "{_truncate(node["label"], 40)}"' if node.get("label") else ""
        cls = f'  {node["className"]}' if node["className"] != node["displayName"] else ""
        meta = "  ".join(x for x in [f'#{node["id"]}', _rect_str(node["frame"]), flags] if x)
        lines.append(f'{prefix}{branch}{node["displayName"]}{label}{cls}  ·  {meta}')

        child_prefix = prefix + ("" if depth == 0 else ("   " if is_last else "│  "))
        kids = [c for c in node.get("children", []) if should_render(c)]

        if max_depth > 0 and depth + 1 >= max_depth:
            if kids:
                plural = "" if len(kids) == 1 else "ren"
                lines.append(f"{child_prefix}└─ … {len(kids)} child{plural} (depth limit)")
            return

        for i, child in enumerate(kids):
            walk(child, depth + 1, child_prefix, i == len(kids) - 1)

    render_roots = [r for r in roots if should_render(r)]
    for i, root in enumerate(render_roots):
        walk(root, 0, "", i == len(render_roots) - 1)
    return "\n".join(lines)


def render_node(node: dict) -> str:
    out: list[str] = []
    out.append(f"{node['displayName']}   {node['className']}")
    out.append(f"  id:       {node['id']}")
    out.append(f"  kind:     {node['kind']}")
    if node.get("label"):
        out.append(f"  label:    {node['label']}")
    out.append(f"  frame:    {_rect_str(node['frame'])}")
    out.append(f"  bounds:   {_rect_str(node['bounds'])}")
    out.append(f"  opacity:  {node['opacity']:.3f}")
    out.append(f"  zIndex:   {node['zIndex']}")
    flags = _flag_str(node)
    if flags:
        out.append(f"  flags:    {flags}")
    out.append(f"  children: {len(node.get('children', []))}")
    if node.get("snapshotID"):
        out.append(f"  snapshot: available (use `treescope snapshot {node['id']}`)")

    for section in node.get("sections", []):
        attrs = section.get("attributes", [])
        if not attrs:
            continue
        out.append("")
        out.append(f"  [{section['title']}]")
        width = max(len(a["title"]) for a in attrs)
        for attr in attrs:
            editable = (
                f"   (editable: {attr['keyPath']})"
                if attr.get("editable") and attr.get("keyPath")
                else ""
            )
            out.append(f"    {attr['title'].ljust(width)}  {display_value(attr['value'])}{editable}")
    return "\n".join(out)


def _attr_text_matches(node: dict, needle: str) -> bool:
    for section in node.get("sections", []):
        for attr in section.get("attributes", []):
            v = attr.get("value", {})
            if v.get("t") in ("string", "enum", "reference") and needle in str(v.get("v", "")).lower():
                return True
    return False


def find_nodes(roots: list[dict], needle: str, limit: int) -> list[dict]:
    found: list[dict] = []
    lower = needle.lower()

    def walk(node: dict, path: list[str]) -> None:
        if len(found) >= limit:
            return
        here = path + [node["displayName"]]
        if _node_matches(node, lower) or _attr_text_matches(node, lower):
            found.append({
                "id": node["id"],
                "displayName": node["displayName"],
                "className": node["className"],
                "label": node.get("label"),
                "kind": node["kind"],
                "frame": node["frame"],
                "path": " › ".join(here),
            })
        for c in node.get("children", []):
            walk(c, here)

    for r in roots:
        walk(r, [])
    return found


def find_node(roots: list[dict], node_id: str) -> Optional[dict]:
    stack = list(roots)
    while stack:
        n = stack.pop()
        if n["id"] == node_id:
            return n
        stack.extend(n.get("children", []))
    return None


def count_nodes(roots: list[dict]) -> int:
    n = 0
    stack = list(roots)
    while stack:
        x = stack.pop()
        n += 1
        stack.extend(x.get("children", []))
    return n


def render_device(d: dict) -> str:
    sim = " (Simulator)" if d.get("isSimulator") else ""
    w = _num(d["screenSize"]["width"])
    h = _num(d["screenSize"]["height"])
    return "\n".join([
        f"App:     {d['appName']} ({d['bundleID']})",
        f"Process: {d['processName']}",
        f"OS:      {d['osName']} {d['osVersion']}",
        f"Device:  {d['deviceName']} — {d['deviceModel']}{sim}",
        f"Screen:  {w} x {h} @{_num(d['screenScale'])}x",
    ])


def snapshot_summary(snap: dict) -> str:
    roots = snap.get("roots", [])
    return f"{len(roots)} root(s), {count_nodes(roots)} nodes total"
