import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { RuntimeMode, TurnIntent } from "../../../../features/sessions/model/session";
import type { HarnessEvent } from "../../core/types";

const sent: string[] = [];
const spawned: string[][] = [];
let onLine: ((line: string) => void) | undefined;
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../core/child", () => ({
  resolveCodexBinary: async () => ({ path: "/fake/codex" }),
  spawnChild: async (_id: string, _path: string, args: string[]) => { spawned.push(args); },
  killChild: async () => undefined,
  unwatchChild: () => undefined,
  watchChild: (_id: string, line: (l: string) => void) => { onLine = line; },
  writeChild: vi.fn(async (_id: string, line: string) => { sent.push(line); }),
}));

const { respondCodexApproval, sendCodexTurn, stopCodexSession, __codexTestReset } = await import("./codex");

const server = { command: "/usr/bin/node", args: ["/opt/Loci/resources/excalidraw-mcp/loci-bridge.mjs"] };
const parse = () => sent.map((line) => JSON.parse(line) as Record<string, any>);
const reply = (id: number, result: unknown) => onLine!(JSON.stringify({ id, result }));
const waitFor = async (pred: () => boolean, label: string) => {
  for (let i = 0; i < 200; i++) {
    if (pred()) return;
    await new Promise((r) => setTimeout(r, 5));
  }
  throw new Error(`timed out waiting for ${label}; sent=${JSON.stringify(parse().map((m) => m.method ?? `reply:${m.id}`))}`);
};

async function startTurn(options: { runtimeMode?: RuntimeMode; intent?: TurnIntent } = {}) {
  const events: HarnessEvent[] = [];
  const turn = sendCodexTurn({ sessionId: "s1", cwd: "/repo", model: "codex:gpt-5.4", modelSettings: {}, runtimeMode: options.runtimeMode ?? "supervised",
    intent: options.intent, text: "draw the architecture", attachments: [], onEvent: (event) => events.push(event) });
  void turn.catch(() => undefined);
  for (const method of ["initialize", "thread/start", "turn/start"]) {
    await waitFor(() => parse().some((m) => m.method === method), method);
    reply(parse().find((m) => m.method === method)!.id, method === "thread/start" ? { thread: { id: "thr_1" } } : method === "turn/start" ? { turn: { id: "turn_1", status: "inProgress" } } : {});
  }
  onLine!(JSON.stringify({ method: "turn/started", params: { turn: { id: "turn_1", status: "inProgress" } } }));
  return { events, turn };
}

/** The request Codex 0.160 sends before running a tool whose approval mode is `prompt`. */
const approvalRequest = (serverName: string, tool: string) => ({
  threadId: "thr_1", turnId: "turn_1", serverName, mode: "form",
  _meta: { codex_approval_kind: "mcp_tool_call", tool_title: "Draw Diagram", tool_params: { elements: "[]" } },
  message: `Allow the ${serverName} MCP server to run tool "${tool}"?`,
  requestedSchema: { type: "object", properties: {} },
});

async function answerTo(params: object, events: HarnessEvent[]) {
  const id = 900 + sent.length;
  onLine!(JSON.stringify({ id, method: "mcpServer/elicitation/request", params }));
  await new Promise((r) => setTimeout(r, 30));
  const answered = parse().find((message) => message.id === id);
  if (answered) return answered.result.action as string;
  const asked = events.find((event) => event.type === "approval.requested");
  return asked ? { ask: (asked as { title: string }).title, requestId: (asked as { requestId: number }).requestId, id } : "pending";
}

beforeEach(() => {
  sent.length = 0;
  spawned.length = 0;
  __codexTestReset();
  vi.mocked(invoke).mockImplementation(async (command) => command === "canvas_mcp_server" ? server : undefined);
});
afterEach(async () => { await stopCodexSession("s1"); });

describe("Loci's Excalidraw MCP server in Codex sessions", () => {
  it("is passed to the app server as config overrides ahead of the subcommand", async () => {
    await startTurn();
    expect(spawned[0]).toEqual([
      "-c", 'mcp_servers.loci_excalidraw.command="/usr/bin/node"',
      "-c", 'mcp_servers.loci_excalidraw.args=["/opt/Loci/resources/excalidraw-mcp/loci-bridge.mjs"]',
      "-c", 'mcp_servers.loci_excalidraw.env_vars=["LOCI_APP_ENDPOINT","LOCI_APP_TOKEN"]',
      "-c", 'mcp_servers.loci_excalidraw.tools.create_view.approval_mode="prompt"',
      "app-server",
    ]);
  });

  it("starts the plain app server when the drawing server cannot run", async () => {
    vi.mocked(invoke).mockRejectedValue(new Error("Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH."));
    await startTurn();
    expect(spawned[0]).toEqual(["app-server"]);
  });

  it.each([
    ["auto-accept-edits", "accept"],
    ["auto", "accept"],
    ["full-access", "accept"],
  ] as const)("draws without asking in %s mode", async (runtimeMode, expected) => {
    const { events } = await startTurn({ runtimeMode });
    expect(await answerTo(approvalRequest("loci_excalidraw", "create_view"), events)).toBe(expected);
    expect(events.some((event) => event.type === "approval.requested")).toBe(false);
  });

  it("asks before drawing in Supervised mode, as a canvas row the user can allow", async () => {
    const { events } = await startTurn({ runtimeMode: "supervised" });
    const asked = await answerTo(approvalRequest("loci_excalidraw", "create_view"), events) as { ask: string; requestId: number; id: number };
    // The transcript recognizes this title and shows "Draw on the canvas".
    expect(asked.ask).toBe("loci_excalidraw:create_view");
    respondCodexApproval("s1", asked.requestId, "allow");
    await waitFor(() => parse().some((message) => message.id === asked.id), "approval answer");
    expect(parse().find((message) => message.id === asked.id)!.result).toEqual({ action: "accept", content: {}, _meta: null });
  });

  it("does not draw in a read-only plan turn, even with Full Access", async () => {
    const { events } = await startTurn({ runtimeMode: "full-access", intent: "plan" });
    expect(await answerTo(approvalRequest("loci_excalidraw", "create_view"), events)).toBe("decline");
  });

  it("leaves other servers' approvals to the user", async () => {
    const { events } = await startTurn({ runtimeMode: "auto-accept-edits" });
    expect(await answerTo(approvalRequest("excalidraw", "create_view"), events)).toMatchObject({ ask: 'excalidraw: Allow the excalidraw MCP server to run tool "create_view"?' });
  });
});
