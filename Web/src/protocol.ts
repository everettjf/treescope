// Wire types mirroring `Sources/TreescopeProtocol`. Messages use a `t`
// discriminator with flat fields (see the Swift custom Codable).

export interface Point { x: number; y: number; }
export interface Size { width: number; height: number; }
export interface Rect { x: number; y: number; width: number; height: number; }
export interface RGBAColor { red: number; green: number; blue: number; alpha: number; }
export interface EdgeInsets { top: number; left: number; bottom: number; right: number; }
export interface Transform3D { m: number[]; }

export type AttributeValue =
  | { t: "string"; v: string }
  | { t: "number"; v: number }
  | { t: "integer"; v: number }
  | { t: "bool"; v: boolean }
  | { t: "enum"; v: string }
  | { t: "color"; v: RGBAColor }
  | { t: "point"; v: Point }
  | { t: "size"; v: Size }
  | { t: "rect"; v: Rect }
  | { t: "insets"; v: EdgeInsets }
  | { t: "reference"; v: string }
  | { t: "null" }
  | { t: "image"; w: number; h: number }
  | { t: "nested"; v: Attribute[] };

export interface Attribute {
  id: string;
  title: string;
  value: AttributeValue;
  editable: boolean;
  keyPath?: string | null;
}

export interface AttributeSection {
  id: string;
  title: string;
  attributes: Attribute[];
}

export type ViewKind =
  | "window" | "uiView" | "uiViewController" | "caLayer"
  | "nsView" | "nsViewController" | "nsWindow"
  | "swiftUI" | "hostingView" | "other";

export interface ViewNode {
  id: string;
  kind: ViewKind;
  className: string;
  displayName: string;
  label?: string | null;
  frame: Rect;
  bounds: Rect;
  opacity: number;
  flags: number;
  zIndex: number;
  transform?: Transform3D | null;
  sections: AttributeSection[];
  snapshotID?: string | null;
  children: ViewNode[];
}

export interface DeviceInfo {
  appName: string;
  bundleID: string;
  processName: string;
  osName: string;
  osVersion: string;
  deviceModel: string;
  deviceName: string;
  screenSize: Size;
  screenScale: number;
  isSimulator: boolean;
}

export interface ServerInfo {
  device: DeviceInfo;
  serverVersion: string;
  protocolVersion: number;
  capabilities: number;
}

export interface HierarchySnapshot {
  device: DeviceInfo;
  roots: ViewNode[];
  timestamp: number;
  serverVersion: string;
}

export interface HierarchyOptions {
  includeSwiftUI: boolean;
  includeLayers: boolean;
  hideSystemViews: boolean;
  requestSnapshots: boolean;
  maxDepth: number;
}

// Bit flags matching ViewFlags.
export const Flag = {
  hidden: 1 << 0,
  clipsToBounds: 1 << 1,
  userInteraction: 1 << 2,
  systemView: 1 << 3,
  hostsSwiftUI: 1 << 4,
  hasSnapshot: 1 << 5,
  zeroSize: 1 << 6,
  offscreen: 1 << 7,
} as const;

export function hasFlag(node: ViewNode, flag: number): boolean {
  return (node.flags & flag) !== 0;
}

// Capability bits matching ServerInfo.Capabilities.
export const Capability = {
  snapshots: 1 << 0,
  liveEditing: 1 << 1,
  swiftUI: 1 << 2,
  highlighting: 1 << 3,
  pushUpdates: 1 << 4,
} as const;

// Envelopes.
export interface ClientEnvelope { id: number; message: ClientMessage; }
export interface ServerEnvelope { id: number; message: ServerMessage; }

export type ClientMessage =
  | { t: "handshake"; client: { name: string; version: string; protocolVersion: number } }
  | { t: "fetchHierarchy"; options: HierarchyOptions }
  | { t: "fetchSnapshot"; nodeID: string; scale: number }
  | { t: "setAttribute"; nodeID: string; keyPath: string; value: AttributeValue }
  | { t: "highlight"; nodeID?: string | null }
  | { t: "ping" };

export type ServerMessage =
  | { t: "handshakeAck"; info: ServerInfo }
  | { t: "hierarchy"; snapshot: HierarchySnapshot }
  | { t: "snapshot"; image: unknown }
  | { t: "attributeResult"; nodeID: string; keyPath: string; success: boolean; message?: string | null }
  | { t: "event"; event: ServerEvent }
  | { t: "error"; code: number; message: string }
  | { t: "pong" };

export type ServerEvent =
  | { t: "hierarchyChanged" }
  | { t: "willDisconnect"; reason: string }
  | { t: "log"; message: string };

// CSS color from an RGBAColor (components 0..1).
export function cssColor(c: RGBAColor): string {
  const to255 = (v: number) => Math.round(Math.max(0, Math.min(1, v)) * 255);
  return `rgba(${to255(c.red)}, ${to255(c.green)}, ${to255(c.blue)}, ${c.alpha.toFixed(3)})`;
}

export function hexColor(c: RGBAColor): string {
  const h = (v: number) => to2(Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16));
  const to2 = (s: string) => (s.length < 2 ? "0" + s : s);
  return c.alpha >= 1
    ? `#${h(c.red)}${h(c.green)}${h(c.blue)}`.toUpperCase()
    : `#${h(c.red)}${h(c.green)}${h(c.blue)}${h(c.alpha)}`.toUpperCase();
}

// Compact display string for an attribute value.
export function displayValue(v: AttributeValue): string {
  switch (v.t) {
    case "string": return v.v;
    case "number": return Number.isInteger(v.v) ? v.v.toFixed(1) : String(+v.v.toPrecision(6));
    case "integer": return String(v.v);
    case "bool": return v.v ? "true" : "false";
    case "enum": return v.v;
    case "reference": return v.v;
    case "null": return "nil";
    case "color": return hexColor(v.v);
    case "point": return `(${v.v.x.toFixed(1)}, ${v.v.y.toFixed(1)})`;
    case "size": return `${v.v.width.toFixed(1)} × ${v.v.height.toFixed(1)}`;
    case "rect": return `{${v.v.x.toFixed(1)}, ${v.v.y.toFixed(1)}, ${v.v.width.toFixed(1)}, ${v.v.height.toFixed(1)}}`;
    case "insets": return `(${v.v.top.toFixed(0)}, ${v.v.left.toFixed(0)}, ${v.v.bottom.toFixed(0)}, ${v.v.right.toFixed(0)})`;
    case "image": return `Image ${v.w}×${v.h}`;
    case "nested": return `{ ${v.v.length} }`;
  }
}
