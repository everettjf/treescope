import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { ViewNode } from "../protocol";
import { Flag, hasFlag } from "../protocol";
import { kindColor } from "../store";
import type { Inspector } from "../hooks/useInspector";

interface Flat { node: ViewNode; depth: number; }

export function Canvas({ insp }: { insp: Inspector }) {
  const { state, select, hover, client } = insp;
  const { options } = state;
  const viewportRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 800, h: 600 });
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const drag = useRef<{ x: number; y: number; px: number; py: number } | null>(null);

  useLayoutEffect(() => {
    const el = viewportRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight }));
    ro.observe(el);
    setSize({ w: el.clientWidth, h: el.clientHeight });
    return () => ro.disconnect();
  }, []);

  // Reset pan when a new snapshot loads.
  useEffect(() => { setPan({ x: 0, y: 0 }); }, [state.snapshot]);

  if (!state.snapshot || state.snapshot.roots.length === 0) {
    return (
      <div className="flex h-full items-center justify-center bg-[radial-gradient(circle_at_50%_40%,#232327,#161618)] text-muted-foreground">
        {state.connection === "connected" ? "No hierarchy captured" : "Connecting…"}
      </div>
    );
  }

  const flat: Flat[] = [];
  let maxX = 1, maxY = 1;
  const walk = (n: ViewNode, depth: number) => {
    flat.push({ node: n, depth });
    maxX = Math.max(maxX, n.frame.x + n.frame.width);
    maxY = Math.max(maxY, n.frame.y + n.frame.height);
    n.children.forEach((c) => walk(c, depth + 1));
  };
  state.snapshot.roots.forEach((r) => walk(r, 0));

  const fit = Math.min(size.w / maxX, size.h / maxY) * 0.88 || 1;
  const scale = Math.max(0.05, fit) * options.zoom;
  const baseLeft = (size.w - maxX * scale) / 2 + pan.x;
  const baseTop = (size.h - maxY * scale) / 2 + pan.y;
  const explodeStep = options.exploded ? 26 : 0;

  const bg = options.showSnapshots
    ? [...flat].filter((f) => f.node.snapshotID).sort((a, b) => area(b.node) - area(a.node))[0]
    : undefined;

  const onWheel = (e: React.WheelEvent) => {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    const z = options.zoom * (e.deltaY < 0 ? 1.1 : 0.9);
    insp.setOption("zoom", clamp(z, 0.1, 6));
  };

  return (
    <div
      ref={viewportRef}
      className="relative h-full overflow-hidden bg-[radial-gradient(circle_at_50%_40%,#232327,#161618)]"
      style={{ perspective: 1600, cursor: drag.current ? "grabbing" : "grab" }}
      onWheel={onWheel}
      onPointerDown={(e) => {
        if (e.target !== e.currentTarget) return;
        drag.current = { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y };
        (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
      }}
      onPointerMove={(e) => {
        if (!drag.current) return;
        setPan({ x: drag.current.px + (e.clientX - drag.current.x), y: drag.current.py + (e.clientY - drag.current.y) });
      }}
      onPointerUp={() => { drag.current = null; }}
    >
      <div
        className="absolute origin-top-left transition-transform duration-200"
        style={{
          width: maxX, height: maxY,
          transformStyle: "preserve-3d",
          transform: `translate(${baseLeft}px, ${baseTop}px) scale(${scale}) ${options.exploded ? "rotateX(18deg) rotateY(-22deg)" : ""}`,
        }}
      >
        {bg && (
          <img
            src={client.snapshotURL(bg.node.snapshotID!)}
            className="pointer-events-none absolute opacity-95"
            style={{ left: bg.node.frame.x, top: bg.node.frame.y, width: bg.node.frame.width, height: bg.node.frame.height }}
            alt=""
          />
        )}
        {flat.map(({ node, depth }) => {
          if (node.frame.width < 0.5 || node.frame.height < 0.5) return null;
          const selected = node.id === state.selectedID;
          const hovered = node.id === state.hoveredID;
          const accent = kindColor(node.kind);
          return (
            <div
              key={node.id}
              className="absolute"
              style={{
                left: node.frame.x, top: node.frame.y, width: node.frame.width, height: node.frame.height,
                transform: explodeStep ? `translateZ(${depth * explodeStep}px)` : undefined,
                border: selected ? `2px solid ${accent}` : hovered ? `1.5px solid ${accent}`
                  : options.showWireframe ? `1px solid ${accent}88` : "1px solid transparent",
                background: selected ? `${accent}22` : hovered ? `${accent}14` : "transparent",
                opacity: hasFlag(node, Flag.hidden) ? 0.35 : 1,
                zIndex: selected ? 9999 : hovered ? 9998 : undefined,
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
    </div>
  );
}

function area(n: ViewNode): number { return n.frame.width * n.frame.height; }
function clamp(v: number, lo: number, hi: number): number { return Math.max(lo, Math.min(hi, v)); }
