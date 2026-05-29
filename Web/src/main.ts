import "./styles.css";
import { Client } from "./client";
import { Store } from "./store";
import { TreeView } from "./ui/tree";
import { CanvasView } from "./ui/canvas";
import { Inspector } from "./ui/inspector";
import { Toolbar } from "./ui/toolbar";
import type { AttributeValue, HierarchyOptions } from "./protocol";

const store = new Store();
const client = new Client();

function currentOptions(): HierarchyOptions {
  const o = store.state.options;
  return {
    includeSwiftUI: true,
    includeLayers: o.includeLayers,
    hideSystemViews: false, // hiding is done client-side so toggling is instant
    requestSnapshots: true,
    maxDepth: 0,
  };
}

async function refresh(): Promise<void> {
  if (store.state.connection !== "connected") return;
  store.update((s) => { s.refreshing = true; s.error = undefined; });
  try {
    const snapshot = await client.fetchHierarchy(currentOptions());
    store.setSnapshot(snapshot);
    store.autoExpand(3);
  } catch (e) {
    store.update((s) => { s.error = String(e); });
  } finally {
    store.update((s) => { s.refreshing = false; });
  }
}

function select(id: string): void {
  store.update((s) => {
    s.selectedID = id;
    for (const a of store.pathTo(id)) s.expanded.add(a);
  });
  void client.highlight(id);
}

// UI wiring.
const toolbar = new Toolbar(store, { onRefresh: refresh, onToggleLayers: refresh });
const tree = new TreeView(store, select);
const canvas = new CanvasView(store, select, (id) => client.snapshotURL(id));
const inspector = new Inspector(store, edit);

function edit(nodeID: string, keyPath: string, value: AttributeValue): void {
  client.setAttribute(nodeID, keyPath, value).then((ok) => { if (ok) void refresh(); });
}

function layout(): void {
  const app = document.getElementById("app")!;
  app.className = "app";
  const body = document.createElement("div");
  body.className = "app-body";
  const sidebar = panel("sidebar", tree.el);
  const center = panel("center", canvas.el);
  const detail = panel("detail", inspector.el);
  body.append(sidebar, makeSplitter(sidebar), center, makeSplitter(detail, true), detail);
  app.append(toolbar.el, body);
}

function panel(kind: string, child: HTMLElement): HTMLElement {
  const p = document.createElement("div");
  p.className = `panel panel-${kind}`;
  p.appendChild(child);
  return p;
}

// Simple draggable splitter that resizes the adjacent panel.
function makeSplitter(panelEl: HTMLElement, fromRight = false): HTMLElement {
  const s = document.createElement("div");
  s.className = "splitter";
  let startX = 0, startW = 0, active = false;
  s.addEventListener("pointerdown", (e) => {
    active = true; startX = e.clientX; startW = panelEl.getBoundingClientRect().width;
    s.setPointerCapture(e.pointerId);
  });
  s.addEventListener("pointermove", (e) => {
    if (!active) return;
    const delta = fromRight ? startX - e.clientX : e.clientX - startX;
    panelEl.style.width = `${Math.max(200, Math.min(700, startW + delta))}px`;
    canvas.render();
  });
  s.addEventListener("pointerup", () => { active = false; });
  return s;
}

let scheduled = false;
function renderAll(): void {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    toolbar.render();
    tree.render();
    canvas.render();
    inspector.render();
  });
}

store.subscribe(renderAll);

client.onState = (state, detail) => {
  store.update((s) => { s.connection = state; if (detail) s.error = detail; });
};
client.onEvent = (event) => {
  if (event.t === "hierarchyChanged") void refresh();
  if (event.t === "willDisconnect") client.disconnect();
};

async function boot(): Promise<void> {
  layout();
  renderAll();
  try {
    await client.connect();
    store.update((s) => { s.serverInfo = undefined; });
    const info = await client.handshake();
    store.update((s) => { s.serverInfo = info; });
    await refresh();
  } catch (e) {
    store.update((s) => { s.error = String(e); s.connection = "failed"; });
    // Retry a couple of times — the app may still be coming up.
    setTimeout(() => { if (store.state.connection !== "connected") void boot(); }, 2000);
  }
}

window.addEventListener("resize", () => canvas.render());
void boot();
