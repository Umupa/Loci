// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invoke(...args),
}));

import { createAgent, findAgent, updateAgent } from "./agent";
import {
  defaultSoul,
  loadAgentFiles,
  MEMORY_MAX_LINES,
  memoryWithinBudget,
  planAgentContext,
  agentContext,
  agentTurn,
  recordAgentContext,
  resetAgentDefaults,
} from "./agentFiles";

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
  invoke.mockReset();
});
afterEach(() => vi.unstubAllGlobals());

const files = (soulHash = "s1", memoryHash = "m1") => ({
  id: "agent",
  dir: "/data/agents/agent",
  soul: "# Soul\n\nBe brief.",
  soulHash,
  memory: "- 2026-10-04 · releases are tag-triggered",
  memoryHash,
  memoryPath: "/data/agents/agent/MEMORY.md",
  topics: ["releases"],
});

it("hands a new native session everything, then nothing it already has", () => {
  expect(planAgentContext("chat", undefined, files())).toEqual({
    soul: true,
    memory: true,
  });
  // The first turn is recorded before its reply names the provider session.
  recordAgentContext("chat", undefined, files());
  expect(planAgentContext("chat", "native-1", files())).toEqual({
    soul: false,
    memory: false,
  });
  recordAgentContext("chat", "native-1", files());
  expect(planAgentContext("chat", "native-1", files())).toEqual({
    soul: false,
    memory: false,
  });
});

it("resends memory when it changed, and everything for a new session", () => {
  recordAgentContext("chat", "native-1", files());
  expect(planAgentContext("chat", "native-1", files("s1", "m2"))).toEqual({
    soul: false,
    memory: true,
  });
  expect(planAgentContext("chat", "native-1", files("s2", "m1"))).toEqual({
    soul: true,
    memory: true,
  });
  // A model switch or a rotated session starts a different native session.
  expect(planAgentContext("chat", "native-2", files())).toEqual({
    soul: true,
    memory: true,
  });
});

it("refreshes standing rules in an existing conversation after a context upgrade", () => {
  localStorage.setItem(
    "loci:agent-handed",
    JSON.stringify({
      chat: { provider: "native-1", soulHash: "s1:v0", memoryHash: "m1" },
    }),
  );
  expect(planAgentContext("chat", "native-1", files())).toEqual({
    soul: true,
    memory: true,
  });
  recordAgentContext("chat", "native-1", files());
  expect(planAgentContext("chat", "native-1", files())).toEqual({
    soul: false,
    memory: false,
  });
});

it("loads only whole lines within the memory budget", () => {
  const memory = Array.from(
    { length: MEMORY_MAX_LINES + 5 },
    (_, i) => `- fact ${i}`,
  ).join("\n");
  const budget = memoryWithinBudget(memory);
  expect(budget.lines).toBe(MEMORY_MAX_LINES + 5);
  expect(budget.droppedLines).toBe(5);
  expect(budget.text.split("\n")).toHaveLength(MEMORY_MAX_LINES);
  expect(memoryWithinBudget("").lines).toBe(0);
});

it("carries the user's soul and factual data without additional standing instructions", () => {
  const look = {
    name: "Navigator",
    role: "domain guide",
    avatar: "luna",
    color: "#fff",
    projects: [{ path: "/code/app", name: "app" }],
  };
  const soul = "# Soul\n\nUse Grilling rounds before collecting sources.";
  const current = { ...files(), soul };
  const prompt = agentContext(look, current, { soul: true, memory: true });
  const blocks = [...prompt.matchAll(/<([a-z_]+)>\n([\s\S]*?)\n<\/\1>/g)];
  expect(blocks.map((block) => block[1])).toEqual(["agent", "soul", "memory", "memory_files"]);
  expect(blocks.map((block) => block[0]).join("\n\n")).toBe(prompt);
  expect(JSON.parse(blocks[0][2])).toEqual({
    id: current.id, name: look.name, role: look.role, projects: look.projects,
  });
  expect(blocks[1][2]).toBe(soul);
  expect(blocks[2][2]).toBe(current.memory);
  expect(JSON.parse(blocks[3][2])).toEqual({
    path: current.memoryPath, topics: current.topics, omittedLines: 0,
  });

  const memoryOnly = agentContext(look, current, { soul: false, memory: true });
  expect(memoryOnly).not.toContain("<soul>");
  expect(memoryOnly).not.toContain("<agent>");
  expect(memoryOnly).toContain(current.memory);
  expect(agentContext(look, current, { soul: false, memory: false })).toBe("");
});

it("seeds SOUL.md once, over the missing file only", async () => {
  const { id } = createAgent(["/code/app"]);
  invoke.mockImplementation(async (command: string) =>
    command === "agent_load" ? { ...files("empty"), soul: null } : "seeded",
  );
  const [first, second] = await Promise.all([
    loadAgentFiles(id),
    loadAgentFiles(id),
  ]);
  expect(first).toBe(second);
  expect(first.soul).toBe(defaultSoul());
  expect(first.soulHash).toBe("seeded");
  const saves = invoke.mock.calls.filter(
    ([command]) => command === "agent_save",
  );
  expect(saves).toHaveLength(1);
  expect(saves[0][1]).toMatchObject({
    agent: id,
    path: "SOUL.md",
    expectedHash: "empty",
  });
});

it.each([
  [undefined, defaultSoul()],
  ["domain guide", "# Soul\n\nGrill the unresolved decisions."],
] as const)("adds no initialization or question policies to a %s agent", (role, soul) => {
  const context = agentContext(
    { name: "小序", role, avatar: "wisp", color: "#fff", projects: [] },
    { ...files(), soul },
    { soul: true, memory: false },
  );
  const message = "我想练英语口语";
  const prompt = agentTurn(message, [context]);
  expect(prompt).toBe(`<loci_context>\n${context}\n</loci_context>\n\n${message}`);
  expect(prompt).toContain(soul);
  expect(JSON.parse(context.match(/<agent>\n([\s\S]*?)\n<\/agent>/)![1])).toEqual({
    id: "agent", name: "小序", role: role ?? null, projects: [],
  });
});
