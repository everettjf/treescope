import type { HierarchySnapshot, ServerInfo, ViewNode } from "./protocol";
import { Flag, hasFlag } from "./protocol";
import type { ConnectionState } from "./client";

export interface DisplayOptions {
  showWireframe: boolean;
  showSnapshots: boolean;
  exploded: boolean;
  includeLayers: boolean;
  hideSystem: boolean;
  zoom: number;
}

export interface State {
  connection: ConnectionState;
  serverInfo?: ServerInfo;
  snapshot?: HierarchySnapshot;
  selectedID?: string;
  hoveredID?: string;
  expanded: Set<string>;
  search: string;
  options: DisplayOptions;
  error?: string;
  refreshing: boolean;
}

export const initialState: State = {
  connection: "disconnected",
  expanded: new Set(),
  search: "",
  refreshing: false,
  options: {
    showWireframe: true,
    showSnapshots: true,
    exploded: false,
    includeLayers: false,
    hideSystem: false,
    zoom: 1,
  },
};

/** Index every node by id for O(1) lookup. */
export function indexNodes(snapshot: HierarchySnapshot): Map<string, ViewNode> {
  const map = new Map<string, ViewNode>();
  const walk = (n: ViewNode) => { map.set(n.id, n); n.children.forEach(walk); };
  snapshot.roots.forEach(walk);
  return map;
}

/** Path of ancestor ids down to `id`, inclusive — for auto-expand on select. */
export function pathTo(roots: ViewNode[], id: string): string[] {
  const find = (n: ViewNode, acc: string[]): string[] | undefined => {
    if (n.id === id) return [...acc, n.id];
    for (const c of n.children) {
      const r = find(c, [...acc, n.id]);
      if (r) return r;
    }
    return undefined;
  };
  for (const root of roots) {
    const r = find(root, []);
    if (r) return r;
  }
  return [];
}

/** Roots filtered by search query + hide-system, keeping ancestors of matches. */
export function displayRoots(
  roots: ViewNode[],
  query: string,
  hideSystem: boolean,
): ViewNode[] {
  const q = query.trim().toLowerCase();
  const filter = (n: ViewNode): ViewNode | undefined => {
    if (hideSystem && hasFlag(n, Flag.systemView) && !hasFlag(n, Flag.hostsSwiftUI)) return undefined;
    const kids = n.children.map(filter).filter((x): x is ViewNode => !!x);
    const selfMatch = q === "" || nodeMatches(n, q);
    if (selfMatch || kids.length) return { ...n, children: kids };
    return undefined;
  };
  return roots.map(filter).filter((x): x is ViewNode => !!x);
}

export function nodeMatches(n: ViewNode, query: string): boolean {
  return n.displayName.toLowerCase().includes(query)
    || n.className.toLowerCase().includes(query)
    || (n.label?.toLowerCase().includes(query) ?? false);
}

/** All ids of nodes with children, down to `levels` deep — for initial expand. */
export function autoExpandIDs(roots: ViewNode[], levels: number): Set<string> {
  const ids = new Set<string>();
  const walk = (n: ViewNode, d: number) => {
    if (d < levels && n.children.length) ids.add(n.id);
    n.children.forEach((c) => walk(c, d + 1));
  };
  roots.forEach((r) => walk(r, 0));
  return ids;
}

/** Flat, visible (expanded) node list — used for keyboard up/down navigation. */
export function visibleList(roots: ViewNode[], expanded: Set<string>): ViewNode[] {
  const out: ViewNode[] = [];
  const walk = (n: ViewNode) => {
    out.push(n);
    if (expanded.has(n.id)) n.children.forEach(walk);
  };
  roots.forEach(walk);
  return out;
}

export function countNodes(snapshot: HierarchySnapshot): number {
  let n = 0;
  const walk = (node: ViewNode) => { n++; node.children.forEach(walk); };
  snapshot.roots.forEach(walk);
  return n;
}

/** Per-framework accent color shared by tree + canvas + inspector. */
export function kindColor(kind: string): string {
  switch (kind) {
    case "swiftUI": case "hostingView": return "#ff9f0a";
    case "caLayer": return "#bf5af2";
    case "window": case "nsWindow": return "#64d2ff";
    case "uiViewController": case "nsViewController": return "#5e9eff";
    case "uiView": case "nsView": return "#30d158";
    default: return "#98989d";
  }
}
