#!/usr/bin/env node
import { Command, Option } from "commander";
import { writeFile } from "node:fs/promises";
import { connect, fetchSnapshot, ConnectionOptions } from "./discovery.js";
import {
  renderTree, renderNode, renderDevice, findNodes, findNode,
  snapshotSummary, TreeFilter,
} from "./format.js";
import { LOOPBACK_HOST, capabilityNames, AttributeValue, DEFAULT_PORT } from "./protocol.js";

const VERSION = "0.1.0";

const program = new Command();
program
  .name("treescope")
  .description("Command-line client for the Treescope runtime view inspector.\nInspect a running app's UIKit / AppKit / SwiftUI hierarchy from a shell or a coding agent.")
  .version(VERSION)
  .option("--host <host>", "server host", LOOPBACK_HOST)
  .option("-p, --port <port>", "server port (default: auto-discover starting at " + DEFAULT_PORT + ")", (v) => parseInt(v, 10))
  .option("--timeout <ms>", "network timeout in milliseconds", (v) => parseInt(v, 10), 8000)
  .option("--json", "emit machine-readable JSON instead of formatted text", false);

function connectionOptions(): ConnectionOptions {
  const o = program.opts();
  return { host: o.host, port: o.port, timeoutMs: o.timeout };
}

function isJSON(): boolean {
  return program.opts().json === true;
}

function fail(err: unknown): never {
  const msg = err instanceof Error ? err.message : String(err);
  if (isJSON()) console.error(JSON.stringify({ error: msg }));
  else console.error(`treescope: ${msg}`);
  process.exit(1);
}

// ── status ────────────────────────────────────────────────────────────────
program
  .command("status")
  .description("Connect to the running app and print device info + capabilities")
  .action(async () => {
    try {
      const { client, info } = await connect(connectionOptions());
      client.disconnect();
      if (isJSON()) { console.log(JSON.stringify(info, null, 2)); return; }
      console.log(`Connected to Treescope server v${info.serverVersion} (protocol ${info.protocolVersion}) at ${client.host}:${client.port}\n`);
      console.log(renderDevice(info.device));
      console.log(`\nCapabilities: ${capabilityNames(info.capabilities).join(", ") || "none"}`);
    } catch (e) { fail(e); }
  });

// ── tree ──────────────────────────────────────────────────────────────────
program
  .command("tree")
  .description("Print the view hierarchy as a compact tree")
  .option("-d, --depth <n>", "maximum depth to print (0 = unlimited)", (v) => parseInt(v, 10), 0)
  .option("--visible-only", "hide hidden / zero-size / fully transparent nodes", false)
  .option("--no-system", "hide system views")
  .option("--filter <text>", "only show subtrees matching this substring (name/class/label)")
  .option("--no-swiftui", "do not reflect SwiftUI views")
  .option("--layers", "include CALayers", false)
  .action(async (opts) => {
    try {
      const { info, snapshot } = await fetchSnapshot(connectionOptions(), {
        includeSwiftUI: opts.swiftui !== false,
        includeLayers: opts.layers === true,
        hideSystemViews: opts.system === false,
      });
      if (isJSON()) { console.log(JSON.stringify(snapshot, null, 2)); return; }
      const filter: TreeFilter = {
        maxDepth: opts.depth ?? 0,
        visibleOnly: opts.visibleOnly === true,
        hideSystem: opts.system === false,
        match: opts.filter,
      };
      console.log(`${info.device.appName} — ${snapshotSummary(snapshot)}\n`);
      console.log(renderTree(snapshot.roots, filter));
    } catch (e) { fail(e); }
  });

// ── inspect ─────────────────────────────────────────────────────────────────
program
  .command("inspect <nodeID>")
  .description("Show all properties/attributes for a single node")
  .action(async (nodeID: string) => {
    try {
      const { snapshot } = await fetchSnapshot(connectionOptions(), { includeLayers: true });
      const node = findNode(snapshot.roots, nodeID);
      if (!node) fail(`node not found: ${nodeID} (it may have changed; re-run \`treescope tree\`)`);
      if (isJSON()) { console.log(JSON.stringify(node, null, 2)); return; }
      console.log(renderNode(node!));
    } catch (e) { fail(e); }
  });

// ── find ────────────────────────────────────────────────────────────────────
program
  .command("find <query>")
  .description("Search nodes by class name, display name, label, or text content")
  .option("-n, --limit <n>", "maximum results", (v) => parseInt(v, 10), 50)
  .action(async (query: string, opts) => {
    try {
      const { snapshot } = await fetchSnapshot(connectionOptions(), { includeLayers: true });
      const results = findNodes(snapshot.roots, query, opts.limit);
      if (isJSON()) { console.log(JSON.stringify(results, null, 2)); return; }
      if (results.length === 0) { console.log(`No nodes match "${query}".`); return; }
      console.log(`${results.length} match(es) for "${query}":\n`);
      for (const r of results) {
        const label = r.label ? `  "${r.label}"` : "";
        console.log(`  #${r.id}  ${r.displayName}${label}  [${r.className}]`);
        console.log(`     ${r.path}`);
      }
    } catch (e) { fail(e); }
  });

// ── snapshot ─────────────────────────────────────────────────────────────────
program
  .command("snapshot <nodeID>")
  .description("Save a rendered PNG of a node")
  .option("-s, --scale <n>", "render scale", (v) => parseFloat(v), 2)
  .option("-o, --output <file>", "output file path", "snapshot.png")
  .action(async (nodeID: string, opts) => {
    try {
      const { client } = await connect(connectionOptions());
      try {
        const png = await client.fetchSnapshot(nodeID, opts.scale);
        await writeFile(opts.output, png);
        if (isJSON()) console.log(JSON.stringify({ output: opts.output, bytes: png.length }));
        else console.log(`Saved ${png.length} bytes to ${opts.output}`);
      } finally { client.disconnect(); }
    } catch (e) { fail(e); }
  });

// ── set ──────────────────────────────────────────────────────────────────────
program
  .command("set <nodeID> <keyPath> <value>")
  .description("Live-edit an editable attribute (e.g. `set <id> alpha 0.5`)")
  .addOption(new Option("-t, --type <type>", "value type").choices(["auto", "string", "number", "integer", "bool"]).default("auto"))
  .action(async (nodeID: string, keyPath: string, value: string, opts) => {
    try {
      const av = parseValue(value, opts.type);
      const { client } = await connect(connectionOptions());
      try {
        const res = await client.setAttribute(nodeID, keyPath, av);
        if (isJSON()) { console.log(JSON.stringify(res)); }
        else if (res.success) console.log(`OK: set ${keyPath} = ${value}`);
        else fail(`server rejected edit: ${res.message ?? "unknown reason"}`);
      } finally { client.disconnect(); }
    } catch (e) { fail(e); }
  });

// ── mcp ──────────────────────────────────────────────────────────────────────
program
  .command("mcp")
  .description("Run as a Model Context Protocol (MCP) server over stdio, exposing the inspector as tools for coding agents")
  .action(async () => {
    try {
      const { runMcpServer } = await import("./mcp.js");
      await runMcpServer(connectionOptions());
    } catch (e) { fail(e); }
  });

function parseValue(raw: string, type: string): AttributeValue {
  if (type === "string") return { t: "string", v: raw };
  if (type === "bool") return { t: "bool", v: raw === "true" || raw === "1" };
  if (type === "integer") return { t: "integer", v: parseInt(raw, 10) };
  if (type === "number") return { t: "number", v: parseFloat(raw) };
  // auto
  if (raw === "true" || raw === "false") return { t: "bool", v: raw === "true" };
  if (/^-?\d+$/.test(raw)) return { t: "integer", v: parseInt(raw, 10) };
  if (/^-?\d*\.\d+$/.test(raw)) return { t: "number", v: parseFloat(raw) };
  return { t: "string", v: raw };
}

program.parseAsync(process.argv).catch(fail);
