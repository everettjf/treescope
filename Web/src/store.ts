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
  expanded: Set<string>;
  search: string;
  options: DisplayOptions;
  error?: string;
  refreshing: boolean;
}

type Listener = () => void;

/** Minimal observable state container. Mutate via methods, read via `state`. */
export class Store {
  state: State = {
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

  private listeners = new Set<Listener>();
  private nodeIndex = new Map<string, ViewNode>();

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  notify(): void { for (const l of this.listeners) l(); }

  update(mutate: (s: State) => void): void {
    mutate(this.state);
    this.notify();
  }

  setSnapshot(snapshot: HierarchySnapshot): void {
    this.nodeIndex.clear();
    const walk = (n: ViewNode) => { this.nodeIndex.set(n.id, n); n.children.forEach(walk); };
    snapshot.roots.forEach(walk);
    this.state.snapshot = snapshot;
    if (!this.state.selectedID || !this.nodeIndex.has(this.state.selectedID)) {
      this.state.selectedID = snapshot.roots[0]?.id;
    }
    this.notify();
  }

  node(id: string | undefined): ViewNode | undefined {
    return id ? this.nodeIndex.get(id) : undefined;
  }

  get selectedNode(): ViewNode | undefined { return this.node(this.state.selectedID); }

  /** Path of ancestor ids down to `id`, for auto-expanding on selection. */
  pathTo(id: string): string[] {
    const find = (n: ViewNode, acc: string[]): string[] | undefined => {
      if (n.id === id) return [...acc, n.id];
      for (const c of n.children) {
        const r = find(c, [...acc, n.id]);
        if (r) return r;
      }
      return undefined;
    };
    for (const root of this.state.snapshot?.roots ?? []) {
      const r = find(root, []);
      if (r) return r;
    }
    return [];
  }

  /** Roots filtered by the search query + hide-system option, keeping ancestors of matches. */
  displayRoots(): ViewNode[] {
    const roots = this.state.snapshot?.roots ?? [];
    const query = this.state.search.trim().toLowerCase();
    const hideSystem = this.state.options.hideSystem;

    const filter = (n: ViewNode): ViewNode | undefined => {
      if (hideSystem && hasFlag(n, Flag.systemView) && !hasFlag(n, Flag.hostsSwiftUI)) return undefined;
      const kids = n.children.map(filter).filter((x): x is ViewNode => !!x);
      const selfMatch = query === "" || matches(n, query);
      if (selfMatch || kids.length) return { ...n, children: kids };
      return undefined;
    };
    return roots.map(filter).filter((x): x is ViewNode => !!x);
  }

  autoExpand(levels: number): void {
    const ids = new Set<string>();
    const walk = (n: ViewNode, d: number) => {
      if (d < levels && n.children.length) ids.add(n.id);
      n.children.forEach((c) => walk(c, d + 1));
    };
    this.state.snapshot?.roots.forEach((r) => walk(r, 0));
    this.state.expanded = ids;
  }
}

function matches(n: ViewNode, query: string): boolean {
  return n.displayName.toLowerCase().includes(query)
    || n.className.toLowerCase().includes(query)
    || (n.label?.toLowerCase().includes(query) ?? false);
}

// Per-kind accent colors + SF-symbol-ish glyphs, shared by tree & canvas.
export function kindColor(kind: string): string {
  switch (kind) {
    case "swiftUI": return "#ff9f0a";
    case "caLayer": return "#bf5af2";
    case "window": case "nsWindow": return "#64d2ff";
    case "uiViewController": case "nsViewController": return "#5e9eff";
    case "hostingView": return "#ff9f0a";
    case "uiView": case "nsView": return "#30d158";
    default: return "#98989d";
  }
}

export function kindGlyph(kind: string): string {
  switch (kind) {
    case "swiftUI": case "hostingView": return "◆";
    case "caLayer": return "▢";
    case "window": case "nsWindow": return "❒";
    case "uiViewController": case "nsViewController": return "⊞";
    default: return "▣";
  }
}
