import { useCallback, useEffect, useMemo, useReducer, useRef } from "react";
import { Client } from "../client";
import type { AttributeValue, HierarchyOptions, ViewNode } from "../protocol";
import {
  type State, initialState, indexNodes, pathTo, autoExpandIDs, displayRoots, visibleList,
} from "../store";

type Action =
  | { type: "patch"; patch: Partial<State> }
  | { type: "setSnapshot"; snapshot: State["snapshot"] }
  | { type: "select"; id: string; ancestors: string[] }
  | { type: "toggleExpand"; id: string }
  | { type: "setExpanded"; ids: Set<string> }
  | { type: "patchOptions"; patch: Partial<State["options"]> };

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
    case "patchOptions": return { ...state, options: { ...state.options, ...action.patch } };
  }
}

export interface Inspector {
  state: State;
  index: Map<string, ViewNode>;
  selected?: ViewNode;
  filteredRoots: ViewNode[];
  client: Client;
  refresh: () => void;
  select: (id: string) => void;
  hover: (id: string | undefined) => void;
  toggleExpand: (id: string) => void;
  setExpanded: (ids: Set<string>) => void;
  setSearch: (q: string) => void;
  setOption: <K extends keyof State["options"]>(key: K, value: State["options"][K]) => void;
  setAttribute: (nodeID: string, keyPath: string, value: AttributeValue) => void;
  moveSelection: (delta: number) => void;
}

export function useInspector(): Inspector {
  const [state, dispatch] = useReducer(reducer, initialState);
  const clientRef = useRef<Client>();
  if (!clientRef.current) clientRef.current = new Client();
  const client = clientRef.current;

  const stateRef = useRef(state);
  stateRef.current = state;

  const currentOptions = useCallback((): HierarchyOptions => ({
    includeSwiftUI: true,
    includeLayers: stateRef.current.options.includeLayers,
    hideSystemViews: false, // filtered client-side so toggling is instant
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

  // Connection lifecycle with retry.
  useEffect(() => {
    let cancelled = false;
    client.onState = (connection, detail) =>
      dispatch({ type: "patch", patch: { connection, error: detail ?? stateRef.current.error } });
    client.onEvent = (event) => {
      if (event.t === "hierarchyChanged") void refresh();
      if (event.t === "willDisconnect") client.disconnect();
    };
    const boot = async () => {
      if (cancelled) return;
      try {
        await client.connect();
        const info = await client.handshake();
        dispatch({ type: "patch", patch: { serverInfo: info } });
        await refresh();
      } catch {
        if (!cancelled) setTimeout(boot, 2000);
      }
    };
    void boot();
    return () => { cancelled = true; client.disconnect(); };
  }, [client, refresh]);

  const index = useMemo(
    () => (state.snapshot ? indexNodes(state.snapshot) : new Map<string, ViewNode>()),
    [state.snapshot],
  );
  const selected = state.selectedID ? index.get(state.selectedID) : undefined;
  const filteredRoots = useMemo(
    () => displayRoots(state.snapshot?.roots ?? [], state.search, state.options.hideSystem),
    [state.snapshot, state.search, state.options.hideSystem],
  );

  return {
    state, index, selected, filteredRoots, client,
    refresh: () => void refresh(),
    select, hover,
    toggleExpand: (id) => dispatch({ type: "toggleExpand", id }),
    setExpanded: (ids) => dispatch({ type: "setExpanded", ids }),
    setSearch: (q) => dispatch({ type: "patch", patch: { search: q } }),
    setOption: (key, value) => {
      dispatch({ type: "patchOptions", patch: { [key]: value } as Partial<State["options"]> });
      if (key === "includeLayers") void refresh();
    },
    setAttribute,
    moveSelection,
  };
}
