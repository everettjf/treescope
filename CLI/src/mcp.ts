import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { connect, fetchSnapshot, ConnectionOptions } from "./discovery.js";
import {
  renderTree, renderNode, renderDevice, findNodes, findNode,
  snapshotSummary, TreeFilter,
} from "./format.js";
import { capabilityNames, AttributeValue } from "./protocol.js";

const VERSION = "0.1.0";

type ToolResult = {
  content: Array<
    | { type: "text"; text: string }
    | { type: "image"; data: string; mimeType: string }
  >;
  isError?: boolean;
};

function textResult(text: string): ToolResult {
  return { content: [{ type: "text", text }] };
}

function errorResult(err: unknown): ToolResult {
  const msg = err instanceof Error ? err.message : String(err);
  return { content: [{ type: "text", text: `Error: ${msg}` }], isError: true };
}

function parseValue(raw: string, type: string): AttributeValue {
  if (type === "string") return { t: "string", v: raw };
  if (type === "bool") return { t: "bool", v: raw === "true" || raw === "1" };
  if (type === "integer") return { t: "integer", v: parseInt(raw, 10) };
  if (type === "number") return { t: "number", v: parseFloat(raw) };
  if (raw === "true" || raw === "false") return { t: "bool", v: raw === "true" };
  if (/^-?\d+$/.test(raw)) return { t: "integer", v: parseInt(raw, 10) };
  if (/^-?\d*\.\d+$/.test(raw)) return { t: "number", v: parseFloat(raw) };
  return { t: "string", v: raw };
}

/**
 * Build the Treescope MCP server. Exposes the runtime view inspector as tools
 * a coding agent can call. Each tool connects to the in-app server fresh,
 * fetches what it needs, and disconnects — robust against the app restarting.
 */
export function buildServer(conn: ConnectionOptions): McpServer {
  const server = new McpServer(
    { name: "treescope", version: VERSION },
    {
      instructions:
        "Inspect a running app's UIKit/AppKit/SwiftUI view hierarchy via Treescope. " +
        "Typical flow: treescope_status to confirm connectivity, treescope_get_tree " +
        "(use a small maxDepth or a filter to stay token-efficient) to see structure, " +
        "treescope_find_nodes to locate something by name/label/text, then " +
        "treescope_inspect_node for one node's full properties. treescope_get_snapshot " +
        "returns a rendered PNG; treescope_set_attribute live-edits an editable property.",
    },
  );

  server.registerTool(
    "treescope_status",
    {
      title: "Treescope: status",
      description:
        "Connect to the running app and report device info (app, OS, device, screen) " +
        "and server capabilities. Use first to confirm an app is reachable.",
      inputSchema: {},
    },
    async (): Promise<ToolResult> => {
      try {
        const { client, info } = await connect(conn);
        client.disconnect();
        const text =
          `Connected to Treescope server v${info.serverVersion} (protocol ${info.protocolVersion}) ` +
          `at ${client.host}:${client.port}\n\n${renderDevice(info.device)}\n\n` +
          `Capabilities: ${capabilityNames(info.capabilities).join(", ") || "none"}`;
        return textResult(text);
      } catch (e) { return errorResult(e); }
    },
  );

  server.registerTool(
    "treescope_get_tree",
    {
      title: "Treescope: get view hierarchy",
      description:
        "Fetch the view hierarchy as a compact one-line-per-node tree. Each line includes " +
        "the node id (#...) to pass to other tools. Keep maxDepth small (default 4) or use a " +
        "filter to avoid flooding context — full hierarchies can be thousands of nodes.",
      inputSchema: {
        maxDepth: z.number().int().min(0).default(4)
          .describe("Maximum depth to print; 0 = unlimited. Default 4."),
        visibleOnly: z.boolean().default(false)
          .describe("Hide hidden / zero-size / fully transparent nodes."),
        hideSystem: z.boolean().default(false)
          .describe("Hide system views (status bar, keyboard internals, etc.)."),
        filter: z.string().optional()
          .describe("Only show subtrees whose name/class/label contains this substring."),
        includeSwiftUI: z.boolean().default(true).describe("Reflect SwiftUI views."),
        includeLayers: z.boolean().default(false).describe("Include CALayers."),
      },
    },
    async (args): Promise<ToolResult> => {
      try {
        const { info, snapshot } = await fetchSnapshot(conn, {
          includeSwiftUI: args.includeSwiftUI,
          includeLayers: args.includeLayers,
          hideSystemViews: args.hideSystem,
        });
        const filter: TreeFilter = {
          maxDepth: args.maxDepth,
          visibleOnly: args.visibleOnly,
          hideSystem: args.hideSystem,
          match: args.filter,
        };
        const body = renderTree(snapshot.roots, filter) || "(no nodes matched)";
        return textResult(`${info.device.appName} — ${snapshotSummary(snapshot)}\n\n${body}`);
      } catch (e) { return errorResult(e); }
    },
  );

  server.registerTool(
    "treescope_inspect_node",
    {
      title: "Treescope: inspect node",
      description:
        "Show all captured properties for one node (geometry plus every attribute section, " +
        "marking which are live-editable and their key path). Pass a node id from treescope_get_tree.",
      inputSchema: {
        nodeID: z.string().describe("Node id, e.g. 'obj:1234' or 'sui:...'."),
      },
    },
    async (args): Promise<ToolResult> => {
      try {
        const { snapshot } = await fetchSnapshot(conn, { includeLayers: true });
        const node = findNode(snapshot.roots, args.nodeID);
        if (!node) {
          return errorResult(`node not found: ${args.nodeID} (it may have changed; re-run treescope_get_tree)`);
        }
        return textResult(renderNode(node));
      } catch (e) { return errorResult(e); }
    },
  );

  server.registerTool(
    "treescope_find_nodes",
    {
      title: "Treescope: find nodes",
      description:
        "Search the hierarchy for nodes by display name, class name, accessibility label, or " +
        "string/enum attribute values (e.g. a label's text). Returns matching node ids and their path.",
      inputSchema: {
        query: z.string().describe("Case-insensitive substring to search for."),
        limit: z.number().int().min(1).max(500).default(25).describe("Max results. Default 25."),
      },
    },
    async (args): Promise<ToolResult> => {
      try {
        const { snapshot } = await fetchSnapshot(conn, { includeLayers: true });
        const results = findNodes(snapshot.roots, args.query, args.limit);
        if (results.length === 0) return textResult(`No nodes match "${args.query}".`);
        const lines = results.map((r) => {
          const label = r.label ? `  "${r.label}"` : "";
          return `#${r.id}  ${r.displayName}${label}  [${r.className}]\n   ${r.path}`;
        });
        return textResult(`${results.length} match(es) for "${args.query}":\n\n${lines.join("\n")}`);
      } catch (e) { return errorResult(e); }
    },
  );

  server.registerTool(
    "treescope_get_snapshot",
    {
      title: "Treescope: get node snapshot (PNG)",
      description:
        "Render a node to a PNG image and return it inline, so a multimodal model can look at it. " +
        "Pass a node id from treescope_get_tree.",
      inputSchema: {
        nodeID: z.string().describe("Node id to render."),
        scale: z.number().min(0.5).max(4).default(2).describe("Render scale. Default 2."),
      },
    },
    async (args): Promise<ToolResult> => {
      try {
        const { client } = await connect(conn);
        try {
          const png = await client.fetchSnapshot(args.nodeID, args.scale);
          return {
            content: [
              { type: "text", text: `Rendered ${args.nodeID} (${png.length} bytes, scale ${args.scale}).` },
              { type: "image", data: png.toString("base64"), mimeType: "image/png" },
            ],
          };
        } finally { client.disconnect(); }
      } catch (e) { return errorResult(e); }
    },
  );

  server.registerTool(
    "treescope_set_attribute",
    {
      title: "Treescope: set attribute (live edit)",
      description:
        "Live-edit an editable attribute on a node (e.g. alpha, isHidden, text). Only attributes " +
        "reported as editable by treescope_inspect_node can be set. Use the key path shown there.",
      inputSchema: {
        nodeID: z.string().describe("Target node id."),
        keyPath: z.string().describe("Attribute key path, e.g. 'alpha' or 'isHidden'."),
        value: z.string().describe("New value as a string; type is inferred unless valueType is set."),
        valueType: z.enum(["auto", "string", "number", "integer", "bool"]).default("auto")
          .describe("Force a value type. Default 'auto' infers from the string."),
      },
    },
    async (args): Promise<ToolResult> => {
      try {
        const av = parseValue(args.value, args.valueType);
        const { client } = await connect(conn);
        try {
          const res = await client.setAttribute(args.nodeID, args.keyPath, av);
          if (res.success) return textResult(`OK: set ${args.keyPath} = ${args.value} on ${args.nodeID}`);
          return errorResult(`server rejected edit: ${res.message ?? "unknown reason"}`);
        } finally { client.disconnect(); }
      } catch (e) { return errorResult(e); }
    },
  );

  return server;
}

/** Start the MCP server on stdio. Resolves when the transport closes. */
export async function runMcpServer(conn: ConnectionOptions): Promise<void> {
  const server = buildServer(conn);
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // The process stays alive while the transport is open; nothing more to do.
}
