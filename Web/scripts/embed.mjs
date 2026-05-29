// Copies the built single-file viewer into the Swift package resources so the
// in-app server can serve it via `Bundle.module`. Run after `vite build`.
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, "../dist/index.html");
const dest = resolve(here, "../../Sources/TreescopeServer/Resources/viewer.html");

if (!existsSync(src)) {
  console.error(`[embed] build output not found: ${src}\nRun "npm run build" first.`);
  process.exit(1);
}
mkdirSync(dirname(dest), { recursive: true });
copyFileSync(src, dest);
console.log(`[embed] viewer.html -> ${dest}`);
