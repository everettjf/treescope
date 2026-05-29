import { ChevronRight } from "lucide-react";
import { kindColor } from "../store";
import type { Inspector } from "../hooks/useInspector";

/** Ancestor path of the selected node, clickable to jump up the tree. */
export function Breadcrumbs({ insp }: { insp: Inspector }) {
  const { state, index, select } = insp;
  if (!state.selectedID || !state.snapshot) return null;
  const ids = pathTo(state.snapshot.roots, state.selectedID);
  if (ids.length === 0) return null;

  return (
    <div className="flex items-center gap-0.5 overflow-x-auto border-b border-border bg-card/40 px-3 py-1 text-[11px]">
      {ids.map((id, i) => {
        const node = index.get(id);
        if (!node) return null;
        const isLast = i === ids.length - 1;
        return (
          <span key={id} className="flex shrink-0 items-center gap-0.5">
            {i > 0 && <ChevronRight className="h-3 w-3 text-muted-foreground/50" />}
            <button
              className={`flex items-center gap-1 rounded px-1 py-0.5 hover:bg-secondary ${isLast ? "text-foreground" : "text-muted-foreground"}`}
              onClick={() => select(id)}
            >
              <span className="h-2 w-2 rounded-sm" style={{ background: kindColor(node.kind) }} />
              {node.displayName}
            </button>
          </span>
        );
      })}
    </div>
  );
}

function pathTo(roots: import("../protocol").ViewNode[], id: string): string[] {
  const find = (n: import("../protocol").ViewNode, acc: string[]): string[] | undefined => {
    if (n.id === id) return [...acc, n.id];
    for (const c of n.children) { const r = find(c, [...acc, n.id]); if (r) return r; }
    return undefined;
  };
  for (const root of roots) { const r = find(root, []); if (r) return r; }
  return [];
}
