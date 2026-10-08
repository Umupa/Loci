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

const canvas = { command: "/usr/bin/node", args: ["/opt/Loci/resources/excalidraw-mcp/loci-bridge.mjs"] };
const learn = { command: "/usr/bin/node", args: ["/opt/Loci/resources/learn-mcp/loci-learn.mjs"] };
const parse = () => sent.map((line) => JSON.parse(line) as Record<string, any>);
const emit = (rec: Record<string, unknown>) => onLine!(JSON.stringify(rec));
const finish = () => emit({ type: "result", subtype: "success", session_id: "sess_1" });
const waitFor = async (pred: () => boolean, label: string) => {
  for (let i = 0; i < 200; i++) {
    if (pred()) return;
    await new Promise((r) => setTimeout(r, 5));
  }
  throw new Error(`timed out waiting for ${label}; sent=${JSON.stringify(parse())}`);
};
const servers = (args: string[]) => args.includes("--mcp-config") ? Object.keys(JSON.parse(args[args.indexOf("--mcp-config") + 1]).mcpServers) : [];

async function startTurn(options: { runtimeMode?: RuntimeMode; intent?: TurnIntent; learnAccess?: boolean } = {}) {
  const offset = sent.length;
  const messages = () => parse().slice(offset);
  const events: HarnessEvent[] = [];
  const turn = sendClaudeTurn({
    sessionId: "s1", cwd: "/learn/kubernetes", model: "claude:claude-sonnet-5", modelSettings: {},
    runtimeMode: options.runtimeMode ?? "supervised", intent: options.intent,
    ...(options.learnAccess === undefined ? {} : { learnAccess: options.learnAccess }),
    text: "kubernetes", attachments: [], onEvent: (event) => events.push(event),
  });
  await waitFor(() => messages().some((m) => m.request?.subtype === "initialize" || m.type === "user"), "initialize or prompt");
  if (messages().some((m) => m.request?.subtype === "initialize")) {
    emit({ type: "system", subtype: "init", session_id: "sess_1" });
    emit({ type: "control_response", response: { subtype: "success", request_id: messages().find((m) => m.request?.subtype === "initialize")!.request_id } });
  }
  await waitFor(() => messages().some((m) => m.type === "user"), "user prompt");
  return { events, turn };
}

/** What Loci answers when Claude Code asks whether a tool may run. */
async function decisionFor(toolName: string, events: HarnessEvent[]) {
  const requestId = `permission_${toolName}_${sent.length}`;
  emit({ type: "control_request", request_id: requestId, request: { subtype: "can_use_tool", tool_name: toolName, tool_use_id: `use_${toolName}`, input: {} } });
  await new Promise((r) => setTimeout(r, 30));
  const response = parse().find((message) => message.response?.request_id === requestId);
  if (response) return response.response.response.behavior as string;
  return events.some((event) => event.type === "approval.requested" && event.callId === `use_${toolName}`) ? "ask" : "pending";
}

beforeEach(() => {
  vi.mocked(invoke).mockReset();
  const storage = new Map<string, string>();
  vi.stubGlobal("localStorage", { getItem: (key: string) => storage.get(key) ?? null, setItem: (key: string, value: string) => storage.set(key, value) });
  sent.length = 0;
  spawned.length = 0;
  __claudeTestReset();
  vi.mocked(invoke).mockImplementation(async (command) => command === "canvas_mcp_server" ? canvas : command === "learn_mcp_server" ? learn : undefined);
});
afterEach(async () => { await stopClaudeSession("s1"); vi.unstubAllGlobals(); });

describe("Loci's learning MCP server in Claude Code sessions", () => {
  it("is attached only to a thread that used /learn, beside the drawing server", async () => {
    const plain = await startTurn({ learnAccess: false });
    expect(servers(spawned[0])).toEqual(["loci_excalidraw"]);
    expect(invoke).not.toHaveBeenCalledWith("learn_mcp_server");
    finish();
    await plain.turn;
    // The thread starts learning: the next turn restarts with the server and resumes the conversation.
    const learning = await startTurn({ learnAccess: true });
    expect(spawned).toHaveLength(2);
    const args = spawned[1];
    expect(JSON.parse(args[args.indexOf("--mcp-config") + 1])).toEqual({ mcpServers: { loci_excalidraw: { type: "stdio", ...canvas }, loci_learn: { type: "stdio", ...learn } } });
    expect(args[args.indexOf("--resume") + 1]).toBe("sess_1");
    expect(args.join(" ")).not.toContain("LOCI_APP_TOKEN");
    finish();
    await learning.turn;
    // Later learning turns reuse the process, and so does a caller that does not say.
    const next = await startTurn({ learnAccess: true });
    finish();
    await next.turn;
    const unspecified = await startTurn();
    finish();
    await unspecified.turn;
    expect(spawned).toHaveLength(2);
  });

  it("starts the session without it when no runtime can run the server", async () => {
    vi.mocked(invoke).mockImplementation(async (command) => {
      if (command === "canvas_mcp_server") return canvas;
      if (command === "learn_mcp_server") throw "The learning map needs Node.js 20.11 or newer (or Bun) on your PATH.";
      return undefined;
    });
    const { turn } = await startTurn({ learnAccess: true });
    expect(servers(spawned[0])).toEqual(["loci_excalidraw"]);
    finish();
    await turn;
  });

  it.each(["supervised", "auto-accept-edits", "auto", "full-access"] as const)("never asks before a learning tool in %s mode", async (runtimeMode) => {
    const { events, turn } = await startTurn({ runtimeMode, learnAccess: true });
    for (const tool of ["map_read", "map_init", "map_sketch", "map_record", "revisit"])
      expect(await decisionFor(`mcp__loci_learn__${tool}`, events), tool).toBe("allow");
    // Another server with the same tool names keeps asking.
    if (runtimeMode === "supervised") expect(await decisionFor("mcp__other__map_record", events)).toBe("ask");
    await stopClaudeSession("s1");
    await turn.catch(() => undefined);
  });

  it("keeps a plan turn read-only: the map can be read but not changed", async () => {
    const { events, turn } = await startTurn({ runtimeMode: "full-access", intent: "plan", learnAccess: true });
    expect(await decisionFor("mcp__loci_learn__map_read", events)).toBe("allow");
    for (const tool of ["map_init", "map_sketch", "map_record", "revisit"])
      expect(await decisionFor(`mcp__loci_learn__${tool}`, events), tool).toBe("deny");
    await stopClaudeSession("s1");
    await turn.catch(() => undefined);
  });
});
