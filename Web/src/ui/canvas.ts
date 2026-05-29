import type { ViewNode } from "../protocol";
import { Flag, hasFlag } from "../protocol";
import { Store, kindColor } from "../store";

interface FlatNode { node: ViewNode; depth: number; }

/** Visual canvas: wireframe + snapshot + exploded-3D, with zoom/pan/select. */
export class CanvasView {
  readonly el = document.createElement("div");
  private viewport = document.createElement("div");
  private stage = document.createElement("div");
  private panX = 0;
  private panY = 0;
  private dragging = false;
  private dragStart = { x: 0, y: 0, px: 0, py: 0 };

  constructor(
    private store: Store,
    private onSelect: (id: string) => void,
    private snapshotURL: (id: string) => string,
  ) {
    this.el.className = "canvas";
    this.viewport.className = "canvas-viewport";
    this.stage.className = "canvas-stage";
    this.viewport.appendChild(this.stage);
    this.el.appendChild(this.viewport);

    this.viewport.addEventListener("wheel", (e) => {
      if (!e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      const z = this.store.state.options.zoom * (e.deltaY < 0 ? 1.1 : 0.9);
      this.store.update((s) => { s.options.zoom = clamp(z, 0.1, 6); });
    }, { passive: false });

    this.viewport.addEventListener("pointerdown", (e) => {
      if (e.target !== this.viewport && e.target !== this.stage) return;
      this.dragging = true;
      this.dragStart = { x: e.clientX, y: e.clientY, px: this.panX, py: this.panY };
      this.viewport.setPointerCapture(e.pointerId);
    });
    this.viewport.addEventListener("pointermove", (e) => {
      if (!this.dragging) return;
      this.panX = this.dragStart.px + (e.clientX - this.dragStart.x);
      this.panY = this.dragStart.py + (e.clientY - this.dragStart.y);
      this.applyTransform();
    });
    this.viewport.addEventListener("pointerup", () => { this.dragging = false; });
  }

  render(): void {
    const { snapshot, options } = this.store.state;
    this.stage.replaceChildren();
    if (!snapshot || snapshot.roots.length === 0) {
      const empty = document.createElement("div");
      empty.className = "canvas-empty";
      empty.textContent = "No hierarchy captured";
      this.stage.appendChild(empty);
      this.el.classList.toggle("exploded", false);
      return;
    }

    const flat: FlatNode[] = [];
    let maxX = 1, maxY = 1, maxDepth = 0;
    const walk = (n: ViewNode, depth: number) => {
      flat.push({ node: n, depth });
      maxX = Math.max(maxX, n.frame.x + n.frame.width);
      maxY = Math.max(maxY, n.frame.y + n.frame.height);
      maxDepth = Math.max(maxDepth, depth);
      n.children.forEach((c) => walk(c, depth + 1));
    };
    snapshot.roots.forEach((r) => walk(r, 0));

    const vw = this.viewport.clientWidth || 800;
    const vh = this.viewport.clientHeight || 600;
    const fit = Math.min(vw / maxX, vh / maxY) * 0.88 || 1;
    const scale = Math.max(0.05, fit) * options.zoom;

    this.stage.style.width = `${maxX}px`;
    this.stage.style.height = `${maxY}px`;
    this.baseScale = scale;
    this.baseLeft = (vw - maxX * scale) / 2;
    this.baseTop = (vh - maxY * scale) / 2;
    this.applyTransform();

    const explodeStep = options.exploded ? 26 : 0;
    this.el.classList.toggle("exploded", options.exploded);

    // Background snapshot: the largest snapshot-bearing node.
    if (options.showSnapshots) {
      const bg = [...flat]
        .filter((f) => f.node.snapshotID)
        .sort((a, b) => area(b.node) - area(a.node))[0];
      if (bg) {
        const img = document.createElement("img");
        img.className = "node-snapshot";
        img.src = this.snapshotURL(bg.node.snapshotID!);
        img.style.left = `${bg.node.frame.x}px`;
        img.style.top = `${bg.node.frame.y}px`;
        img.style.width = `${bg.node.frame.width}px`;
        img.style.height = `${bg.node.frame.height}px`;
        img.style.opacity = "0.95";
        this.stage.appendChild(img);
      }
    }

    const selectedID = this.store.state.selectedID;
    for (const { node, depth } of flat) {
      if (node.frame.width < 0.5 || node.frame.height < 0.5) continue;
      const box = document.createElement("div");
      const selected = node.id === selectedID;
      box.className = "node-box" + (selected ? " selected" : "");
      box.style.left = `${node.frame.x}px`;
      box.style.top = `${node.frame.y}px`;
      box.style.width = `${node.frame.width}px`;
      box.style.height = `${node.frame.height}px`;
      box.style.setProperty("--accent", kindColor(node.kind));
      if (explodeStep) box.style.transform = `translateZ(${depth * explodeStep}px)`;
      if (!options.showWireframe && !selected) box.style.borderColor = "transparent";
      if (hasFlag(node, Flag.hidden)) box.style.opacity = "0.35";
      box.title = `${node.displayName} — ${node.className}`;
      box.addEventListener("click", (e) => { e.stopPropagation(); this.onSelect(node.id); });

      if (selected && options.showSnapshots && node.snapshotID) {
        const img = document.createElement("img");
        img.className = "node-snapshot-sel";
        img.src = this.snapshotURL(node.snapshotID);
        box.appendChild(img);
      }
      this.stage.appendChild(box);
    }
  }

  private baseScale = 1;
  private baseLeft = 0;
  private baseTop = 0;

  private applyTransform(): void {
    const tx = this.baseLeft + this.panX;
    const ty = this.baseTop + this.panY;
    const rot = this.store.state.options.exploded ? "rotateX(18deg) rotateY(-22deg)" : "";
    this.stage.style.transform = `translate(${tx}px, ${ty}px) scale(${this.baseScale}) ${rot}`;
  }
}

function area(n: ViewNode): number { return n.frame.width * n.frame.height; }
function clamp(v: number, lo: number, hi: number): number { return Math.max(lo, Math.min(hi, v)); }
