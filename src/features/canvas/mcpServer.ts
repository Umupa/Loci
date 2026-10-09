import { invoke } from "@tauri-apps/api/core";
import { loadCanvasMcpEnabled } from "../settings/model/builtinMcp";

/** Stdio command for Loci's built-in Excalidraw MCP server. */
export type CanvasMcpServer = { command: string; args: string[] };

/** Agents see the official tools under this name, e.g. `mcp__loci_excalidraw__create_view`. */
// Reserve an app-owned name: Codex merges config overrides field by field,
// so reusing a user's remote `excalidraw` entry would mix url with command.
export const CANVAS_MCP_NAME = "loci_excalidraw";
// The server reaches the session's Loci window with the credential the agent
// CLI already holds; Codex only forwards variables that are listed.
const FORWARDED_ENV = ["LOCI_APP_ENDPOINT", "LOCI_APP_TOKEN"];

export type CanvasMcpTool = "read_me" | "create_view" | "read_widget_context" | "get_elements" | "update_elements";
export const CANVAS_MCP_TOOLS: readonly CanvasMcpTool[] = ["read_me", "create_view", "read_widget_context", "get_elements", "update_elements"];

/** Recognize the built-in server's tools as Claude (`mcp__loci_excalidraw__x`) and Codex (`loci_excalidraw:x`) name them. */
export function canvasMcpTool(name: string | undefined): CanvasMcpTool | undefined {
  const match = name?.trim().match(new RegExp(`(?:^|\\s)(?:mcp__${CANVAS_MCP_NAME}__|${CANVAS_MCP_NAME}[:.])([a-z_]+)$`));
  return CANVAS_MCP_TOOLS.find((tool) => tool === match?.[1]);
}

/**
 * Whether a call needs no approval prompt. Reading the reference or the
 * project's own drawings never does. Drawing is an edit the canvas pane can
 * undo, so it follows file edits: asked for in Supervised, automatic above it.
 */
export function isCanvasWriteTool(tool: CanvasMcpTool): boolean {
  return tool === "create_view" || tool === "update_elements";
}

export function canvasToolAutoAllowed(tool: CanvasMcpTool, runtimeMode: string): boolean {
  return !isCanvasWriteTool(tool) || runtimeMode !== "supervised";
}

/** The app's reason the server cannot start here, e.g. no Node.js; null when it can. */
export async function canvasMcpProblem(): Promise<string | null> {
  if (!loadCanvasMcpEnabled()) return "The built-in Excalidraw MCP is disabled in Settings → MCP.";
  try { await invoke<CanvasMcpServer>("canvas_mcp_server"); return null; }
  // A command failure is the backend's own sentence; anything else is not ours to show.
  catch (error) { return typeof error === "string" ? error : null; }
}

/**
 * The server to add to an agent session, or null when disabled or unavailable.
 * Providers pass the preference captured for this process so a settings change
 * during startup is picked up on its next turn. Failures are not cached.
 */
export async function canvasMcpServer(enabled = loadCanvasMcpEnabled()): Promise<CanvasMcpServer | null> {
  if (!enabled) return null;
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
    // Explicitly route writing approvals through Loci's permission mode.
    "-c", `${key}.tools.create_view.approval_mode="prompt"`,
    "-c", `${key}.tools.update_elements.approval_mode="prompt"`,
  ];
}

/** The built-in tool a Codex MCP approval request is about, if it is one. */
export function codexCanvasApprovalTool(params: unknown): CanvasMcpTool | undefined {
  const request = params as { serverName?: unknown; message?: unknown; _meta?: { codex_approval_kind?: unknown } } | null;
  if (request?.serverName !== CANVAS_MCP_NAME || request._meta?.codex_approval_kind !== "mcp_tool_call") return undefined;
  const named = typeof request.message === "string" ? request.message.match(/\btool "([a-z_]+)"/)?.[1] : undefined;
  return CANVAS_MCP_TOOLS.find((tool) => tool === named);
}
