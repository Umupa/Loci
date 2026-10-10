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

it("says how to keep memory and update the soul only at the user's request", () => {
  const look = {
    name: "Skull",
    avatar: "ember",
    color: "#fff",
    projects: [
      { path: "/code/app", name: "app" },
      { path: "/code/site", name: "site" },
    ],
  };
  const full = agentContext(look, files(), { soul: true, memory: true });
  expect(full).toContain("You are Skull: a resident agent in Loci");
  expect(full).toContain("not a general chat assistant");
  expect(agentContext({ ...look, role: "CI watcher" }, files(), { soul: true, memory: false })).toContain("You are Skull, the user's CI watcher: a resident agent in Loci");
  expect(full).toContain("these 2 projects (app and site)");
  expect(full).toContain("- site: /code/site");
  expect(full).toContain("Be brief.");
  expect(full).toContain(
    "Otherwise, only when the user asks you to change your soul or standing instructions",
  );
  expect(full).toContain(
    "A request defining your continuing role or standing preferences is also a request to save those instructions; a one-off task is not",
  );
  expect(full).toContain("app soul.read {}");
  expect(full).toContain(
    'app soul.update {"text":"<complete updated Markdown>","expectedHash":"<hash from soul.read>"}',
  );
  expect(full).toContain("preserving the other instructions");
  expect(full).toContain(
    "Never rewrite a customized Soul on your own or edit its files directly",
  );
  expect(full).not.toContain("never edit that file yourself");
  expect(full).toContain("app memory.add");
  // Nothing it cannot do yet: no documents, no worktrees.
  expect(full).not.toContain("artifacts.");
  expect(full).not.toContain("worktree");
  expect(full).toContain(
    "Topic notes, read on demand with memory.read: releases",
  );
  expect(full).toContain("releases are tag-triggered");
  const memoryOnly = agentContext(look, files(), {
    soul: false,
    memory: true,
  });
  expect(memoryOnly).not.toContain("<soul>");
  expect(memoryOnly).toContain("<memory>");
  const alone = agentContext({ ...look, projects: [] }, files(), {
    soul: true,
    memory: false,
  });
  expect(alone).toContain("has not given you any projects yet");
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

it("initializes a blank agent from a natural purpose and starts helping without a profile interview", () => {
  const context = agentContext(
    { name: "Wisp", avatar: "wisp", color: "#fff", projects: [] },
    { ...files(), soul: defaultSoul() },
    { soul: true, memory: true },
    { canChooseName: true },
  );
  const message = "我想练英语口语";
  const prompt = agentTurn(message, [context]);
  expect(prompt).toContain("<agent_creation>");
  expect(prompt).toContain("begin a useful first step in this turn");
  expect(prompt).toContain("A natural statement of purpose");
  expect(prompt).toContain('They do not need to say "long-term" or "standing instructions"');
  expect(prompt).toContain("first draft Soul with 3–5 short instructions");
  expect(prompt).toContain("not invented facts about the user");
  expect(prompt).toContain("Do not invent their level, preferences, schedule, commitments or permission");
  expect(prompt).toContain('app agent.rename {"name":"<short name>","role":"<concise role>"}');
  expect(prompt).toContain("Do not ask them to confirm this first draft");
  expect(prompt).toContain("Only for an untouched default Soul with no assigned role");
  expect(prompt).toContain("That identity does not authorize connecting accounts, sending messages, payments, publishing or habits");
  expect(prompt).toContain("Initialize only over the default empty standing instructions");
  expect(prompt).toContain("A clearly one-off task");
  expect(prompt).toContain("do it without renaming yourself or writing a Soul");
  expect(prompt).toContain("If the message is ambiguous, help with the task now");
  expect(prompt).toContain("After completing a real task, suggest a habit only when the user has described a recurring need");
  expect(prompt).toContain("habits run only while Loci is open");
  expect(prompt.endsWith(message)).toBe(true);
  expect(prompt).not.toContain("<agent_setup>");
});

it.each([undefined, { canChooseName: false }])("keeps an existing name while initializing the role (%#)", (options) => {
  const prompt = agentContext(
    { name: "小序", avatar: "wisp", color: "#fff", projects: [] },
    { ...files(), soul: defaultSoul() },
    { soul: true, memory: false },
    options,
  );
  expect(prompt).toContain("<agent_creation>");
  expect(prompt).toContain('The user has already named you. Keep "小序" unless they ask to change it');
  expect(prompt).toContain('app agent.rename {"name":"小序","role":"<concise role>"}');
  expect(prompt).not.toContain("The current name is a placeholder");
});

it("leaves a defined role or edited soul out of blank-agent creation guidance", () => {
  const look = { name: "Wisp", avatar: "wisp", color: "#fff", projects: [] };
  for (const [identity, soul] of [
    [{ ...look, role: "tutor" }, defaultSoul()],
    [look, defaultSoul("Explain things briefly.")],
    [look, ""],
  ] as const) {
    const prompt = agentContext(identity, { ...files(), soul }, { soul: true, memory: false }, { canChooseName: true });
    expect(prompt).not.toContain("<agent_creation>");
    expect(prompt).toContain("Never rewrite a customized Soul on your own");
    expect(prompt).toContain(soul.trim());
  }
  expect(agentContext(look, { ...files(), soul: defaultSoul() }, { soul: false, memory: true }))
    .not.toContain("<agent_creation>");
});

it("asks only for an indispensable input and uses natural questions while allowing lesson choices", () => {
  const prompt = agentContext(
    { name: "Tutor", role: "tutor", avatar: "luna", color: "#fff", projects: [] },
    files(),
    { soul: true, memory: false },
  );
  const rules = prompt.match(/<asking_rules>([\s\S]*?)<\/asking_rules>/)?.[1];
  expect(rules).toBeDefined();
  expect(rules).toContain("Missing optional preferences are not blockers");
  expect(rules).toContain("Ask at most one critical question only when a missing input cannot reasonably be inferred or defaulted and prevents the current task");
  expect(rules).toContain("A short natural question is the default");
  expect(rules).toContain("concrete choices genuinely help a required user decision or an interactive lesson");
  expect(rules).toContain("Teaching exercises and follow-up questions are part of the lesson");
  expect(rules).toContain("```loci-question");
  expect(rules).not.toContain("When the user has to decide something, ask them");
});
