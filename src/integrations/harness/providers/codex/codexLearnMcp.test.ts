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

const { sendCodexTurn, stopCodexSession, __codexTestReset } = await import("./codex");

const canvas = { command: "/usr/bin/node", args: ["/opt/Loci/resources/excalidraw-mcp/loci-bridge.mjs"] };
const learn = { command: "/usr/bin/node", args: ["/opt/Loci/resources/learn-mcp/loci-learn.mjs"] };
const parse = () => sent.map((line) => JSON.parse(line) as Record<string, any>);
const reply = (id: number, result: unknown) => onLine!(JSON.stringify({ id, result }));
const complete = () => onLine!(JSON.stringify({ method: "turn/completed", params: { turn: { id: "turn_1", status: "completed" } } }));
const waitFor = async (pred: () => boolean, label: string) => {
  for (let i = 0; i < 200; i++) {
    if (pred()) return;
    await new Promise((r) => setTimeout(r, 5));
  }
  throw new Error(`timed out waiting for ${label}; sent=${JSON.stringify(parse().map((m) => m.method ?? `reply:${m.id}`))}`);
};

async function startTurn(options: { runtimeMode?: RuntimeMode; intent?: TurnIntent; resume?: boolean; reuse?: boolean; learnAccess?: boolean } = {}) {
  const offset = sent.length;
  const messages = () => parse().slice(offset);
  const events: HarnessEvent[] = [];
  const turn = sendCodexTurn({ sessionId: "s1", cwd: "/learn/kubernetes", model: "codex:gpt-5.4", modelSettings: {}, runtimeMode: options.runtimeMode ?? "supervised",
    intent: options.intent, ...(options.learnAccess === undefined ? {} : { learnAccess: options.learnAccess }),
    text: "kubernetes", attachments: [], onEvent: (event) => events.push(event) });
  void turn.catch(() => undefined);
  for (const method of options.reuse ? ["turn/start"] : ["initialize", options.resume ? "thread/resume" : "thread/start", "turn/start"]) {
    await waitFor(() => messages().some((m) => m.method === method), method);
    reply(messages().find((m) => m.method === method)!.id, method.startsWith("thread/") ? { thread: { id: "thr_1" } } : method === "turn/start" ? { turn: { id: "turn_1", status: "inProgress" } } : {});
  }
  onLine!(JSON.stringify({ method: "turn/started", params: { turn: { id: "turn_1", status: "inProgress" } } }));
  return { events, turn };
}

/** The request Codex 0.160 sends before running a tool whose approval mode is `prompt`. */
const approvalRequest = (serverName: string, tool: string) => ({
  threadId: "thr_1", turnId: "turn_1", serverName, mode: "form",
  _meta: { codex_approval_kind: "mcp_tool_call", tool_title: "Record", tool_params: {} },
  message: `Allow the ${serverName} MCP server to run tool "${tool}"?`,
  requestedSchema: { type: "object", properties: {} },
});

async function answerTo(params: object, events: HarnessEvent[]) {
  const id = 900 + sent.length;
  onLine!(JSON.stringify({ id, method: "mcpServer/elicitation/request", params }));
  await new Promise((r) => setTimeout(r, 30));
  const answered = parse().find((message) => message.id === id);
  if (answered) return answered.result.action as string;
  return events.some((event) => event.type === "approval.requested") ? "ask" : "pending";
}

beforeEach(() => {
  vi.mocked(invoke).mockReset();
  const storage = new Map<string, string>();
  vi.stubGlobal("localStorage", { getItem: (key: string) => storage.get(key) ?? null, setItem: (key: string, value: string) => storage.set(key, value) });
  sent.length = 0;
  spawned.length = 0;
  __codexTestReset();
  vi.mocked(invoke).mockImplementation(async (command) => command === "canvas_mcp_server" ? canvas : command === "learn_mcp_server" ? learn : undefined);
});
afterEach(async () => { await stopCodexSession("s1"); vi.unstubAllGlobals(); });

describe("Loci's learning MCP server in Codex sessions", () => {
  it("is attached only to a thread that used /learn, and resumes the thread when it starts learning", async () => {
    const plain = await startTurn({ learnAccess: false });
    expect(spawned[0].join(" ")).not.toContain("loci_learn");
    expect(invoke).not.toHaveBeenCalledWith("learn_mcp_server");
    complete();
    await plain.turn;
    const learning = await startTurn({ learnAccess: true, resume: true });
    expect(spawned).toHaveLength(2);
    expect(spawned[1].slice(spawned[1].indexOf("-c", 10))).toEqual([
      "-c", 'mcp_servers.loci_learn.command="/usr/bin/node"',
      "-c", 'mcp_servers.loci_learn.args=["/opt/Loci/resources/learn-mcp/loci-learn.mjs"]',
      "-c", 'mcp_servers.loci_learn.env_vars=["LOCI_APP_ENDPOINT","LOCI_APP_TOKEN"]',
      "-c", 'mcp_servers.loci_learn.tools.map_init.approval_mode="prompt"',
      "-c", 'mcp_servers.loci_learn.tools.map_sketch.approval_mode="prompt"',
      "-c", 'mcp_servers.loci_learn.tools.map_record.approval_mode="prompt"',
      "-c", 'mcp_servers.loci_learn.tools.revisit.approval_mode="prompt"',
      "app-server",
    ]);
    expect(spawned[1].join(" ")).toContain("mcp_servers.loci_excalidraw.command");
    expect(parse().filter((m) => m.method === "thread/resume").at(-1)?.params.threadId).toBe("thr_1");
    complete();
    await learning.turn;
    // A caller that does not say keeps the running app server.
    const unspecified = await startTurn({ reuse: true });
    complete();
    await unspecified.turn;
    expect(spawned).toHaveLength(2);
  });

  it.each(["supervised", "auto-accept-edits", "auto", "full-access"] as const)("never asks before a learning tool in %s mode", async (runtimeMode) => {
    const { events } = await startTurn({ runtimeMode, learnAccess: true });
    for (const tool of ["map_init", "map_sketch", "map_record", "revisit"])
      expect(await answerTo(approvalRequest("loci_learn", tool), events), tool).toBe("accept");
    expect(events.some((event) => event.type === "approval.requested")).toBe(false);
  });

  it("keeps a plan turn read-only, even with Full Access", async () => {
    const { events } = await startTurn({ runtimeMode: "full-access", intent: "plan", learnAccess: true });
    for (const tool of ["map_init", "map_sketch", "map_record", "revisit"])
      expect(await answerTo(approvalRequest("loci_learn", tool), events), tool).toBe("decline");
    expect(await answerTo(approvalRequest("loci_learn", "map_read"), events)).toBe("accept");
  });
});
