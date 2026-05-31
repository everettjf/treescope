import {
  ViewNode, Flag, Rect, displayValue, HierarchySnapshot, DeviceInfo,
} from "./protocol.js";

export interface TreeFilter {
  maxDepth: number;        // 0 = unlimited
  visibleOnly: boolean;    // drop hidden / zero-size / offscreen
  hideSystem: boolean;     // drop system views
  match?: string;          // case-insensitive substring over name/class/label
}

function rectStr(r: Rect): string {
  const n = (v: number) => (Number.isInteger(v) ? String(v) : v.toFixed(1));
  return `(${n(r.x)}, ${n(r.y)}, ${n(r.width)}, ${n(r.height)})`;
}

/** Short flag annotations, e.g. "H off α0.50". */
function flagStr(node: ViewNode): string {
  const parts: string[] = [];
  if ((node.flags & Flag.hidden) !== 0) parts.push("hidden");
  if ((node.flags & Flag.zeroSize) !== 0) parts.push("zero");
  if ((node.flags & Flag.offscreen) !== 0) parts.push("offscreen");
  if ((node.flags & Flag.hostsSwiftUI) !== 0) parts.push("hostsSwiftUI");
  if ((node.flags & Flag.systemView) !== 0) parts.push("system");
  if (node.opacity < 0.999) parts.push(`α${node.opacity.toFixed(2)}`);
  return parts.join(" ");
}

function isVisible(node: ViewNode): boolean {
  return (node.flags & (Flag.hidden | Flag.zeroSize)) === 0 && node.opacity > 0.001;
}

function nodeMatches(node: ViewNode, needle: string): boolean {
  const hay = `${node.displayName}\n${node.className}\n${node.label ?? ""}`.toLowerCase();
  return hay.includes(needle);
}

/** True if node or any descendant matches (so we keep ancestors of matches). */
function subtreeMatches(node: ViewNode, needle: string): boolean {
  if (nodeMatches(node, needle)) return true;
  return node.children.some((c) => subtreeMatches(c, needle));
}

/** One compact line per node, e.g.:
 *   ├─ UILabel  "Hello"  #obj:1234  (16, 40, 200, 24)
 */
export function renderTree(roots: ViewNode[], filter: TreeFilter): string {
  const lines: string[] = [];
  const needle = filter.match?.toLowerCase();

  // Whether a node survives the active filters (and so contributes a line).
  const shouldRender = (node: ViewNode): boolean => {
    if (filter.visibleOnly && !isVisible(node)) return false;
    if (filter.hideSystem && (node.flags & Flag.systemView) !== 0) return false;
    if (needle && !subtreeMatches(node, needle)) return false;
    return true;
  };

  // `node` is always renderable here (callers pre-filter), so connector glyphs
  // (├─ vs └─) reflect the *rendered* siblings, not the raw children.
  const walk = (node: ViewNode, depth: number, prefix: string, isLast: boolean) => {
    const branch = depth === 0 ? "" : (isLast ? "└─ " : "├─ ");
    const flags = flagStr(node);
    const label = node.label ? `  "${truncate(node.label, 40)}"` : "";
    const cls = node.className !== node.displayName ? `  ${node.className}` : "";
    const meta = [`#${node.id}`, rectStr(node.frame), flags].filter(Boolean).join("  ");
    lines.push(`${prefix}${branch}${node.displayName}${label}${cls}  ·  ${meta}`);

    const childPrefix = prefix + (depth === 0 ? "" : (isLast ? "   " : "│  "));
    const kids = node.children.filter(shouldRender);

    if (filter.maxDepth > 0 && depth + 1 >= filter.maxDepth) {
      if (kids.length > 0) {
        lines.push(`${childPrefix}└─ … ${kids.length} child${kids.length === 1 ? "" : "ren"} (depth limit)`);
      }
      return;
    }

    kids.forEach((child, i) => walk(child, depth + 1, childPrefix, i === kids.length - 1));
  };

  const renderRoots = roots.filter(shouldRender);
  renderRoots.forEach((root, i) => walk(root, 0, "", i === renderRoots.length - 1));
  return lines.join("\n");
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

/** Detailed attribute dump for one node. */
export function renderNode(node: ViewNode): string {
  const out: string[] = [];
  out.push(`${node.displayName}   ${node.className}`);
  out.push(`  id:       ${node.id}`);
  out.push(`  kind:     ${node.kind}`);
  if (node.label) out.push(`  label:    ${node.label}`);
  out.push(`  frame:    ${rectStr(node.frame)}`);
  out.push(`  bounds:   ${rectStr(node.bounds)}`);
  out.push(`  opacity:  ${node.opacity.toFixed(3)}`);
  out.push(`  zIndex:   ${node.zIndex}`);
  const flags = flagStr(node);
  if (flags) out.push(`  flags:    ${flags}`);
  out.push(`  children: ${node.children.length}`);
  if (node.snapshotID) out.push(`  snapshot: available (use \`treescope snapshot ${node.id}\`)`);

  for (const section of node.sections) {
    if (section.attributes.length === 0) continue;
    out.push("");
    out.push(`  [${section.title}]`);
    const width = Math.max(...section.attributes.map((a) => a.title.length));
    for (const attr of section.attributes) {
      const editable = attr.editable && attr.keyPath ? `   (editable: ${attr.keyPath})` : "";
      out.push(`    ${attr.title.padEnd(width)}  ${displayValue(attr.value)}${editable}`);
    }
  }
  return out.join("\n");
}

export interface FoundNode {
  id: string;
  displayName: string;
  className: string;
  label?: string | null;
  kind: string;
  frame: Rect;
  path: string; // human path of displayNames from root
}

/** Flatten a tree into matching nodes for `find`. */
export function findNodes(roots: ViewNode[], needle: string, limit: number): FoundNode[] {
  const found: FoundNode[] = [];
  const lower = needle.toLowerCase();
  const walk = (node: ViewNode, path: string[]) => {
    if (found.length >= limit) return;
    const here = [...path, node.displayName];
    if (nodeMatches(node, lower) || attrTextMatches(node, lower)) {
      found.push({
        id: node.id,
        displayName: node.displayName,
        className: node.className,
        label: node.label,
        kind: node.kind,
        frame: node.frame,
        path: here.join(" › "),
      });
    }
    for (const c of node.children) walk(c, here);
  };
  for (const r of roots) walk(r, []);
  return found;
}

/** Also match against string/enum attribute values (e.g. label text). */
function attrTextMatches(node: ViewNode, needle: string): boolean {
  for (const section of node.sections) {
    for (const attr of section.attributes) {
      const v = attr.value;
      if ((v.t === "string" || v.t === "enum" || v.t === "reference") && v.v.toLowerCase().includes(needle)) {
        return true;
      }
    }
  }
  return false;
}

export function findNode(roots: ViewNode[], id: string): ViewNode | undefined {
  const stack = [...roots];
  while (stack.length) {
    const n = stack.pop()!;
    if (n.id === id) return n;
    stack.push(...n.children);
  }
  return undefined;
}

export function countNodes(roots: ViewNode[]): number {
  let n = 0;
  const stack = [...roots];
  while (stack.length) { const x = stack.pop()!; n++; stack.push(...x.children); }
  return n;
}

export function renderDevice(d: DeviceInfo): string {
  return [
    `App:     ${d.appName} (${d.bundleID})`,
    `Process: ${d.processName}`,
    `OS:      ${d.osName} ${d.osVersion}`,
    `Device:  ${d.deviceName} — ${d.deviceModel}${d.isSimulator ? " (Simulator)" : ""}`,
    `Screen:  ${d.screenSize.width} x ${d.screenSize.height} @${d.screenScale}x`,
  ].join("\n");
}

export function snapshotSummary(snap: HierarchySnapshot): string {
  return `${snap.roots.length} root(s), ${countNodes(snap.roots)} nodes total`;
}
