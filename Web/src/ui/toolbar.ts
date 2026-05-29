import { Store } from "../store";
import type { ConnectionState } from "../client";

export interface ToolbarCallbacks {
  onRefresh: () => void;
  onToggleLayers: () => void; // requires a re-fetch
}

/** Top toolbar: title, device subtitle, display toggles, zoom, status. */
export class Toolbar {
  readonly el = document.createElement("div");
  private title = document.createElement("div");
  private status = document.createElement("div");
  private toggles: Record<string, HTMLButtonElement> = {};
  private zoomLabel = document.createElement("span");

  constructor(private store: Store, private cb: ToolbarCallbacks) {
    this.el.className = "toolbar";

    const left = document.createElement("div");
    left.className = "toolbar-left";
    this.title.className = "toolbar-title";
    this.title.textContent = "Treescope";
    left.appendChild(this.title);
    this.el.appendChild(left);

    const center = document.createElement("div");
    center.className = "toolbar-center";
    const refresh = button("⟳ Refresh", () => this.cb.onRefresh());
    refresh.classList.add("primary");
    center.appendChild(refresh);

    this.toggles.wireframe = toggle("▦ Wireframe", () => this.opt((o) => { o.showWireframe = !o.showWireframe; }));
    this.toggles.snapshots = toggle("▣ Snapshots", () => this.opt((o) => { o.showSnapshots = !o.showSnapshots; }));
    this.toggles.exploded = toggle("◳ 3D", () => this.opt((o) => { o.exploded = !o.exploded; }));
    this.toggles.layers = toggle("⧉ Layers", () => { this.opt((o) => { o.includeLayers = !o.includeLayers; }); this.cb.onToggleLayers(); });
    this.toggles.hideSystem = toggle("⊘ System", () => this.opt((o) => { o.hideSystem = !o.hideSystem; }));
    for (const t of Object.values(this.toggles)) center.appendChild(t);

    const zoomBox = document.createElement("div");
    zoomBox.className = "zoom-box";
    zoomBox.append(
      button("−", () => this.opt((o) => { o.zoom = Math.max(0.1, o.zoom - 0.2); })),
      this.zoomLabel,
      button("+", () => this.opt((o) => { o.zoom = Math.min(6, o.zoom + 0.2); })),
      button("100%", () => this.opt((o) => { o.zoom = 1; })),
    );
    this.zoomLabel.className = "zoom-label mono";
    center.appendChild(zoomBox);
    this.el.appendChild(center);

    const right = document.createElement("div");
    right.className = "toolbar-right";
    this.status.className = "toolbar-status";
    right.appendChild(this.status);
    this.el.appendChild(right);
  }

  private opt(mutate: (o: Store["state"]["options"]) => void): void {
    this.store.update((s) => mutate(s.options));
  }

  render(): void {
    const { serverInfo, options, snapshot, connection } = this.store.state;
    if (serverInfo) {
      this.title.textContent = serverInfo.device.appName;
      this.title.title = `${serverInfo.device.osName} ${serverInfo.device.osVersion} · ${serverInfo.device.deviceModel}`;
    }
    setActive(this.toggles.wireframe, options.showWireframe);
    setActive(this.toggles.snapshots, options.showSnapshots);
    setActive(this.toggles.exploded, options.exploded);
    setActive(this.toggles.layers, options.includeLayers);
    setActive(this.toggles.hideSystem, options.hideSystem);
    this.zoomLabel.textContent = `${Math.round(options.zoom * 100)}%`;

    const count = snapshot ? `${countNodes(snapshot)} nodes` : "";
    this.status.textContent = `${statusText(connection)}${count ? " · " + count : ""}`;
    this.status.dataset.state = connection;
  }
}

function countNodes(snapshot: { roots: { children: any[] }[] }): number {
  let n = 0;
  const walk = (node: { children: any[] }) => { n++; node.children.forEach(walk); };
  snapshot.roots.forEach(walk);
  return n;
}

function statusText(s: ConnectionState): string {
  switch (s) {
    case "connected": return "● connected";
    case "connecting": return "○ connecting…";
    case "failed": return "● disconnected";
    default: return "○ offline";
  }
}

function button(label: string, onClick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.className = "tb-btn";
  b.textContent = label;
  b.addEventListener("click", onClick);
  return b;
}
function toggle(label: string, onClick: () => void): HTMLButtonElement {
  const b = button(label, onClick);
  b.classList.add("tb-toggle");
  return b;
}
function setActive(b: HTMLButtonElement, on: boolean): void {
  b.classList.toggle("active", on);
}
