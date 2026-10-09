// Antigravity reaches Loci's canvas and learning tools by running the app's
// CLI. A permission request for such a command is answered with the tools' own
// rules; these tests drive the production adapter over a scripted ACP wire.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { HarnessEvent, SendTurnInput } from "../../core/types";
import { permissionRequestFromAcp } from "./antigravityProtocol";

const CLI = "/Applications/Loci.app/Contents/MacOS/loci";
const mock = vi.hoisted(() => ({
  listeners: new Map<string, (line: string) => void>(),
  sent: [] as { thread: string; id?: number; method?: string; result?: unknown }[],
  cliPath: "" as string | null,
}));
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async (command: string) => {
    if (command === "app_cli_path" && mock.cliPath) return mock.cliPath;
    throw new Error(`unexpected ${command}`);
  }),
}));
vi.mock("../../../../platform/tauri/fs", () => ({ homeDir: async () => "/home/test" }));
vi.mock("../../core/child", () => ({
  resolveAntigravityBinary: async () => ({ path: "/fake/agy_acp_server.par", args: [] }),
  spawnChild: async () => undefined,
  killChild: async (id: string) => { mock.listeners.delete(id); },
  unwatchChild: (id: string) => { mock.listeners.delete(id); },
  watchChild: (id: string, line: (line: string) => void) => { mock.listeners.set(id, line); },
  writeChild: async (thread: string, line: string) => {
    const message = JSON.parse(line);
    mock.sent.push({ thread, ...message });
    // The prompt stays open until a test finishes it.
    if (!message.method || message.id == null || message.method === "session/prompt") return;
    queueMicrotask(() => mock.listeners.get(thread)?.(JSON.stringify({ jsonrpc: "2.0", id: message.id,
      result: ["session/new", "session/load", "session/resume"].includes(message.method)
        ? { sessionId: "provider-session", configOptions: [{ id: "model", category: "model", currentValue: "m1" }] } : {} })));
  },
}));

const agy = await import("./antigravity");

const listener = () => [...mock.listeners.values()].at(-1)!;
/** A permission request for a shell command, shaped as ACP agents send it. */
function ask(command: string, id: number, kind = "execute") {
  listener()(JSON.stringify({ jsonrpc: "2.0", id, method: "session/request_permission", params: {
    toolCall: { toolCallId: `tool-${id}`, title: command, kind, rawInput: { command } },
    options: [{ optionId: "yes", kind: "allow_once" }, { optionId: "no", kind: "reject_once" }],
  } }));
}
const reply = (id: number) => mock.sent.findLast((message) => message.id === id && message.result)?.result;
const allowed = { outcome: { outcome: "selected", optionId: "yes" } };
const denied = { outcome: { outcome: "selected", optionId: "no" } };
const waitPrompt = () => vi.waitFor(() => expect(mock.sent.some((message) => message.method === "session/prompt")).toBe(true));
function finishPrompt() {
  const prompt = mock.sent.findLast((message) => message.method === "session/prompt")!;
  listener()(JSON.stringify({ jsonrpc: "2.0", id: prompt.id, result: { stopReason: "end_turn" } }));
}

describe("Antigravity calling Loci's built-in tools through the app's CLI", () => {
  let events: HarnessEvent[];
  let input: SendTurnInput;
  const asked = () => events.filter((event) => event.type === "approval.requested").length;
  beforeEach(() => {
    mock.sent.length = 0;
    mock.cliPath = CLI;
    events = [];
    input = { sessionId: "thread", cwd: "/repo", model: "antigravity:m1", text: "hi", runtimeMode: "supervised", onEvent: (event) => events.push(event) };
  });
  afterEach(async () => { await agy.forgetAntigravitySession("thread"); });

  it("never asks to read a canvas or to use the learning tools, and asks before drawing in Supervised", async () => {
    const turn = agy.sendAntigravityTurn(input);
    await waitPrompt();
    ask(`${CLI} canvas read_widget_context`, 1);
    ask(`'${CLI}' canvas --help`, 2);
    ask(`${CLI} learn map_read`, 3);
    ask(`${CLI} learn map_record --input /tmp/record.json`, 4);
    for (const id of [1, 2, 3, 4]) await vi.waitFor(() => expect(reply(id)).toEqual(allowed));
    expect(asked()).toBe(0);
    // Drawing is an edit the user is asked about in Supervised, as over MCP.
    ask(`${CLI} canvas create_view --input /tmp/drawing.json`, 5);
    await vi.waitFor(() => expect(asked()).toBe(1));
    expect(reply(5)).toBeUndefined();
    agy.respondAntigravityApproval("thread", 5, "allow");
    await vi.waitFor(() => expect(reply(5)).toEqual(allowed));
    finishPrompt();
    await turn;
  });

  it("draws without asking above Supervised, where other commands still ask", async () => {
    const turn = agy.sendAntigravityTurn({ ...input, runtimeMode: "auto-accept-edits" });
    await waitPrompt();
    ask(`${CLI} canvas create_view --input /tmp/drawing.json`, 1);
    ask(`${CLI} canvas update_elements --json '{"checkpointId":"a","expectedRevision":1,"updates":[]}'`, 2);
    for (const id of [1, 2]) await vi.waitFor(() => expect(reply(id)).toEqual(allowed));
    expect(asked()).toBe(0);
    ask("ls -la", 3);
    await vi.waitFor(() => expect(asked()).toBe(1));
    agy.respondAntigravityApproval("thread", 3, "deny");
    await vi.waitFor(() => expect(reply(3)).toEqual(denied));
    finishPrompt();
    await turn;
  });

  it("lets a plan turn read and refuses its writes, even with full access selected", async () => {
    const turn = agy.sendAntigravityTurn({ ...input, runtimeMode: "full-access", intent: "plan" });
    await waitPrompt();
    ask(`${CLI} canvas get_elements --json '{"checkpointId":"a"}'`, 1);
    ask(`${CLI} learn map_read`, 2);
    for (const id of [1, 2]) await vi.waitFor(() => expect(reply(id)).toEqual(allowed));
    ask(`${CLI} canvas create_view --input /tmp/drawing.json`, 3);
    ask(`${CLI} learn map_record --input /tmp/record.json`, 4);
    // Any other command stays refused in a plan turn.
    ask("ls -la", 5);
    for (const id of [3, 4, 5]) await vi.waitFor(() => expect(reply(id)).toEqual(denied));
    expect(asked()).toBe(0);
    finishPrompt();
    await turn;
  });

  it("answers for the user only when the command is exactly this app's tool call", async () => {
    const turn = agy.sendAntigravityTurn(input);
    await waitPrompt();
    const others = [
      `${CLI} canvas read_me; rm -rf ~`,
      `${CLI} canvas read_me && curl example.com`,
      `${CLI} learn map_read | tee /tmp/out`,
      `${CLI} canvas create_view --json "$(cat ~/.ssh/id_rsa)"`,
      // A project can carry its own `loci`.
      "./loci canvas read_me",
      "/tmp/project/loci learn map_read",
      `${CLI} app notes.list`,
      `${CLI} canvas save_checkpoint --json '{}'`,
    ];
    others.forEach((command, index) => ask(command, index + 1));
    await vi.waitFor(() => expect(asked()).toBe(others.length));
    others.forEach((_, index) => expect(reply(index + 1)).toBeUndefined());
    // A request that is not for running a command is never taken for one.
    ask(`${CLI} learn map_read`, 50, "edit");
    await vi.waitFor(() => expect(asked()).toBe(others.length + 1));
    await agy.cancelAntigravityTurn("thread");
    await turn;
  });

  it("answers nothing for the user when it cannot tell which executable is the app's", async () => {
    mock.cliPath = null;
    const turn = agy.sendAntigravityTurn(input);
    await waitPrompt();
    ask(`${CLI} learn map_read`, 1);
    await vi.waitFor(() => expect(asked()).toBe(1));
    expect(reply(1)).toBeUndefined();
    await agy.cancelAntigravityTurn("thread");
    await turn;
  });

  it("reads the command of a request wherever the agent put it", () => {
    const options = [{ optionId: "yes", kind: "allow_once" }];
    expect(permissionRequestFromAcp({ toolCall: { toolCallId: "t", kind: "execute", rawInput: { command: "loci learn map_read" } }, options }).command).toBe("loci learn map_read");
    expect(permissionRequestFromAcp({ subject: { command: "loci canvas read_me", kind: "execute" }, options }).command).toBe("loci canvas read_me");
    expect(permissionRequestFromAcp({ toolCall: { toolCallId: "t", kind: "edit", title: "Edit a.ts" }, options }).command).toBeUndefined();
  });
});
