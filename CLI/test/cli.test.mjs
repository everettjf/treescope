import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { readFile, rm } from "node:fs/promises";
import { startMockServer } from "./mock-server.mjs";

const execFileP = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "..", "dist", "index.js");

let server;

before(async () => { server = await startMockServer(); });
after(async () => { await server?.close(); });

/** Run the CLI; returns {code, stdout, stderr}. Never throws on non-zero exit. */
async function run(args) {
  try {
    const { stdout, stderr } = await execFileP("node", [CLI, "--port", String(server.port), "--timeout", "4000", ...args]);
    return { code: 0, stdout, stderr };
  } catch (e) {
    return { code: e.code ?? 1, stdout: e.stdout ?? "", stderr: e.stderr ?? "" };
  }
}

test("status reports the mock device and capabilities", async () => {
  const { code, stdout } = await run(["status"]);
  assert.equal(code, 0);
  assert.match(stdout, /MockApp/);
  assert.match(stdout, /iOS 18\.2/);
  assert.match(stdout, /Capabilities: .*liveEditing/);
});

test("status --json emits valid JSON ServerInfo", async () => {
  const { code, stdout } = await run(["--json", "status"]);
  assert.equal(code, 0);
  const info = JSON.parse(stdout);
  assert.equal(info.device.appName, "MockApp");
  assert.equal(info.protocolVersion, 1);
});

test("tree prints the hierarchy with node ids", async () => {
  const { code, stdout } = await run(["tree"]);
  assert.equal(code, 0);
  assert.match(stdout, /5 nodes total/);
  assert.match(stdout, /#obj:4/);
  assert.match(stdout, /LoginButton/);
});

test("tree --depth limits output", async () => {
  const { stdout } = await run(["tree", "--depth", "2"]);
  assert.match(stdout, /depth limit/);
  assert.doesNotMatch(stdout, /UILabel/);
});

test("tree --filter narrows to a subtree", async () => {
  const { stdout } = await run(["tree", "--filter", "login"]);
  assert.match(stdout, /LoginButton/);
  assert.doesNotMatch(stdout, /UILabel/);
});

test("tree --json round-trips a HierarchySnapshot", async () => {
  const { stdout } = await run(["--json", "tree"]);
  const snap = JSON.parse(stdout);
  assert.equal(snap.roots[0].id, "obj:1");
  assert.equal(snap.roots[0].children[0].children.length, 3);
});

test("find locates nodes by text and reports paths", async () => {
  const { code, stdout } = await run(["find", "Welcome"]);
  assert.equal(code, 0);
  assert.match(stdout, /#obj:3/);
  assert.match(stdout, /UIWindow › RootView › UILabel/);
});

test("find --json returns an array", async () => {
  const { stdout } = await run(["--json", "find", "button"]);
  const arr = JSON.parse(stdout);
  assert.ok(Array.isArray(arr));
  assert.equal(arr[0].id, "obj:4");
});

test("inspect shows attributes and editable key paths", async () => {
  const { code, stdout } = await run(["inspect", "obj:3"]);
  assert.equal(code, 0);
  assert.match(stdout, /\[Text\]/);
  assert.match(stdout, /editable: text/);
});

test("inspect of a missing node exits non-zero", async () => {
  const { code, stderr } = await run(["inspect", "obj:does-not-exist"]);
  assert.equal(code, 1);
  assert.match(stderr, /node not found/);
});

test("snapshot saves a PNG file", async () => {
  const out = join(HERE, "_tmp_snapshot.png");
  await rm(out, { force: true });
  const { code } = await run(["snapshot", "obj:3", "-o", out]);
  assert.equal(code, 0);
  const png = await readFile(out);
  assert.deepEqual([...png.subarray(0, 4)], [0x89, 0x50, 0x4e, 0x47]); // PNG signature
  await rm(out, { force: true });
});

test("set succeeds on a known node", async () => {
  const { code, stdout } = await run(["set", "obj:4", "alpha", "0.5"]);
  assert.equal(code, 0);
  assert.match(stdout, /OK: set alpha = 0\.5/);
});

test("set fails on an unknown node", async () => {
  const { code, stderr } = await run(["set", "obj:nope", "alpha", "0.5"]);
  assert.equal(code, 1);
  assert.match(stderr, /rejected|unknown/i);
});

test("explicit --port miss yields a clear error", async () => {
  // A port with nothing listening.
  const { stdout, stderr } = await execFileP(
    "node", [CLI, "--port", "1", "--timeout", "1500", "status"],
  ).then(
    (r) => ({ ...r, code: 0 }),
    (e) => ({ stdout: e.stdout ?? "", stderr: e.stderr ?? "", code: e.code ?? 1 }),
  );
  assert.equal(stdout, "");
  assert.match(stderr, /No Treescope server responding/);
});
