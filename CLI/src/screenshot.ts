import { connect, ConnectionOptions } from "./discovery.js";
import {
  DEFAULT_HIERARCHY_OPTIONS, Flag, Rect, ViewNode, DeviceInfo,
} from "./protocol.js";

function area(r: Rect): number {
  return Math.max(0, r.width) * Math.max(0, r.height);
}

/** A node worth trying to render: on-screen, visible, and non-empty. */
function renderable(node: ViewNode): boolean {
  return (node.flags & (Flag.hidden | Flag.zeroSize)) === 0
    && node.opacity > 0.001
    && area(node.frame) > 0;
}

/**
 * Ordered list of node ids to try when capturing the whole screen. Prefers the
 * largest visible root window, then its largest first-level children as a
 * fallback — a UIWindow renders directly on iOS, whereas an NSWindow root is not
 * itself a view, so its contentView (a child) is what actually renders on macOS.
 */
export function pickScreenshotNodes(roots: ViewNode[]): string[] {
  const ids: string[] = [];
  const byAreaDesc = (a: ViewNode, b: ViewNode) => area(b.frame) - area(a.frame);
  const sortedRoots = roots.filter(renderable).sort(byAreaDesc);
  for (const root of sortedRoots) {
    ids.push(root.id);
    const kids = root.children.filter(renderable).sort(byAreaDesc).slice(0, 3);
    for (const k of kids) ids.push(k.id);
  }
  return [...new Set(ids)];
}

export interface ScreenCapture {
  png: Buffer;
  nodeID: string;        // the node that actually rendered
  device: DeviceInfo;
}

/**
 * Capture a PNG of the current screen in one round-trip. Fetches the hierarchy,
 * picks the best renderable root (see {@link pickScreenshotNodes}), and renders
 * the first candidate that produces an image. SwiftUI reflection is skipped — we
 * only need view geometry to choose what to render, which keeps it fast.
 */
export async function captureScreen(
  conn: ConnectionOptions,
  scale: number,
): Promise<ScreenCapture> {
  const { client, info } = await connect(conn);
  try {
    const snapshot = await client.fetchHierarchy({
      ...DEFAULT_HIERARCHY_OPTIONS,
      includeSwiftUI: false,
      includeLayers: false,
    });
    const candidates = pickScreenshotNodes(snapshot.roots);
    if (candidates.length === 0) {
      throw new Error("no visible on-screen window to capture (is the app foregrounded?)");
    }
    let lastErr: unknown;
    for (const id of candidates) {
      try {
        const png = await client.fetchSnapshot(id, scale);
        return { png, nodeID: id, device: info.device };
      } catch (e) { lastErr = e; }
    }
    const reason = lastErr instanceof Error ? lastErr.message : String(lastErr);
    throw new Error(`could not capture the screen (tried ${candidates.length} root node(s)): ${reason}`);
  } finally {
    client.disconnect();
  }
}
