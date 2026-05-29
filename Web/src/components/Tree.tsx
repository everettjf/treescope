import { useEffect, useRef } from "react";
import { ChevronRight, ChevronDown, EyeOff, Search, X, Box } from "lucide-react";
import type { ViewNode } from "../protocol";
import { Flag, hasFlag } from "../protocol";
import { kindColor, nodeMatches } from "../store";
import type { Inspector } from "../hooks/useInspector";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import { cn } from "../lib/utils";

export function Tree({ insp }: { insp: Inspector }) {
  const { state, filteredRoots, matchCount, select, hover, toggleExpand, setSearch } = insp;

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-1.5 border-b border-border p-2">
        <Search className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
        <Input
          type="search"
          value={state.search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Filter views…  (/)"
          spellCheck={false}
          className="h-6"
        />
        {state.search && (
          <>
            <span className="shrink-0 font-mono text-[10px] text-muted-foreground">{matchCount}</span>
            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => setSearch("")}>
              <X className="h-3.5 w-3.5" />
            </Button>
          </>
        )}
      </div>
      <div className="min-h-0 flex-1 overflow-auto py-1">
        {filteredRoots.length === 0 ? (
          <div className="p-10 text-center text-muted-foreground">
            {state.snapshot ? "No matching views" : "Connecting…"}
          </div>
        ) : (
          filteredRoots.map((n) => (
            <Row key={n.id} node={n} depth={0} insp={insp} query={state.search}
                 onSelect={select} onHover={hover} onToggle={toggleExpand} />
          ))
        )}
      </div>
    </div>
  );
}

function Row({
  node, depth, insp, query, onSelect, onHover, onToggle,
}: {
  node: ViewNode; depth: number; insp: Inspector; query: string;
  onSelect: (id: string) => void; onHover: (id: string | undefined) => void; onToggle: (id: string) => void;
}) {
  const { state } = insp;
  const expanded = state.expanded.has(node.id);
  const selected = state.selectedID === node.id;
  const hovered = state.hoveredID === node.id;
  const hasKids = node.children.length > 0;
  const rowRef = useRef<HTMLDivElement>(null);

  // Scroll the selected row into view when selection changes elsewhere (canvas/keyboard).
  useEffect(() => {
    if (selected) rowRef.current?.scrollIntoView({ block: "nearest" });
  }, [selected]);

  return (
    <>
      <div
        ref={rowRef}
        className={cn(
          "flex cursor-default select-none items-center gap-1 py-[3px] pr-2 text-[13px]",
          selected ? "bg-primary/25" : hovered ? "bg-primary/10" : "hover:bg-white/[0.05]",
        )}
        style={{ paddingLeft: depth * 14 + 6 }}
        onClick={() => onSelect(node.id)}
        onMouseEnter={() => onHover(node.id)}
        onMouseLeave={() => onHover(undefined)}
      >
        <span
          className="flex h-3 w-3 shrink-0 items-center justify-center text-muted-foreground"
          onClick={(e) => { e.stopPropagation(); if (hasKids) onToggle(node.id); }}
        >
          {hasKids ? (expanded ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />) : null}
        </span>
        <Box className="h-3 w-3 shrink-0" style={{ color: kindColor(node.kind) }} />
        <span className={cn("truncate", node.kind === "swiftUI" && "font-medium")}>
          {highlight(node.displayName, query)}
        </span>
        {subtitle(node) && (
          <span className="ml-1 truncate text-[11px] text-muted-foreground">{subtitle(node)}</span>
        )}
        {hasFlag(node, Flag.hidden) && <EyeOff className="ml-auto h-3 w-3 shrink-0 text-muted-foreground" />}
      </div>
      {expanded && node.children.map((c) => (
        <Row key={c.id} node={c} depth={depth + 1} insp={insp} query={query}
             onSelect={onSelect} onHover={onHover} onToggle={onToggle} />
      ))}
    </>
  );
}

function subtitle(node: ViewNode): string {
  if (node.label) return node.label;
  for (const s of node.sections) {
    for (const a of s.attributes) {
      if ((a.title === "text" || a.title === "stringValue") && a.value.t === "string" && a.value.v) {
        return `"${a.value.v}"`;
      }
    }
  }
  return "";
}

// Highlight the search match within a node name.
function highlight(text: string, query: string) {
  const q = query.trim().toLowerCase();
  if (!q) return text;
  const idx = text.toLowerCase().indexOf(q);
  if (idx < 0) return text;
  return (
    <>
      {text.slice(0, idx)}
      <mark className="ts-match">{text.slice(idx, idx + q.length)}</mark>
      {text.slice(idx + q.length)}
    </>
  );
}

export { nodeMatches };
