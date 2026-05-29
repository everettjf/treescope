import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { RotateCcw, Hand, Orbit } from "lucide-react";
import type { ViewNode } from "../protocol";
import { Flag, hasFlag } from "../protocol";
import { kindColor } from "../store";
import type { Inspector } from "../hooks/useInspector";
import { Slider } from "./ui/slider";
import { Button } from "./ui/button";

interface Flat { node: ViewNode; depth: number; }

const DEFAULT_ROT = { x: 18, y: -22 };
const DEFAULT_SPACING = 26;

export function Canvas({ insp }: { insp: Inspector }) {
  const { state, select, hover, client } = insp;
  const { options } = state;
  const viewportRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 800, h: 600 });
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [rot, setRot] = useState(DEFAULT_ROT);
  const [spacing, setSpacing] = useState(DEFAULT_SPACING);
  const drag = useRef<{ x: number; y: number; px: number; py: number; rx: number; ry: number; mode: "pan" | "orbit" } | null>(null);

  useLayoutEffect(() => {
    const el = viewportRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight }));
    ro.observe(el);
    setSize({ w: el.clientWidth, h: el.clientHeight });
    return () => ro.disconnect();
  }, []);

  useEffect(() => { setPan({ x: 0, y: 0 }); }, [state.snapshot]);

  const { flat, maxX, maxY } = useMemo(() => {
    const f: Flat[] = [];
    let mx = 1, my = 1;
    const walk = (n: ViewNode, depth: number) => {
      f.push({ node: n, depth });
      mx = Math.max(mx, n.frame.x + n.frame.width);
      my = Math.max(my, n.frame.y + n.frame.height);
      n.children.forEach((c) => walk(c, depth + 1));
    };
    state.snapshot?.roots.forEach((r) => walk(r, 0));
    return { flat: f, maxX: mx, maxY: my };
  }, [state.snapshot]);

  const fit = Math.min(size.w / maxX, size.h / maxY) * 0.82 || 1;
  const baseScale = Math.max(0.05, fit);
  const scale = baseScale * options.zoom;

  // Focus (F / toolbar): center + zoom the selected node.
  const focusedRef = useRef(insp.focusSignal);
  useEffect(() => {
    if (insp.focusSignal === focusedRef.current) return;
    focusedRef.current = insp.focusSignal;
    const node = insp.selected;
    if (!node || node.frame.width < 1 || node.frame.height < 1) return;
    const targetZoom = clamp(Math.min(size.w / (node.frame.width * baseScale), size.h / (node.frame.height * baseScale)) * 0.55, 0.2, 6);
    insp.setOption("zoom", targetZoom);
    const s = baseScale * targetZoom;
    const cx = node.frame.x + node.frame.width / 2;
    const cy = node.frame.y + node.frame.height / 2;
    setPan({
      x: size.w / 2 - cx * s - (size.w - maxX * s) / 2,
      y: size.h / 2 - cy * s - (size.h - maxY * s) / 2,
    });
  }, [insp.focusSignal]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!state.snapshot || state.snapshot.roots.length === 0) {
    return <div className="h-full bg-[radial-gradient(circle_at_50%_40%,#232327,#161618)]" />;
  }

  const baseLeft = (size.w - maxX * scale) / 2 + pan.x;
  const baseTop = (size.h - maxY * scale) / 2 + pan.y;
  const explodeStep = options.exploded ? spacing : 0;

  const bg = options.showSnapshots
    ? [...flat].filter((f) => f.node.snapshotID).sort((a, b) => area(b.node) - area(a.node))[0]
    : undefined;

  const onWheel = (e: React.WheelEvent) => {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    insp.setOption("zoom", clamp(options.zoom * (e.deltaY < 0 ? 1.1 : 0.9), 0.1, 6));
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.target !== e.currentTarget) return;
    const mode: "pan" | "orbit" = options.exploded && !e.altKey && !e.shiftKey ? "orbit" : "pan";
    drag.current = { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y, rx: rot.x, ry: rot.y, mode };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!drag.current) return;
    const dx = e.clientX - drag.current.x, dy = e.clientY - drag.current.y;
    if (drag.current.mode === "orbit") setRot({ x: clamp(drag.current.rx - dy * 0.4, -85, 85), y: drag.current.ry + dx * 0.4 });
    else setPan({ x: drag.current.px + dx, y: drag.current.py + dy });
  };

  const transform = `translate(${baseLeft}px, ${baseTop}px) scale(${scale}) ` +
    (options.exploded ? `rotateX(${rot.x}deg) rotateY(${rot.y}deg)` : "");

  return (
    <div
      ref={viewportRef}
      className="relative h-full select-none overflow-hidden bg-[radial-gradient(circle_at_50%_40%,#232327,#161618)]"
      style={{ perspective: 1600, cursor: drag.current?.mode === "orbit" ? "grabbing" : "grab" }}
      onWheel={onWheel}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={() => { drag.current = null; }}
      onDoubleClick={() => { setRot(DEFAULT_ROT); setPan({ x: 0, y: 0 }); }}
    >
      <div
        className="absolute origin-top-left"
        style={{ width: maxX, height: maxY, transformStyle: "preserve-3d", transform, transition: drag.current ? "none" : "transform 0.25s ease" }}
      >
        {bg && (
          <img src={client.snapshotURL(bg.node.snapshotID!)} className="pointer-events-none absolute" alt=""
            style={{ left: bg.node.frame.x, top: bg.node.frame.y, width: bg.node.frame.width, height: bg.node.frame.height, opacity: options.exploded ? 0.6 : 0.95 }} />
        )}
        {flat.map(({ node, depth }) => {
          if (node.frame.width < 0.5 || node.frame.height < 0.5) return null;
          const selected = node.id === state.selectedID;
          const hovered = node.id === state.hoveredID;
          const accent = kindColor(node.kind);
          return (
            <div key={node.id} className="absolute"
              style={{
                left: node.frame.x, top: node.frame.y, width: node.frame.width, height: node.frame.height,
                transform: explodeStep ? `translateZ(${depth * explodeStep}px)` : undefined,
                transition: drag.current ? "none" : "transform 0.25s ease",
                border: selected ? `2px solid ${accent}` : hovered ? `1.5px solid ${accent}` : options.showWireframe ? `1px solid ${accent}88` : "1px solid transparent",
                background: selected ? `${accent}22` : options.exploded ? `${accent}10` : hovered ? `${accent}14` : "transparent",
                opacity: hasFlag(node, Flag.hidden) ? 0.35 : 1,
                zIndex: selected ? 9999 : hovered ? 9998 : undefined,
                boxShadow: options.exploded ? "0 1px 8px rgba(0,0,0,0.35)" : undefined,
              }}
              onClick={(e) => { e.stopPropagation(); select(node.id); }}
              onMouseEnter={() => hover(node.id)}
              onMouseLeave={() => hover(undefined)}
            >
              {selected && options.showSnapshots && node.snapshotID && (
                <img src={client.snapshotURL(node.snapshotID)} className="pointer-events-none h-full w-full" alt="" />
              )}
            </div>
          );
        })}
      </div>

      {options.exploded && (
        <div className="absolute bottom-3 left-1/2 flex -translate-x-1/2 items-center gap-3 rounded-lg border border-border/60 bg-card/80 px-3 py-2 backdrop-blur-md">
          <Orbit className="h-3.5 w-3.5 text-muted-foreground" />
          <AngleSlider label="X" value={rot.x} min={-85} max={85} onChange={(x) => setRot((r) => ({ ...r, x }))} />
          <AngleSlider label="Y" value={rot.y} min={-180} max={180} onChange={(y) => setRot((r) => ({ ...r, y }))} />
          <div className="flex items-center gap-1.5">
            <span className="text-[10px] text-muted-foreground">depth</span>
            <Slider className="w-20" value={[spacing]} min={4} max={80} step={1} onValueChange={([v]) => setSpacing(v)} />
          </div>
          <Button variant="ghost" size="icon" className="h-6 w-6" title="Reset" onClick={() => { setRot(DEFAULT_ROT); setSpacing(DEFAULT_SPACING); }}>
            <RotateCcw className="h-3.5 w-3.5" />
          </Button>
        </div>
      )}

      <div className="pointer-events-none absolute right-3 top-3 flex items-center gap-1 rounded-md bg-card/70 px-2 py-1 text-[10px] text-muted-foreground backdrop-blur">
        {options.exploded ? <><Orbit className="h-3 w-3" /> drag to orbit · ⌥ drag to pan</> : <><Hand className="h-3 w-3" /> drag to pan · ⌘-scroll to zoom</>}
      </div>
    </div>
  );
}

function AngleSlider({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (v: number) => void }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="w-2 text-[10px] text-muted-foreground">{label}</span>
      <Slider className="w-20" value={[value]} min={min} max={max} step={1} onValueChange={([v]) => onChange(v)} />
      <span className="w-7 text-right font-mono text-[10px] text-muted-foreground">{Math.round(value)}°</span>
    </div>
  );
}

function area(n: ViewNode): number { return n.frame.width * n.frame.height; }
function clamp(v: number, lo: number, hi: number): number { return Math.max(lo, Math.min(hi, v)); }
