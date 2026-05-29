import { useEffect, useRef, useState } from "react";
import { TooltipProvider } from "./components/ui/tooltip";
import { Toolbar } from "./components/Toolbar";
import { Tree } from "./components/Tree";
import { Canvas } from "./components/Canvas";
import { InspectorPanel } from "./components/Inspector";
import { useInspector } from "./hooks/useInspector";

export default function App() {
  const insp = useInspector();
  const [sidebarW, setSidebarW] = useState(320);
  const [detailW, setDetailW] = useState(340);

  // Keyboard navigation: ↑/↓ move selection, ←/→ collapse/expand, ⌘R refresh.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      if (target.tagName === "INPUT" || target.tagName === "TEXTAREA") return;
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "r") { e.preventDefault(); insp.refresh(); return; }
      if (e.key === "ArrowDown") { e.preventDefault(); insp.moveSelection(1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); insp.moveSelection(-1); }
      else if (e.key === "ArrowRight" && insp.selected?.children.length) {
        if (!insp.state.expanded.has(insp.selected.id)) insp.toggleExpand(insp.selected.id);
        else insp.moveSelection(1);
      } else if (e.key === "ArrowLeft" && insp.selected) {
        if (insp.state.expanded.has(insp.selected.id)) insp.toggleExpand(insp.selected.id);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [insp]);

  return (
    <TooltipProvider delayDuration={400}>
      <div className="flex h-full flex-col">
        <Toolbar insp={insp} />
        {insp.state.error && insp.state.connection !== "connected" && (
          <div className="bg-[#ff453a]/15 px-3 py-1 text-[11px] text-[#ff8a80]">{insp.state.error}</div>
        )}
        <div className="flex min-h-0 flex-1">
          <div className="shrink-0 overflow-hidden border-r border-border bg-[#1e1e20]" style={{ width: sidebarW }}>
            <Tree insp={insp} />
          </div>
          <Splitter onDrag={(dx) => setSidebarW((w) => clamp(w + dx, 200, 560))} />
          <div className="min-w-0 flex-1"><Canvas insp={insp} /></div>
          <Splitter onDrag={(dx) => setDetailW((w) => clamp(w - dx, 240, 620))} />
          <div className="shrink-0 overflow-hidden border-l border-border bg-[#1e1e20]" style={{ width: detailW }}>
            <InspectorPanel insp={insp} />
          </div>
        </div>
      </div>
    </TooltipProvider>
  );
}

function Splitter({ onDrag }: { onDrag: (dx: number) => void }) {
  const last = useRef<number | null>(null);
  return (
    <div
      className="w-[5px] shrink-0 cursor-col-resize hover:bg-primary/30"
      onPointerDown={(e) => { last.current = e.clientX; (e.target as HTMLElement).setPointerCapture(e.pointerId); }}
      onPointerMove={(e) => {
        if (last.current === null) return;
        const dx = e.clientX - last.current;
        last.current = e.clientX;
        onDrag(dx);
      }}
      onPointerUp={() => { last.current = null; }}
    />
  );
}

function clamp(v: number, lo: number, hi: number): number { return Math.max(lo, Math.min(hi, v)); }
