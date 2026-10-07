import { invoke } from "@tauri-apps/api/core";

/** Stdio command for Loci's built-in Excalidraw MCP server. */
export type CanvasMcpServer = { command: string; args: string[] };

/** Agents see the official tools under this name, e.g. `mcp__excalidraw__create_view`. */
export const CANVAS_MCP_NAME = "excalidraw";
// The server reaches the session's Loci window with the credential the agent
// CLI already holds; Codex only forwards variables that are listed.
const FORWARDED_ENV = ["LOCI_APP_ENDPOINT", "LOCI_APP_TOKEN"];

export type CanvasMcpTool = "read_me" | "create_view" | "read_widget_context";
const TOOLS: readonly CanvasMcpTool[] = ["read_me", "create_view", "read_widget_context"];

/** Recognize the built-in server's tools as Claude (`mcp__excalidraw__x`) and Codex (`excalidraw:x`) name them. */
export function canvasMcpTool(name: string | undefined): CanvasMcpTool | undefined {
  const match = name?.trim().match(new RegExp(`(?:^|\\s)(?:mcp__${CANVAS_MCP_NAME}__|${CANVAS_MCP_NAME}[:.])([a-z_]+)$`));
  return TOOLS.find((tool) => tool === match?.[1]);
}

/**
 * Whether a call needs no approval prompt. Reading the reference or the
 * project's own drawings never does. Drawing is an edit the canvas pane can
 * undo, so it follows file edits: asked for in Supervised, automatic above it.
 */
export function canvasToolAutoAllowed(tool: CanvasMcpTool, runtimeMode: string): boolean {
  return tool !== "create_view" || runtimeMode !== "supervised";
}

/** The app's reason the server cannot start here, e.g. no Node.js; null when it can. */
export async function canvasMcpProblem(): Promise<string | null> {
  try { await invoke<CanvasMcpServer>("canvas_mcp_server"); return null; }
  // A command failure is the backend's own sentence; anything else is not ours to show.
  catch (error) { return typeof error === "string" ? error : null; }
}

/**
 * The server to add to an agent session, or null when it cannot run. Sessions
 * still start without it; a failure is not cached, so installing Node.js
 * takes effect on the next session.
 */
export async function canvasMcpServer(): Promise<CanvasMcpServer | null> {
  try {
    const server = await invoke<CanvasMcpServer>("canvas_mcp_server");
    return server && typeof server.command === "string" && Array.isArray(server.args) ? server : null;
  } catch { return null; }
}

/** `--mcp-config` value for Claude Code. It adds to the user's own servers. */
export function claudeCanvasMcpConfig(server: CanvasMcpServer): string {
  return JSON.stringify({ mcpServers: { [CANVAS_MCP_NAME]: { type: "stdio", command: server.command, args: server.args } } });
}

/** `-c` overrides for Codex. JSON strings and string arrays are valid TOML values. */
export function codexCanvasMcpArgs(server: CanvasMcpServer): string[] {
  const key = `mcp_servers.${CANVAS_MCP_NAME}`;
  return [
    "-c", `${key}.command=${JSON.stringify(server.command)}`,
    "-c", `${key}.args=${JSON.stringify(server.args)}`,
    "-c", `${key}.env_vars=${JSON.stringify(FORWARDED_ENV)}`,
    // The official server marks drawing read-only, so Codex would never ask.
    // Have it ask Loci, which answers by the session's permission mode.
    "-c", `${key}.tools.create_view.approval_mode="prompt"`,
  ];
}

/** The built-in tool a Codex MCP approval request is about, if it is one. */
export function codexCanvasApprovalTool(params: unknown): CanvasMcpTool | undefined {
  const request = params as { serverName?: unknown; message?: unknown; _meta?: { codex_approval_kind?: unknown } } | null;
  if (request?.serverName !== CANVAS_MCP_NAME || request._meta?.codex_approval_kind !== "mcp_tool_call") return undefined;
  const named = typeof request.message === "string" ? request.message.match(/\btool "([a-z_]+)"/)?.[1] : undefined;
  return TOOLS.find((tool) => tool === named);
}
