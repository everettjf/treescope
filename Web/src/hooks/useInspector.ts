import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import { Client } from "../client";
import type { AttributeValue, HierarchyOptions, ViewNode } from "../protocol";
import {
  type State, type DisplayOptions, initialState, indexNodes, pathTo, autoExpandIDs, displayRoots, visibleList,
} from "../store";

const OPTIONS_KEY = "treescope.options";

function loadOptions(): DisplayOptions {
  try {
    const saved = JSON.parse(localStorage.getItem(OPTIONS_KEY) || "{}");
    return { ...initialState.options, ...saved };
  } catch { return initialState.options; }
}

type Action =
  | { type: "patch"; patch: Partial<State> }
  | { type: "setSnapshot"; snapshot: State["snapshot"] }
  | { type: "select"; id: string; ancestors: string[] }
  | { type: "toggleExpand"; id: string }
  | { type: "setExpanded"; ids: Set<string> }
  | { type: "patchOptions"; patch: Partial<DisplayOptions> };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case "patch": return { ...state, ...action.patch };
    case "setSnapshot": return { ...state, snapshot: action.snapshot };
    case "select": {
      const expanded = new Set(state.expanded);
      action.ancestors.forEach((a) => expanded.add(a));
      return { ...state, selectedID: action.id, expanded };
    }
    case "toggleExpand": {
      const expanded = new Set(state.expanded);
      if (expanded.has(action.id)) expanded.delete(action.id); else expanded.add(action.id);
      return { ...state, expanded };
    }
    case "setExpanded": return { ...state, expanded: action.ids };
    case "patchOptions": {
      const options = { ...state.options, ...action.patch };
      try { localStorage.setItem(OPTIONS_KEY, JSON.stringify(options)); } catch {}
      return { ...state, options };
    }
  }
}

export interface Inspector {
  state: State;
  index: Map<string, ViewNode>;
  selected?: ViewNode;
  filteredRoots: ViewNode[];
  matchCount: number;
  focusSignal: number;
  client: Client;
  refresh: () => void;
  reconnect: () => void;
  select: (id: string) => void;
  hover: (id: string | undefined) => void;
  toggleExpand: (id: string) => void;
  setExpanded: (ids: Set<string>) => void;
  setSearch: (q: string) => void;
  setOption: <K extends keyof DisplayOptions>(key: K, value: DisplayOptions[K]) => void;
  setAttribute: (nodeID: string, keyPath: string, value: AttributeValue) => void;
  moveSelection: (delta: number) => void;
  requestFocus: () => void;
}

export function useInspector(): Inspector {
  const [state, dispatch] = useReducer(reducer, { ...initialState, options: loadOptions() });
  const [focusSignal, setFocusSignal] = useState(0);
  const clientRef = useRef<Client>();
  if (!clientRef.current) clientRef.current = new Client();
  const client = clientRef.current;
  const stateRef = useRef(state);
  stateRef.current = state;

  const currentOptions = useCallback((): HierarchyOptions => ({
    includeSwiftUI: true,
    includeLayers: stateRef.current.options.includeLayers,
    hideSystemViews: false,
    requestSnapshots: true,
    maxDepth: 0,
  }), []);

  const refresh = useCallback(async () => {
    if (stateRef.current.connection !== "connected") return;
    dispatch({ type: "patch", patch: { refreshing: true, error: undefined } });
    try {
      const snapshot = await client.fetchHierarchy(currentOptions());
      dispatch({ type: "setSnapshot", snapshot });
      dispatch({ type: "setExpanded", ids: autoExpandIDs(snapshot.roots, 3) });
      if (!stateRef.current.selectedID) {
        const first = snapshot.roots[0]?.id;
        if (first) dispatch({ type: "patch", patch: { selectedID: first } });
      }
    } catch (e) {
      dispatch({ type: "patch", patch: { error: String(e) } });
    } finally {
      dispatch({ type: "patch", patch: { refreshing: false } });
    }
  }, [client, currentOptions]);

  const select = useCallback((id: string) => {
    const roots = stateRef.current.snapshot?.roots ?? [];
    dispatch({ type: "select", id, ancestors: pathTo(roots, id) });
    void client.highlight(id);
  }, [client]);

  const hover = useCallback((id: string | undefined) => {
    dispatch({ type: "patch", patch: { hoveredID: id } });
  }, []);

  const setAttribute = useCallback(async (nodeID: string, keyPath: string, value: AttributeValue) => {
    const ok = await client.setAttribute(nodeID, keyPath, value);
    if (ok) void refresh();
  }, [client, refresh]);

  const moveSelection = useCallback((delta: number) => {
    const s = stateRef.current;
    if (!s.snapshot) return;
    const list = visibleList(s.snapshot.roots, s.expanded);
    const idx = list.findIndex((n) => n.id === s.selectedID);
    const next = list[Math.max(0, Math.min(list.length - 1, idx + delta))];
    if (next) select(next.id);
  }, [select]);

  const boot = useCallback(async () => {
    try {
      await client.connect();
      const info = await client.handshake();
      dispatch({ type: "patch", patch: { serverInfo: info } });
      await refresh();
    } catch {
      setTimeout(() => { if (stateRef.current.connection !== "connected") void boot(); }, 2000);
    }
  }, [client, refresh]);

  useEffect(() => {
    let cancelled = false;
    client.onState = (connection, detail) =>
      dispatch({ type: "patch", patch: { connection, error: detail ?? stateRef.current.error } });
    client.onEvent = (event) => {
      if (event.t === "hierarchyChanged") void refresh();
      if (event.t === "willDisconnect") client.disconnect();
    };
    if (!cancelled) void boot();
    return () => { cancelled = true; client.disconnect(); };
  }, [client, boot, refresh]);

  const index = useMemo(
    () => (state.snapshot ? indexNodes(state.snapshot) : new Map<string, ViewNode>()),
    [state.snapshot],
  );
  const selected = state.selectedID ? index.get(state.selectedID) : undefined;
  const filteredRoots = useMemo(
    () => displayRoots(state.snapshot?.roots ?? [], state.search, state.options.hideSystem),
    [state.snapshot, state.search, state.options.hideSystem],
  );
  const matchCount = useMemo(() => {
    const q = state.search.trim().toLowerCase();
    if (!q || !state.snapshot) return 0;
    let n = 0;
    const walk = (node: ViewNode) => {
      if (node.displayName.toLowerCase().includes(q) || node.className.toLowerCase().includes(q)
        || (node.label?.toLowerCase().includes(q) ?? false)) n++;
      node.children.forEach(walk);
    };
    state.snapshot.roots.forEach(walk);
    return n;
  }, [state.snapshot, state.search]);

  return {
    state, index, selected, filteredRoots, matchCount, focusSignal, client,
    refresh: () => void refresh(),
    reconnect: () => { dispatch({ type: "patch", patch: { connection: "connecting", error: undefined } }); void boot(); },
    select, hover,
    toggleExpand: (id) => dispatch({ type: "toggleExpand", id }),
    setExpanded: (ids) => dispatch({ type: "setExpanded", ids }),
    setSearch: (q) => dispatch({ type: "patch", patch: { search: q } }),
    setOption: (key, value) => {
      dispatch({ type: "patchOptions", patch: { [key]: value } as Partial<DisplayOptions> });
      if (key === "includeLayers") void refresh();
    },
    setAttribute,
    moveSelection,
    requestFocus: () => setFocusSignal((n) => n + 1),
  };
}
