import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { RuntimeMode, TurnIntent } from "../../../../features/sessions/model/session";
import type { HarnessEvent } from "../../core/types";

const sent: string[] = [];
const spawned: string[][] = [];
let onLine: ((line: string) => void) | undefined;

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../core/child", () => ({
  resolveClaudeBinary: async () => ({ path: "/fake/claude" }),
  spawnChild: async (_id: string, _path: string, args: string[]) => { spawned.push(args); },
  killChild: async () => undefined,
  unwatchChild: () => undefined,
  watchChild: (_id: string, line: (l: string) => void) => { onLine = line; },
  writeChild: vi.fn(async (_id: string, line: string) => { sent.push(line); }),
}));

const { sendClaudeTurn, stopClaudeSession, __claudeTestReset } = await import("./claude");
const { buildClaudeSpawnArgs } = await import("./claudeProtocol");

const server = { command: "/usr/bin/node", args: ["/Applications/Loci.app/Contents/Resources/resources/excalidraw-mcp/loci-bridge.mjs"] };
const parse = () => sent.map((line) => JSON.parse(line) as Record<string, any>);
const emit = (rec: Record<string, unknown>) => onLine!(JSON.stringify(rec));
const waitFor = async (pred: () => boolean, label: string) => {
  for (let i = 0; i < 200; i++) {
    if (pred()) return;
    await new Promise((r) => setTimeout(r, 5));
  }
  throw new Error(`timed out waiting for ${label}; sent=${JSON.stringify(parse())}`);
};

async function startTurn(options: { runtimeMode?: RuntimeMode; intent?: TurnIntent } = {}) {
  const events: HarnessEvent[] = [];
  const turn = sendClaudeTurn({
    sessionId: "s1", cwd: "/repo", model: "claude:claude-sonnet-5", modelSettings: {},
    runtimeMode: options.runtimeMode ?? "supervised", intent: options.intent,
    text: "draw the architecture", attachments: [], onEvent: (event) => events.push(event),
  });
  await waitFor(() => parse().some((m) => m.request?.subtype === "initialize"), "initialize");
  emit({ type: "system", subtype: "init", session_id: "sess_1" });
  emit({ type: "control_response", response: { subtype: "success", request_id: "loci_1" } });
  await waitFor(() => parse().some((m) => m.type === "user"), "user prompt");
  return { events, turn };
}

/** What Loci answers when Claude Code asks whether a tool may run. */
async function decisionFor(toolName: string, events: HarnessEvent[]) {
  const requestId = `permission_${toolName}_${sent.length}`;
  emit({ type: "control_request", request_id: requestId, request: { subtype: "can_use_tool", tool_name: toolName, tool_use_id: `use_${toolName}`, input: { elements: "[]" } } });
  await new Promise((r) => setTimeout(r, 30));
  const response = parse().find((message) => message.response?.request_id === requestId);
  if (response) return response.response.response.behavior as string;
  return events.some((event) => event.type === "approval.requested" && event.callId === `use_${toolName}`) ? "ask" : "pending";
}

beforeEach(() => {
  sent.length = 0;
  spawned.length = 0;
  __claudeTestReset();
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "canvas_mcp_server") return server;
    return undefined;
  });
});
afterEach(async () => { await stopClaudeSession("s1"); });

describe("Loci's Excalidraw MCP server in Claude Code sessions", () => {
  it("is added to an interactive session beside the user's own servers", async () => {
    const { turn } = await startTurn();
    const args = spawned[0];
    expect(args).not.toContain("--strict-mcp-config");
    const config = JSON.parse(args[args.indexOf("--mcp-config") + 1]);
    expect(config).toEqual({ mcpServers: { loci_excalidraw: { type: "stdio", ...server } } });
    // The session credential stays in the environment, never in arguments.
    expect(args.join(" ")).not.toContain("LOCI_APP_TOKEN");
    emit({ type: "result", subtype: "success", session_id: "sess_1" });
    await turn;
  });

  it("starts the session without it when no runtime can run the server", async () => {
    vi.mocked(invoke).mockRejectedValue(new Error("Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH."));
    const { turn } = await startTurn();
    expect(spawned[0]).not.toContain("--mcp-config");
    emit({ type: "result", subtype: "success", session_id: "sess_1" });
    await turn;
  });

  it("never reaches Loci's own helper calls", () => {
    const args = buildClaudeSpawnArgs({ isolated: true, mcpConfig: '{"mcpServers":{"loci_excalidraw":{}}}' });
    expect(args.filter((arg) => arg === "--mcp-config")).toHaveLength(1);
    expect(args[args.indexOf("--mcp-config") + 1]).toBe('{"mcpServers":{}}');
  });

  it.each([
    ["supervised", "mcp__loci_excalidraw__read_me", "allow"],
    ["supervised", "mcp__loci_excalidraw__read_widget_context", "allow"],
    // Drawing changes the user's canvas: asked for where edits are asked for.
    ["supervised", "mcp__loci_excalidraw__create_view", "ask"],
    ["auto-accept-edits", "mcp__loci_excalidraw__create_view", "allow"],
    ["auto", "mcp__loci_excalidraw__create_view", "allow"],
    ["full-access", "mcp__loci_excalidraw__create_view", "allow"],
    // Other servers, including a user's own Excalidraw connector, keep asking.
    ["auto-accept-edits", "mcp__claude_ai_Excalidraw__create_view", "ask"],
    ["auto-accept-edits", "mcp__excalidraw__create_view", "ask"],
    ["auto-accept-edits", "mcp__loci_excalidraw__export_to_excalidraw", "ask"],
    ["supervised", "mcp__github__read_me", "ask"],
  ] as const)("in %s mode answers %s with %s", async (runtimeMode, tool, expected) => {
    const { events, turn } = await startTurn({ runtimeMode });
    expect(await decisionFor(tool, events)).toBe(expected);
    await stopClaudeSession("s1");
    await turn.catch(() => undefined);
  });

  it("keeps a plan turn read-only: the drawing can be read but not changed", async () => {
    const { events, turn } = await startTurn({ runtimeMode: "full-access", intent: "plan" });
    expect(await decisionFor("mcp__loci_excalidraw__read_widget_context", events)).toBe("allow");
    expect(await decisionFor("mcp__loci_excalidraw__create_view", events)).toBe("deny");
    await stopClaudeSession("s1");
    await turn.catch(() => undefined);
  });
});
