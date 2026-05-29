import type {
  ClientMessage, ServerMessage, ServerEnvelope, ServerEvent,
  ServerInfo, HierarchySnapshot, HierarchyOptions, AttributeValue,
} from "./protocol";

export type ConnectionState = "disconnected" | "connecting" | "connected" | "failed";

/** WebSocket client to the in-app Treescope server, correlating responses by id. */
export class Client {
  private ws?: WebSocket;
  private nextId = 1;
  private pending = new Map<number, { resolve: (m: ServerMessage) => void; reject: (e: Error) => void }>();

  onState: (state: ConnectionState, detail?: string) => void = () => {};
  onEvent: (event: ServerEvent) => void = () => {};

  get url(): string {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    // Served by the in-app server itself, so same-origin is the right target.
    return `${proto}//${location.host}/ws`;
  }

  connect(): Promise<void> {
    this.onState("connecting");
    return new Promise((resolve, reject) => {
      let settled = false;
      const ws = new WebSocket(this.url);
      this.ws = ws;
      ws.onopen = () => { settled = true; this.onState("connected"); resolve(); };
      ws.onerror = () => {
        if (!settled) { settled = true; this.onState("failed", "connection error"); reject(new Error("ws error")); }
      };
      ws.onclose = () => {
        this.onState("disconnected");
        for (const p of this.pending.values()) p.reject(new Error("connection closed"));
        this.pending.clear();
      };
      ws.onmessage = (ev) => this.handleMessage(ev.data);
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
      waiter.resolve(envelope.message);
    }
  }

  private send(message: ClientMessage, timeoutMs = 30_000): Promise<ServerMessage> {
    return new Promise((resolve, reject) => {
      const ws = this.ws;
      if (!ws || ws.readyState !== WebSocket.OPEN) { reject(new Error("not connected")); return; }
      const id = this.nextId++;
      this.pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, message }));
      if (timeoutMs > 0) {
        setTimeout(() => {
          if (this.pending.delete(id)) reject(new Error("request timed out"));
        }, timeoutMs);
      }
    });
  }

  async handshake(): Promise<ServerInfo> {
    const r = await this.send({ t: "handshake", client: { name: "Treescope Web", version: "0.1.0", protocolVersion: 1 } });
    if (r.t === "handshakeAck") return r.info;
    throw new Error(r.t === "error" ? r.message : "unexpected handshake response");
  }

  async fetchHierarchy(options: HierarchyOptions): Promise<HierarchySnapshot> {
    const r = await this.send({ t: "fetchHierarchy", options });
    if (r.t === "hierarchy") return r.snapshot;
    throw new Error(r.t === "error" ? r.message : "unexpected hierarchy response");
  }

  async setAttribute(nodeID: string, keyPath: string, value: AttributeValue): Promise<boolean> {
    const r = await this.send({ t: "setAttribute", nodeID, keyPath, value });
    return r.t === "attributeResult" ? r.success : false;
  }

  async highlight(nodeID: string | null): Promise<void> {
    await this.send({ t: "highlight", nodeID });
  }

  /** HTTP URL for a node's rendered snapshot PNG. */
  snapshotURL(nodeID: string, scale = 2): string {
    return `${location.protocol}//${location.host}/snapshot/${encodeURIComponent(nodeID)}?scale=${scale}`;
  }
}
