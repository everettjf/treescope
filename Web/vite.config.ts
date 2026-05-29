import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// Builds the entire viewer into a single self-contained `dist/index.html`
// (inlined JS + CSS), which `scripts/embed.mjs` copies into the Swift package
// resources so the in-app server can serve it with zero external files.
export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    target: "es2020",
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    chunkSizeWarningLimit: 100_000,
    reportCompressedSize: false,
  },
});
