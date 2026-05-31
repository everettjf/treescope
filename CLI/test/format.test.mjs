import { test } from "node:test";
import assert from "node:assert/strict";
import {
  renderTree, renderNode, findNodes, findNode, countNodes, snapshotSummary, renderDevice,
} from "../dist/format.js";
import { displayValue, hexColor, capabilityNames, hasFlag, Flag } from "../dist/protocol.js";
import { mockHierarchy } from "./mock-server.mjs";

const roots = mockHierarchy();

test("countNodes counts the whole tree", () => {
  assert.equal(countNodes(roots), 5);
});

test("renderTree renders one line per node with ids and frames", () => {
  const out = renderTree(roots, { maxDepth: 0, visibleOnly: false, hideSystem: false });
  const lines = out.split("\n");
  assert.equal(lines.length, 5);
  assert.match(out, /UIWindow {2}·/);
  assert.match(out, /#obj:3/);
  assert.match(out, /"Welcome back"/);
  // displayName, then label, then class (shown when it differs from displayName)
  assert.match(out, /LoginButton {2}"Log In" {2}UIButton/);
  // flag + opacity annotations
  assert.match(out, /hidden α0\.50/);
  // tree glyphs present
  assert.match(out, /└─|├─/);
});

test("renderTree --visible-only drops hidden and zero-size nodes", () => {
  const out = renderTree(roots, { maxDepth: 0, visibleOnly: true, hideSystem: false });
  assert.doesNotMatch(out, /LoginButton/); // hidden (flag 1) + alpha 0.5
  assert.doesNotMatch(out, /UIImageView/); // zero size (flag 64)
  assert.match(out, /UILabel/);
});

test("renderTree connectors reflect rendered siblings, not raw children", () => {
  // RootView has 3 children but only UILabel is visible; it must be the last
  // child (└─), with no dangling vertical connector before it.
  const out = renderTree(roots, { maxDepth: 0, visibleOnly: true, hideSystem: false });
  assert.match(out, /└─ UILabel/);
  assert.doesNotMatch(out, /├─ UILabel/);
  assert.doesNotMatch(out, /│.*UILabel/);
});

test("renderTree --filter keeps matches and their ancestors", () => {
  const out = renderTree(roots, { maxDepth: 0, visibleOnly: false, hideSystem: false, match: "login" });
  assert.match(out, /LoginButton/);
  assert.match(out, /UIWindow/);   // ancestor retained
  assert.match(out, /RootView/);   // ancestor retained
  assert.doesNotMatch(out, /UILabel/); // non-matching sibling dropped
});

test("renderTree --depth limits and notes elided children", () => {
  const out = renderTree(roots, { maxDepth: 2, visibleOnly: false, hideSystem: false });
  assert.match(out, /UIWindow/);
  assert.match(out, /RootView/);
  assert.doesNotMatch(out, /UILabel/); // depth 3 not printed
  assert.match(out, /depth limit/);
});

test("findNodes matches by class, label and attribute text", () => {
  assert.equal(findNodes(roots, "LoginButton", 50).length, 1);
  assert.equal(findNodes(roots, "welcome back", 50).length, 1); // label + attr text
  const byClass = findNodes(roots, "UILabel", 50);
  assert.equal(byClass[0].id, "obj:3");
  assert.equal(byClass[0].path, "UIWindow › RootView › UILabel");
});

test("findNodes respects the limit", () => {
  assert.equal(findNodes(roots, "ui", 2).length, 2);
});

test("findNode locates a node by id, undefined when missing", () => {
  assert.equal(findNode(roots, "obj:4")?.displayName, "LoginButton");
  assert.equal(findNode(roots, "nope"), undefined);
});

test("renderNode shows sections and marks editable key paths", () => {
  const out = renderNode(findNode(roots, "obj:3"));
  assert.match(out, /\[Text\]/);
  assert.match(out, /text +Welcome back +\(editable: text\)/);
  assert.match(out, /numberOfLines +1/);
  assert.doesNotMatch(out, /numberOfLines.*editable/); // not editable
  assert.match(out, /snapshot: available/);
});

test("displayValue formats typed values", () => {
  assert.equal(displayValue({ t: "bool", v: true }), "true");
  assert.equal(displayValue({ t: "integer", v: 3 }), "3");
  assert.equal(displayValue({ t: "rect", v: { x: 1, y: 2, width: 3, height: 4 } }), "{1.0, 2.0, 3.0, 4.0}");
  assert.equal(displayValue({ t: "null" }), "nil");
  assert.equal(displayValue({ t: "size", v: { width: 10, height: 20 } }), "10.0 x 20.0");
});

test("hexColor renders with and without alpha", () => {
  assert.equal(hexColor({ red: 1, green: 0, blue: 0, alpha: 1 }), "#FF0000");
  assert.equal(hexColor({ red: 0, green: 0, blue: 0, alpha: 0.5 }), "#00000080");
});

test("capabilityNames decodes the bitset", () => {
  const names = capabilityNames(31);
  assert.deepEqual(names.sort(), ["highlighting", "liveEditing", "pushUpdates", "snapshots", "swiftUI"].sort());
});

test("hasFlag reads ViewFlags bits", () => {
  const hidden = findNode(roots, "obj:4");
  assert.ok(hasFlag(hidden, Flag.hidden));
  assert.ok(!hasFlag(hidden, Flag.systemView));
});

test("snapshotSummary and renderDevice produce readable text", () => {
  const summary = snapshotSummary({ roots, device: {}, timestamp: 0, serverVersion: "x" });
  assert.match(summary, /1 root\(s\), 5 nodes total/);
  const dev = renderDevice({
    appName: "A", bundleID: "b", processName: "A", osName: "iOS", osVersion: "1",
    deviceModel: "m", deviceName: "n", screenSize: { width: 1, height: 2 }, screenScale: 3, isSimulator: true,
  });
  assert.match(dev, /Simulator/);
  assert.match(dev, /1 x 2 @3x/);
});
