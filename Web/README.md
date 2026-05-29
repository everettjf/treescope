# Treescope Web Viewer

The browser viewer for [Treescope](../README.md). TypeScript + Vite, **no UI framework** — the
tree, canvas (wireframe + snapshot + exploded 3D), and property inspector are plain DOM + CSS.

## Develop

```bash
npm install
npm run dev      # vite dev server with HMR
```

The dev server proxies nothing — to talk to a real app, the viewer connects to `location.host`,
so run it from the embedded build (below) when you need live data, or point a browser at the app's
own `http://127.0.0.1:47761` after `npm run release`.

## Build & embed

```bash
npm run build    # tsc --noEmit + vite build → dist/index.html (single self-contained file)
npm run embed    # copy dist/index.html → ../Sources/TreescopeServer/Resources/viewer.html
npm run release  # build + embed in one step
```

## Layout

| File | Role |
|---|---|
| `src/protocol.ts` | Wire types + helpers mirroring `Sources/TreescopeProtocol`. The `t`-discriminated JSON shapes match the Swift custom `Codable`. |
| `src/client.ts` | WebSocket client; correlates responses by envelope id, exposes typed requests + the snapshot HTTP URL. |
| `src/store.ts` | Observable state container: snapshot index, selection, expand set, filtering, display options. |
| `src/ui/tree.ts` | Hierarchy sidebar with search + filtering. |
| `src/ui/canvas.ts` | Visual canvas: wireframe + snapshot + exploded 3D, zoom/pan/select. |
| `src/ui/inspector.ts` | Property inspector with typed rendering + live editing. |
| `src/ui/toolbar.ts` | Top toolbar: toggles, zoom, connection status. |
| `src/main.ts` | Wires it together; connection lifecycle + render loop. |
