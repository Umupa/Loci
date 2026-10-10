// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { agentLook, type Agent } from "./agent";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invoke(...args),
}));

import * as agentFiles from "./agentFiles";
import { prepareAgentTurn } from "./agentTurnContext";

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
  invoke.mockReset();
  invoke.mockResolvedValue({
    id: "agent",
    dir: "/data/agents/agent",
    soul: agentFiles.defaultSoul(),
    soulHash: "s1",
    memory: "",
    memoryHash: "m1",
    memoryPath: "/data/agents/agent/MEMORY.md",
    topics: [],
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it.each([
  [undefined, true],
  ["  ", true],
  ["小序", false],
  ["Wisp", false],
] as const)("allows initial naming only when there is no explicit agent name (%s)", async (name, canChooseName) => {
  const context = vi.spyOn(agentFiles, "agentContext");
  const agent: Agent = { id: "agent", name, avatar: "wisp", color: "#fff", projects: [] };
  const prepared = await prepareAgentTurn(agent, { id: "chat", blocks: [] }, { canRotate: false });

  expect(context).toHaveBeenCalledOnce();
  expect(context.mock.calls[0][3]).toEqual({ canChooseName });
  expect(prepared.context[0]).toContain(canChooseName
    ? "The current name is a placeholder"
    : `The user has already named you. Keep ${JSON.stringify(name)} unless they ask to change it`);
  expect(agent.name).toBe(name);
});

it("refreshes initial naming permission when the user explicitly chooses the same placeholder name", async () => {
  const agent: Agent = { id: "agent", avatar: "wisp", color: "#fff", projects: [] };
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  const initial = await prepareAgentTurn(agent, session, { canRotate: false });
  expect(initial.context[0]).toContain("The current name is a placeholder");
  initial.record(session.providerSessionId);

  const named = { ...agent, name: agentLook(agent).name };
  const refreshed = await prepareAgentTurn(named, session, { canRotate: false });
  expect(refreshed.introduces).toBe(true);
  expect(refreshed.context[0]).toContain(`The user has already named you. Keep ${JSON.stringify(named.name)} unless they ask to change it`);
  expect(refreshed.context[0]).not.toContain("The current name is a placeholder");
  refreshed.record(session.providerSessionId);
  expect((await prepareAgentTurn(named, session, { canRotate: false })).introduces).toBe(false);
});
