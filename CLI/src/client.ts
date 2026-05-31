import WebSocket from "ws";
import {
  ClientMessage, ServerMessage, ServerEnvelope, ServerEvent,
  ServerInfo, HierarchySnapshot, HierarchyOptions, AttributeValue,
  PROTOCOL_VERSION,
} from "./protocol.js";

/**
 * Node WebSocket client to the in-app Treescope server, correlating
 * responses to requests by envelope `id`. Server-pushed events use id 0.
 *
 * Mirrors the browser client in `Web/src/client.ts`.
 */
export class Client {
  private ws?: WebSocket;
  private nextId = 1;
  private pending = new Map<number, {
    resolve: (m: ServerMessage) => void;
    reject: (e: Error) => void;
    timer?: NodeJS.Timeout;
  }>();

  onEvent: (event: ServerEvent) => void = () => {};
  onClose: () => void = () => {};

  constructor(
    readonly host: string,
    readonly port: number,
    private readonly clientName = "Treescope CLI",
    private readonly clientVersion = "0.1.0",
  ) {}

  get httpBase(): string {
    return `http://${this.host}:${this.port}`;
  }

  connect(timeoutMs = 8000): Promise<void> {
    return new Promise((resolve, reject) => {
      let settled = false;
      const ws = new WebSocket(`ws://${this.host}:${this.port}/ws`);
      this.ws = ws;
      const timer = setTimeout(() => {
        if (!settled) { settled = true; ws.terminate(); reject(new Error("connection timed out")); }
      }, timeoutMs);
      ws.on("open", () => { settled = true; clearTimeout(timer); resolve(); });
      ws.on("error", (err) => {
        if (!settled) { settled = true; clearTimeout(timer); reject(err instanceof Error ? err : new Error(String(err))); }
      });
      ws.on("close", () => {
        for (const p of this.pending.values()) { if (p.timer) clearTimeout(p.timer); p.reject(new Error("connection closed")); }
        this.pending.clear();
        this.onClose();
      });
      ws.on("message", (data) => this.handleMessage(data.toString()));
    });
  }

  disconnect(): void {
    this.ws?.close();
    this.ws = undefined;
  }

  private handleMessage(data: string): void {
    let envelope: ServerEnvelope;
    try { envelope = JSON.parse(data) as ServerEnvelope; } catch { return; }
    if (envelope.id === 0) {
      if (envelope.message.t === "event") this.onEvent(envelope.message.event);
      return;
    }
    const waiter = this.pending.get(envelope.id);
    if (waiter) {
      this.pending.delete(envelope.id);
      if (waiter.timer) clearTimeout(waiter.timer);
      waiter.resolve(envelope.message);
    }
  }

  private send(message: ClientMessage, timeoutMs = 30_000): Promise<ServerMessage> {
    return new Promise((resolve, reject) => {
      const ws = this.ws;
      if (!ws || ws.readyState !== WebSocket.OPEN) { reject(new Error("not connected")); return; }
      const id = this.nextId++;
      const timer = timeoutMs > 0
        ? setTimeout(() => { if (this.pending.delete(id)) reject(new Error("request timed out")); }, timeoutMs)
        : undefined;
      this.pending.set(id, { resolve, reject, timer });
      ws.send(JSON.stringify({ id, message }));
    });
  }

  async handshake(): Promise<ServerInfo> {
    const r = await this.send({
      t: "handshake",
      client: { name: this.clientName, version: this.clientVersion, protocolVersion: PROTOCOL_VERSION },
    });
    if (r.t === "handshakeAck") return r.info;
    throw new Error(r.t === "error" ? r.message : "unexpected handshake response");
  }

  async fetchHierarchy(options: HierarchyOptions): Promise<HierarchySnapshot> {
    const r = await this.send({ t: "fetchHierarchy", options });
    if (r.t === "hierarchy") return r.snapshot;
    throw new Error(r.t === "error" ? r.message : "unexpected hierarchy response");
  }

  async setAttribute(nodeID: string, keyPath: string, value: AttributeValue): Promise<{ success: boolean; message?: string | null }> {
    const r = await this.send({ t: "setAttribute", nodeID, keyPath, value });
    if (r.t === "attributeResult") return { success: r.success, message: r.message };
    throw new Error(r.t === "error" ? r.message : "unexpected setAttribute response");
  }

  async highlight(nodeID: string | null): Promise<void> {
    await this.send({ t: "highlight", nodeID });
  }

  /** HTTP URL for a node's rendered snapshot PNG. */
  snapshotURL(nodeID: string, scale = 2): string {
    return `${this.httpBase}/snapshot/${encodeURIComponent(nodeID)}?scale=${scale}`;
  }

  /** Fetch a node's rendered snapshot PNG over HTTP. */
  async fetchSnapshot(nodeID: string, scale = 2): Promise<Buffer> {
    const res = await fetch(this.snapshotURL(nodeID, scale));
    if (!res.ok) throw new Error(`snapshot request failed (HTTP ${res.status})`);
    return Buffer.from(await res.arrayBuffer());
  }
}
