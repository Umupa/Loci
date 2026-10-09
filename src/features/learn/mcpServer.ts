import { invoke } from "@tauri-apps/api/core";
import { CANVAS_MCP_NAME, type CanvasMcpServer } from "../canvas/mcpServer";

/** Agents see the learning tools under this name, e.g. `mcp__loci_learn__map_read`. */
export const LEARN_MCP_NAME = "loci_learn";
// The server reaches the session's Loci window with the credential the agent
// CLI already holds; Codex only forwards variables that are listed.
const FORWARDED_ENV = ["LOCI_APP_ENDPOINT", "LOCI_APP_TOKEN"];

export type LearnMcpTool = "map_read" | "map_init" | "map_sketch" | "map_record" | "revisit";
export const LEARN_MCP_TOOLS: readonly LearnMcpTool[] = ["map_read", "map_init", "map_sketch", "map_record", "revisit"];

/** Recognize the learning server's tools as Claude (`mcp__loci_learn__x`) and Codex (`loci_learn:x`) name them. */
export function learnMcpTool(name: string | undefined): LearnMcpTool | undefined {
  const match = name?.trim().match(new RegExp(`(?:^|\\s)(?:mcp__${LEARN_MCP_NAME}__|${LEARN_MCP_NAME}[:.])([a-z_]+)$`));
  return LEARN_MCP_TOOLS.find((tool) => tool === match?.[1]);
}

export function isLearnWriteTool(tool: LearnMcpTool): boolean {
  return tool !== "map_read";
}

/**
 * Learning tools never prompt outside a plan turn, in any permission mode:
 * each write is narrow, checked against the learner's own words by the host,
 * and undoable in the map's pane. A plan turn may only read.
 */
export function learnToolAllowed(tool: LearnMcpTool, planning: boolean): boolean {
  return !planning || !isLearnWriteTool(tool);
}

/** The app's reason the server cannot start here, e.g. no Node.js; null when it can. */
export async function learnMcpProblem(): Promise<string | null> {
  try { await invoke<CanvasMcpServer>("learn_mcp_server"); return null; }
  catch (error) { return typeof error === "string" ? error : null; }
}

/** The server to add to a session that used /learn, or null when it cannot run here. */
export async function learnMcpServer(): Promise<CanvasMcpServer | null> {
  try {
    const server = await invoke<CanvasMcpServer>("learn_mcp_server");
    return server && typeof server.command === "string" && Array.isArray(server.args) ? server : null;
  } catch { return null; }
}

/** `--mcp-config` value for Claude Code with Loci's built-in servers. It adds to the user's own servers. */
export function claudeBuiltinMcpConfig(canvas: CanvasMcpServer | null, learn: CanvasMcpServer | null): string | undefined {
  const entry = (server: CanvasMcpServer) => ({ type: "stdio", command: server.command, args: server.args });
  if (!canvas && !learn) return undefined;
  return JSON.stringify({ mcpServers: { ...(canvas ? { [CANVAS_MCP_NAME]: entry(canvas) } : {}), ...(learn ? { [LEARN_MCP_NAME]: entry(learn) } : {}) } });
}

/** `-c` overrides for Codex. JSON strings and string arrays are valid TOML values. */
export function codexLearnMcpArgs(server: CanvasMcpServer): string[] {
  const key = `mcp_servers.${LEARN_MCP_NAME}`;
  return [
    "-c", `${key}.command=${JSON.stringify(server.command)}`,
    "-c", `${key}.args=${JSON.stringify(server.args)}`,
    "-c", `${key}.env_vars=${JSON.stringify(FORWARDED_ENV)}`,
    // Route write approvals to Loci, which accepts them outside plan turns.
    ...LEARN_MCP_TOOLS.filter(isLearnWriteTool).flatMap((tool) => ["-c", `${key}.tools.${tool}.approval_mode="prompt"`]),
  ];
}

/** The learning tool a Codex MCP approval request is about, if it is one. */
export function codexLearnApprovalTool(params: unknown): LearnMcpTool | undefined {
  const request = params as { serverName?: unknown; message?: unknown; _meta?: { codex_approval_kind?: unknown } } | null;
  if (request?.serverName !== LEARN_MCP_NAME || request._meta?.codex_approval_kind !== "mcp_tool_call") return undefined;
  const named = typeof request.message === "string" ? request.message.match(/\btool "([a-z_]+)"/)?.[1] : undefined;
  return LEARN_MCP_TOOLS.find((tool) => tool === named);
}
