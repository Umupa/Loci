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
import { AGENT_TEMPLATES } from "../templates";
import { currentSoulFor } from "../templates/retiredSouls";

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

it("introduces app tools alongside the user's soul without introducing session delegation", () => {
  const look = {
    name: "Navigator",
    role: "domain guide",
    avatar: "luna",
    color: "#fff",
    workdir: "/home/me/Loci/navigator",
    projects: [{ path: "/code/app", name: "app" }],
  };
  const soul = "# Soul\n\nUse Grilling rounds before collecting sources.";
  const current = { ...files(), soul };
  const prompt = agentContext(look, current, { soul: true, memory: true });
  const blocks = [...prompt.matchAll(/<([a-z_]+)>\n([\s\S]*?)\n<\/\1>/g)];
  expect(blocks.map((block) => block[1])).toEqual(["agent", "soul", "tools", "memory", "memory_files"]);
  expect(blocks.map((block) => block[0]).join("\n\n")).toBe(prompt);
  expect(JSON.parse(blocks[0][2])).toEqual({
    id: current.id, name: look.name, role: look.role,
    workdir: "/home/me/Loci/navigator", folders: ["/code/app"],
  });
  expect(blocks[1][2]).toBe(soul);
  expect(blocks[2][2]).toContain("courses.write");
  expect(blocks[2][2]).toContain("notes.list/read/write");
  expect(blocks[2][2]).toContain("<agent>.workdir");
  expect(blocks[2][2]).not.toContain("sessions.start");
  expect(blocks[2][2]).toContain("once you have written your reply rather than before or in the middle of it");
  expect(blocks[2][2]).toContain("memory.search");
  expect(blocks[3][2]).toBe(current.memory);
  expect(JSON.parse(blocks[4][2])).toEqual({
    path: current.memoryPath, topics: current.topics, omittedLines: 0,
  });

  const memoryOnly = agentContext(look, current, { soul: false, memory: true });
  expect(memoryOnly).not.toContain("<tools>");
  expect(memoryOnly).not.toContain("<soul>");
  expect(memoryOnly).not.toContain("<agent>");
  expect(memoryOnly).toContain(current.memory);
  expect(agentContext(look, current, { soul: false, memory: false })).toBe("");
});

it("says when memory is empty and when lines did not load", () => {
  const look = { name: "Mentor", projects: [] };
  const empty = agentContext(look, { ...files(), memory: "" }, { soul: false, memory: true });
  expect(empty).toContain("<memory>\n(Empty. Nothing has been remembered yet.)\n</memory>");
  const long = Array.from({ length: 205 }, (_, i) => `- fact ${i}`).join("\n");
  const cut = agentContext(look, { ...files(), memory: long }, { soul: false, memory: true });
  expect(cut).toContain("- fact 199\n[5 more lines did not load; move older detail into topic files.]\n</memory>");
  expect(cut).not.toContain("- fact 200");
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

const OLD_MENTOR_SOUL = "e0575861b4bbd98182a53707d77cae059516a972ec21440f50c54d60aa6b24e1";
const OLD_LENS_SOUL = "36032ba9729f32fc63add440abb2a82d3615218f05e3c1051e2f5971ae11fa91";

it.each([
  [OLD_MENTOR_SOUL, "learning-guide"],
  [OLD_LENS_SOUL, "repo-lens"],
] as const)("moves an untouched %s template Soul to the current template", async (hash, template) => {
  const { id } = createAgent([]);
  invoke.mockImplementation(async (command: string) =>
    command === "agent_load" ? { ...files(hash), soul: "# Soul\n\nthe old template" } : "upgraded",
  );
  const loaded = await loadAgentFiles(id);
  const current = AGENT_TEMPLATES.find((entry) => entry.id === template)!.soul;
  expect(loaded).toMatchObject({ soul: current, soulHash: "upgraded" });
  const saves = invoke.mock.calls.filter(([command]) => command === "agent_save");
  expect(saves).toHaveLength(1);
  expect(saves[0][1]).toMatchObject({ agent: id, path: "SOUL.md", text: current, expectedHash: hash });
});

it("keeps a Soul the user edited, and one edited while the upgrade ran", async () => {
  const { id } = createAgent([]);
  invoke.mockImplementation(async (command: string) =>
    command === "agent_load" ? { ...files("edited"), soul: "# Soul\n\nmine" } : "never",
  );
  expect((await loadAgentFiles(id)).soul).toBe("# Soul\n\nmine");
  expect(invoke.mock.calls.some(([command]) => command === "agent_save")).toBe(false);

  let loads = 0;
  invoke.mockReset();
  invoke.mockImplementation(async (command: string) => {
    if (command === "agent_save") throw "conflict";
    loads += 1;
    return loads === 1 ? { ...files(OLD_MENTOR_SOUL), soul: "old" } : { ...files("raced"), soul: "# Soul\n\njust edited" };
  });
  expect(await loadAgentFiles(id)).toMatchObject({ soul: "# Soul\n\njust edited", soulHash: "raced" });
});

it("keeps the platform's formats out of the templates and in the tool guide", async () => {
  const { createHash } = await import("node:crypto");
  const tools = agentContext({ name: "Mentor", projects: [] }, files(), { soul: true, memory: false })
    .match(/<tools>\n([\s\S]*?)\n<\/tools>/)![1];
  for (const format of ["loci://source/<id>#section=", "code.pin", "compare", "documents.write", "reader.open", "annotations.list", "lab/<topic>/", "no scores, mastery gates or review schedules"])
    expect(tools).toContain(format);
  for (const template of AGENT_TEMPLATES) {
    // A shipped template is never its own retired version.
    expect(currentSoulFor(createHash("sha256").update(template.soul).digest("hex"))).toBeUndefined();
    for (const format of ["loci://", "code.pin", "--json", "documents.write", "courses.write", "<reading_now>", "考我"])
      expect(template.soul).not.toContain(format);
    expect(template.soul).toMatch(/first principles/);
    expect(template.soul).toMatch(/shallow to deep/);
  }
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
    id: "agent", name: "小序", role: role ?? null, workdir: null, folders: [],
  });
});

it("loads topic notes into the memory block and resends it when one changes", () => {
  const look = { name: "Mentor", projects: [] };
  const withTopic = (hash: string) => ({
    ...files(),
    topicNotes: [{ name: "learning-mission", text: "# learning-mission\n- 2026-10-13 · 使命：K8s", hash }],
  });
  const block = agentContext(look, withTopic("t1"), { soul: false, memory: true });
  expect(block).toContain("releases are tag-triggered");
  expect(block).toContain("## learning-mission\n- 2026-10-13 · 使命：K8s");
  recordAgentContext("chat", "native-1", withTopic("t1"));
  expect(planAgentContext("chat", "native-1", withTopic("t1")).memory).toBe(false);
  expect(planAgentContext("chat", "native-1", withTopic("t2")).memory).toBe(true);
});

it("names the mentor's folder and says its files may be edited directly", () => {
  const look = { name: "Kern", avatar: "luna", color: "#fff", workdir: "/home/me/Loci/kern", folder: "/home/me/Loci/kern", projects: [] };
  const prompt = agentContext(look, files(), { soul: true, memory: true });
  const blocks = Object.fromEntries([...prompt.matchAll(/<([a-z_]+)>\n([\s\S]*?)\n<\/\1>/g)].map((block) => [block[1], block[2]]));
  expect(JSON.parse(blocks.agent).folder).toBe("/home/me/Loci/kern");
  expect(blocks.tools).toContain("<agent>.folder");
  expect(blocks.tools).toContain("library.check");
  expect(blocks.tools).toContain("only through soul.* and memory.*");
});
