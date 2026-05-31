import { Client } from "./client.js";
import {
  DEFAULT_PORT, PORT_SCAN_COUNT, LOOPBACK_HOST,
  HierarchyOptions, DEFAULT_HIERARCHY_OPTIONS, HierarchySnapshot, ServerInfo,
} from "./protocol.js";

export interface ConnectionOptions {
  host: string;
  port?: number;       // explicit port; if omitted, scan
  timeoutMs: number;
}

/** Probe a single port's /healthz endpoint; resolves true if a server answers "ok". */
async function probe(host: string, port: number, timeoutMs: number): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`http://${host}:${port}/healthz`, { signal: controller.signal });
    if (!res.ok) return false;
    const body = await res.text();
    return body.trim() === "ok";
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Resolve a reachable server port. If an explicit port is given, only that is
 * probed. Otherwise scans [DEFAULT_PORT, DEFAULT_PORT + PORT_SCAN_COUNT).
 */
export async function discoverPort(opts: ConnectionOptions): Promise<number> {
  const host = opts.host;
  if (opts.port !== undefined) {
    if (await probe(host, opts.port, opts.timeoutMs)) return opts.port;
    throw new Error(`No Treescope server responding at ${host}:${opts.port}. Is the app running with Treescope.start()?`);
  }
  const ports = Array.from({ length: PORT_SCAN_COUNT }, (_, i) => DEFAULT_PORT + i);
  const results = await Promise.all(ports.map(async (p) => ((await probe(host, p, opts.timeoutMs)) ? p : -1)));
  const found = results.filter((p) => p >= 0).sort((a, b) => a - b);
  if (found.length === 0) {
    throw new Error(
      `No Treescope server found on ${host}:${DEFAULT_PORT}-${DEFAULT_PORT + PORT_SCAN_COUNT - 1}.\n` +
      `  - Make sure the app is running with Treescope.start() (DEBUG builds).\n` +
      `  - For a physical device, forward the port over USB: iproxy ${DEFAULT_PORT} ${DEFAULT_PORT}\n` +
      `  - Or pass --port explicitly.`,
    );
  }
  return found[0];
}

export interface Connected {
  client: Client;
  info: ServerInfo;
}

/** Discover, connect and handshake. Caller is responsible for client.disconnect(). */
export async function connect(opts: ConnectionOptions): Promise<Connected> {
  const port = await discoverPort(opts);
  const client = new Client(opts.host, port);
  await client.connect(opts.timeoutMs);
  const info = await client.handshake();
  return { client, info };
}

/** Convenience: connect, fetch one hierarchy snapshot, disconnect. */
export async function fetchSnapshot(
  opts: ConnectionOptions,
  hierarchyOptions: Partial<HierarchyOptions> = {},
): Promise<{ info: ServerInfo; snapshot: HierarchySnapshot }> {
  const { client, info } = await connect(opts);
  try {
    const snapshot = await client.fetchHierarchy({ ...DEFAULT_HIERARCHY_OPTIONS, ...hierarchyOptions });
    return { info, snapshot };
  } finally {
    client.disconnect();
  }
}

export { LOOPBACK_HOST };
