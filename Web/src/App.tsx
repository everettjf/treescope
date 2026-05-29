import { useEffect, useRef, useState } from "react";
import { TooltipProvider } from "./components/ui/tooltip";
import { Toolbar } from "./components/Toolbar";
import { Tree } from "./components/Tree";
import { Canvas } from "./components/Canvas";
import { InspectorPanel } from "./components/Inspector";
import { Breadcrumbs } from "./components/Breadcrumbs";
import { ConnectionOverlay } from "./components/ConnectionOverlay";
import { ShortcutsHelp } from "./components/ShortcutsHelp";
import { useInspector } from "./hooks/useInspector";

function usePersistentWidth(key: string, initial: number) {
  const [w, setW] = useState(() => {
    const v = Number(localStorage.getItem(key));
    return v > 0 ? v : initial;
  });
  useEffect(() => { localStorage.setItem(key, String(w)); }, [key, w]);
  return [w, setW] as const;
}

export default function App() {
  const insp = useInspector();
  const [sidebarW, setSidebarW] = usePersistentWidth("treescope.sidebarW", 320);
  const [detailW, setDetailW] = usePersistentWidth("treescope.detailW", 340);
  const [helpOpen, setHelpOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      const typing = target.tagName === "INPUT" || target.tagName === "TEXTAREA";
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "r") { e.preventDefault(); insp.refresh(); return; }
      if (typing) {
        if (e.key === "Escape") (target as HTMLInputElement).blur();
        return;
      }
      if (e.key === "?") setHelpOpen(true);
      else if (e.key === "/") { e.preventDefault(); (document.querySelector('input[type="search"]') as HTMLInputElement)?.focus(); }
      else if (e.key.toLowerCase() === "f" && insp.selected) insp.requestFocus();
      else if (e.key === "ArrowDown") { e.preventDefault(); insp.moveSelection(1); }
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
        <Toolbar insp={insp} onHelp={() => setHelpOpen(true)} />
        <div className="relative flex min-h-0 flex-1">
          <div className="shrink-0 overflow-hidden border-r border-border bg-[#1e1e20]" style={{ width: sidebarW }}>
            <Tree insp={insp} />
          </div>
          <Splitter onDrag={(dx) => setSidebarW((w) => clamp(w + dx, 200, 560))} />
          <div className="flex min-w-0 flex-1 flex-col">
            <Breadcrumbs insp={insp} />
            <div className="relative min-h-0 flex-1">
              <Canvas insp={insp} />
            </div>
          </div>
          <Splitter onDrag={(dx) => setDetailW((w) => clamp(w - dx, 240, 620))} />
          <div className="shrink-0 overflow-hidden border-l border-border bg-[#1e1e20]" style={{ width: detailW }}>
            <InspectorPanel insp={insp} />
          </div>
          <ConnectionOverlay insp={insp} />
        </div>
      </div>
      <ShortcutsHelp open={helpOpen} onOpenChange={setHelpOpen} />
    </TooltipProvider>
  );
}

function Splitter({ onDrag }: { onDrag: (dx: number) => void }) {
  const last = useRef<number | null>(null);
  return (
    <div
      className="z-10 w-[5px] shrink-0 cursor-col-resize hover:bg-primary/30"
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
