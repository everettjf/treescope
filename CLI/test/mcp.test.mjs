import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { startMockServer } from "./mock-server.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "..", "dist", "index.js");

let server, client, transport;

before(async () => {
  server = await startMockServer();
  transport = new StdioClientTransport({
    command: "node",
    args: [CLI, "--port", String(server.port), "--timeout", "4000", "mcp"],
  });
  client = new Client({ name: "treescope-test", version: "0.0.0" });
  await client.connect(transport);
});

after(async () => {
  await client?.close();
  await server?.close();
});

function textOf(result) {
  return (result.content ?? []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
}

test("initialize + tools/list exposes all tools with schemas", async () => {
  const { tools } = await client.listTools();
  const names = tools.map((t) => t.name).sort();
  assert.deepEqual(names, [
    "treescope_find_nodes",
    "treescope_get_snapshot",
    "treescope_get_tree",
    "treescope_inspect_node",
    "treescope_set_attribute",
    "treescope_status",
  ]);
  const tree = tools.find((t) => t.name === "treescope_get_tree");
  assert.ok(tree.description?.length > 10);
  assert.equal(tree.inputSchema.type, "object");
  assert.ok(tree.inputSchema.properties.maxDepth);
});

test("treescope_status returns device info", async () => {
  const r = await client.callTool({ name: "treescope_status", arguments: {} });
  assert.ok(!r.isError);
  assert.match(textOf(r), /MockApp/);
  assert.match(textOf(r), /Capabilities: .*swiftUI/);
});

test("treescope_get_tree returns a compact tree with ids", async () => {
  const r = await client.callTool({ name: "treescope_get_tree", arguments: { maxDepth: 0 } });
  assert.ok(!r.isError);
  const t = textOf(r);
  assert.match(t, /5 nodes total/);
  assert.match(t, /#obj:4/);
  assert.match(t, /LoginButton/);
});

test("treescope_get_tree honors filter", async () => {
  const r = await client.callTool({ name: "treescope_get_tree", arguments: { filter: "login" } });
  const t = textOf(r);
  assert.match(t, /LoginButton/);
  assert.doesNotMatch(t, /UILabel/);
});

test("treescope_find_nodes finds by text", async () => {
  const r = await client.callTool({ name: "treescope_find_nodes", arguments: { query: "Welcome" } });
  assert.ok(!r.isError);
  assert.match(textOf(r), /#obj:3/);
});

test("treescope_inspect_node returns attributes; missing node is an error", async () => {
  const ok = await client.callTool({ name: "treescope_inspect_node", arguments: { nodeID: "obj:3" } });
  assert.ok(!ok.isError);
  assert.match(textOf(ok), /editable: text/);

  const bad = await client.callTool({ name: "treescope_inspect_node", arguments: { nodeID: "obj:missing" } });
  assert.equal(bad.isError, true);
  assert.match(textOf(bad), /not found/);
});

test("treescope_get_snapshot returns inline PNG image content", async () => {
  const r = await client.callTool({ name: "treescope_get_snapshot", arguments: { nodeID: "obj:3" } });
  assert.ok(!r.isError);
  const image = r.content.find((c) => c.type === "image");
  assert.ok(image, "expected an image content block");
  assert.equal(image.mimeType, "image/png");
  const bytes = Buffer.from(image.data, "base64");
  assert.deepEqual([...bytes.subarray(0, 4)], [0x89, 0x50, 0x4e, 0x47]);
});

test("treescope_set_attribute succeeds on known and errors on unknown node", async () => {
  const ok = await client.callTool({
    name: "treescope_set_attribute",
    arguments: { nodeID: "obj:4", keyPath: "alpha", value: "0.5" },
  });
  assert.ok(!ok.isError);
  assert.match(textOf(ok), /OK: set alpha/);

  const bad = await client.callTool({
    name: "treescope_set_attribute",
    arguments: { nodeID: "obj:nope", keyPath: "alpha", value: "0.5" },
  });
  assert.equal(bad.isError, true);
});

test("a missing required argument surfaces as an error (not a silent success)", async () => {
  // The SDK may either reject the call or return an isError result depending on
  // schema enforcement; either way it must not look like a successful inspect.
  const outcome = await client
    .callTool({ name: "treescope_inspect_node", arguments: {} })
    .then((r) => ({ thrown: null, result: r }), (e) => ({ thrown: e, result: null }));
  if (outcome.thrown) {
    assert.match(String(outcome.thrown), /nodeID|required|invalid|expected/i);
  } else {
    assert.equal(outcome.result.isError, true);
    assert.doesNotMatch(textOf(outcome.result), /editable: text/);
  }
});
