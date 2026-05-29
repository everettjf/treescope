# Treescope Web Viewer

The browser viewer for [Treescope](../README.md). **React + TypeScript + Tailwind CSS +
shadcn/ui (Radix primitives)**, built with Vite. Bundles to a single self-contained HTML embedded
into `TreescopeServer` so the inspected app serves it with zero external files.

## Develop

```bash
npm install
npm run dev      # vite dev server with HMR
```

The viewer connects to `location.host`, so for live data run a Treescope-embedding app and open its
own `http://127.0.0.1:47761` after `npm run release` (the dev server has no backend of its own).

## Build & embed

```bash
npm run build    # tsc --noEmit + vite build → dist/index.html (single self-contained file)
npm run embed    # copy dist/index.html → ../Sources/TreescopeServer/Resources/viewer.html
npm run release  # build + embed in one step
```

## Stack

- **React 18** — component model.
- **Tailwind CSS** + **shadcn/ui** (new-york style) on **Radix UI** primitives — `src/components/ui/`.
- **lucide-react** — icons.
- **chart.js** / **react-chartjs-2** — available for stats panels (wired into deps).
- **vite-plugin-singlefile** — inlines JS+CSS into one HTML for embedding.

## Layout

| File | Role |
|---|---|
| `src/protocol.ts` | Wire types + helpers mirroring `Sources/TreescopeProtocol`. The `t`-discriminated JSON shapes match the Swift custom `Codable`. |
| `src/client.ts` | WebSocket client; correlates responses by envelope id, exposes typed requests + the snapshot HTTP URL. |
| `src/store.ts` | Pure state helpers: node index, ancestor paths, filtering, flat visible list, colors. |
| `src/hooks/useInspector.ts` | The app's state hook: connection lifecycle (with retry), selection, expand, options, live editing, keyboard move. |
| `src/components/Tree.tsx` | Hierarchy sidebar: search + match highlight, hover↔canvas sync, scroll-to-selected. |
| `src/components/Canvas.tsx` | Visual canvas: wireframe + snapshot + exploded 3D, zoom/pan/select, hover. |
| `src/components/Inspector.tsx` | Property inspector with typed rendering + live editing (color picker, switches, text). |
| `src/components/Toolbar.tsx` | Toolbar: toggles, zoom, connection status, node count. |
| `src/components/ui/` | shadcn/ui components (button, toggle, switch, input, tooltip, badge, slider, tabs). |
| `src/App.tsx` / `src/main.tsx` | Layout, splitters, global keyboard nav (↑/↓/←/→, ⌘R). |
