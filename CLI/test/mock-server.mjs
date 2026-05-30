// A self-contained mock of the in-app Treescope server, implementing the wire
// protocol (HTTP /healthz + /snapshot, and the WebSocket JSON message protocol)
// well enough to drive the CLI and MCP server in tests deterministically.
import http from "node:http";
import { WebSocketServer } from "ws";

// 1x1 transparent PNG.
const PNG_1x1 = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
  "base64",
);

const DEVICE = {
  appName: "MockApp",
  bundleID: "com.example.MockApp",
  processName: "MockApp",
  osName: "iOS",
  osVersion: "18.2",
  deviceModel: "iPhone17,1",
  deviceName: "Mock iPhone",
  screenSize: { width: 393, height: 852 },
  screenScale: 3,
  isSimulator: true,
};

const node = (id, displayName, className, frame, children = [], extra = {}) => ({
  id, kind: extra.kind ?? "uiView", className, displayName,
  label: extra.label ?? null,
  frame, bounds: { x: 0, y: 0, width: frame.width, height: frame.height },
  opacity: extra.opacity ?? 1, flags: extra.flags ?? 0, zIndex: 0, transform: null,
  sections: extra.sections ?? [], snapshotID: extra.snap ? id : null, children,
});

export function mockHierarchy() {
  return [
    node("obj:1", "UIWindow", "UIWindow", { x: 0, y: 0, width: 393, height: 852 }, [
      node("obj:2", "RootView", "UIView", { x: 0, y: 0, width: 393, height: 852 }, [
        node("obj:3", "UILabel", "UILabel", { x: 16, y: 60, width: 200, height: 24 }, [], {
          label: "Welcome back",
          snap: true,
          sections: [{
            id: "text", title: "Text", attributes: [
              { id: "a1", title: "text", value: { t: "string", v: "Welcome back" }, editable: true, keyPath: "text" },
              { id: "a2", title: "textColor", value: { t: "color", v: { red: 0, green: 0, blue: 0, alpha: 1 } }, editable: true, keyPath: "textColor" },
              { id: "a3", title: "numberOfLines", value: { t: "integer", v: 1 }, editable: false, keyPath: null },
            ],
          }],
        }),
        node("obj:4", "LoginButton", "UIButton", { x: 16, y: 200, width: 358, height: 48 }, [], {
          label: "Log In", opacity: 0.5, flags: 1, snap: true,
          sections: [{
            id: "layout", title: "Layout", attributes: [
              { id: "b1", title: "alpha", value: { t: "number", v: 0.5 }, editable: true, keyPath: "alpha" },
              { id: "b2", title: "isHidden", value: { t: "bool", v: true }, editable: true, keyPath: "isHidden" },
            ],
          }],
        }),
        node("obj:5", "UIImageView", "UIImageView", { x: 0, y: 0, width: 0, height: 0 }, [], { flags: 64 }),
      ]),
    ]),
  ];
}

const SERVER_INFO = {
  device: DEVICE,
  serverVersion: "0.1.0",
  protocolVersion: 1,
  // snapshots|liveEditing|swiftUI|highlighting|pushUpdates = 31
  capabilities: 31,
};

/** Start the mock server. Returns { port, url, close() }. */
export function startMockServer({ port = 0 } = {}) {
  const httpServer = http.createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname === "/healthz") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("ok");
    } else if (url.pathname.startsWith("/snapshot/")) {
      res.writeHead(200, { "content-type": "image/png" });
      res.end(PNG_1x1);
    } else {
      res.writeHead(404);
      res.end("not found");
    }
  });

  const wss = new WebSocketServer({ server: httpServer, path: "/ws" });
  wss.on("connection", (ws) => {
    ws.on("message", (raw) => {
      let env;
      try { env = JSON.parse(raw.toString()); } catch { return; }
      const reply = (message) => ws.send(JSON.stringify({ id: env.id, message }));
      const m = env.message;
      switch (m?.t) {
        case "handshake":
          reply({ t: "handshakeAck", info: SERVER_INFO });
          break;
        case "fetchHierarchy":
          reply({
            t: "hierarchy",
            snapshot: { device: DEVICE, roots: mockHierarchy(), timestamp: 1, serverVersion: "0.1.0" },
          });
          break;
        case "setAttribute": {
          // Reject unknown nodes, accept known ones.
          const known = ["obj:1", "obj:2", "obj:3", "obj:4", "obj:5"].includes(m.nodeID);
          reply({
            t: "attributeResult", nodeID: m.nodeID, keyPath: m.keyPath,
            success: known, message: known ? null : "unknown node",
          });
          break;
        }
        case "highlight":
          // No response payload defined; emit a pong-like ack via event id 0 noop.
          break;
        case "ping":
          reply({ t: "pong" });
          break;
        default:
          reply({ t: "error", code: 1, message: `unsupported message: ${m?.t}` });
      }
    });
  });

  return new Promise((resolve) => {
    httpServer.listen(port, "127.0.0.1", () => {
      const actual = httpServer.address().port;
      resolve({
        port: actual,
        url: `http://127.0.0.1:${actual}`,
        close: () => new Promise((r) => { wss.close(); httpServer.close(() => r()); }),
      });
    });
  });
}
