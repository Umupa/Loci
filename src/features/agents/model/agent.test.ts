// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import {
  agentForSession,
  agentLook,
  agentState,
  createAgent,
  findAgent,
  listAgents,
  removeAgent,
  reorderAgents,
  saveAgentDefaults,
  saveAgentSessionId,
  updateAgent,
} from "./agent";

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
    removeItem: (key: string) => stored.delete(key),
  });
});
afterEach(() => vi.unstubAllGlobals());

it("gives each new agent an avatar and color the others are not using", () => {
  const first = createAgent();
  const second = createAgent();
  expect(second.avatar).not.toBe(first.avatar);
  expect(second.color).not.toBe(first.color);
  expect(agentLook(first).name).toBe("Ember");
  expect(agentLook(second).name).toBe("Wisp");
});

it("takes the look and name chosen for it when it is set up", () => {
  const first = createAgent({ name: "  Scout ", avatar: "dew", color: "#123456" });
  expect(first).toMatchObject({ name: "Scout", avatar: "dew", color: "#123456" });
  // What was not chosen still comes from what the others are not using.
  const second = createAgent({ name: "  " });
  expect(second.name).toBeUndefined();
  expect(second.avatar).toBe("ember");
});

it("goes by the user's name once it has one, and back when it is cleared", () => {
  const { id } = createAgent();
  updateAgent(id, (agent) => ({ ...agent, name: "Scout" }));
  expect(agentLook(findAgent(id)!).name).toBe("Scout");
  updateAgent(id, (agent) => ({ ...agent, name: "  " }));
  expect(findAgent(id)?.name).toBeUndefined();
  expect(agentLook(findAgent(id)!).name).toBe("Ember");
});

it("keeps the defaults a mentor's next conversation starts with", () => {
  const { id } = createAgent();
  saveAgentDefaults(id, {
    provider: "grok",
    model: "grok:deepseek-flash",
    mode: "full-access",
    effort: "high",
    modelSettings: { effort: "high" },
  });
  expect(findAgent(id)?.defaults).toEqual({
    provider: "grok",
    model: "grok:deepseek-flash",
    mode: "full-access",
    effort: "high",
    modelSettings: { effort: "high" },
  });
  // Saying the same thing again does not rewrite the roster for every turn.
  const written = localStorage.getItem("loci:agent-roster");
  saveAgentDefaults(id, { ...findAgent(id)!.defaults! });
  expect(localStorage.getItem("loci:agent-roster")).toBe(written);
  // An unknown provider or permission mode is not read back.
  localStorage.setItem("loci:agent-roster", JSON.stringify([
    { id: "bad", avatar: "ember", color: "#000", defaults: { provider: "nope", model: "x", mode: "full-access" } },
    { id: "bad-mode", avatar: "dew", color: "#000", defaults: { provider: "grok", model: "x", mode: "yolo" } },
  ]));
  expect(listAgents().map((agent) => agent.defaults)).toEqual([undefined, undefined]);
});

it("carries its one main job beside its name, and drops an empty one", () => {
  const { id } = createAgent();
  updateAgent(id, (agent) => ({ ...agent, name: "Scout", role: " CI watcher " }));
  expect(agentLook(findAgent(id)!)).toMatchObject({ name: "Scout", role: "CI watcher" });
  updateAgent(id, (agent) => ({ ...agent, role: " " }));
  expect(findAgent(id)?.role).toBeUndefined();
  expect(agentLook(findAgent(id)!).role).toBeUndefined();
});

it("keeps the rail's order and forgets a removed agent", () => {
  const a = createAgent();
  const b = createAgent();
  const c = createAgent();
  reorderAgents([c.id, a.id, b.id]);
  expect(listAgents().map((agent) => agent.id)).toEqual([c.id, a.id, b.id]);
  removeAgent(a.id);
  expect(listAgents().map((agent) => agent.id)).toEqual([c.id, b.id]);
});

it("keeps the one-time access migration flag", () => {
  const { id } = createAgent();
  updateAgent(id, (agent) => ({ ...agent, accessMigrated: true }));
  expect(findAgent(id)?.accessMigrated).toBe(true);
  expect(JSON.parse(localStorage.getItem("loci:agent-roster")!)[0].accessMigrated).toBe(true);
});

it("finds an agent by its conversation", () => {
  const { id } = createAgent();
  expect(agentForSession("s1")).toBeUndefined();
  saveAgentSessionId(id, "s1");
  expect(agentForSession("s1")?.id).toBe(id);
});

it("drops roster entries it cannot read", () => {
  localStorage.setItem(
    "loci:agent-roster",
    JSON.stringify([{ id: "../x" }, null, { id: "a-1", projects: [1, "/p"] }]),
  );
  expect(listAgents()).toEqual([
    { id: "a-1", avatar: "ember", color: "hsl(211 92% 62%)" },
  ]);
});

it("says what the agent is doing from its conversation", () => {
  expect(agentState({ blocks: [], busy: false })).toEqual({ status: "idle" });
  expect(agentState({ blocks: [], busy: true })).toEqual({
    status: "working",
    activity: "Thinking",
  });
  expect(
    agentState({
      busy: true,
      blocks: [
        { id: "u", role: "user", text: "go" },
        {
          id: "t",
          role: "tool",
          text: "",
          tool: { kind: "execute", title: "npm test", status: "in_progress" },
        },
      ] as never,
    }),
  ).toEqual({ status: "working", activity: "Running npm test" });
  expect(
    agentState({
      busy: true,
      blocks: [
        {
          id: "t",
          role: "assistant",
          text: "",
          tool: { title: "rm -rf build" },
          approval: { requestId: 1 },
        },
      ] as never,
    }),
  ).toEqual({ status: "needs-you", activity: "Approve rm -rf build" });
});

it("keeps the workdir as the folder it works in", async () => {
  const { agentFolders } = await import("./agent");
  const { id } = createAgent();
  updateAgent(id, (agent) => ({ ...agent, workdir: "/home/me/Loci/ember" }));
  const agent = findAgent(id)!;
  expect(agent.workdir).toBe("/home/me/Loci/ember");
  expect(agentFolders(agent)).toEqual(["/home/me/Loci/ember"]);
  updateAgent(id, (current) => ({ ...current, workdir: " " }));
  expect(findAgent(id)).not.toHaveProperty("workdir");
  expect(agentFolders(findAgent(id)!)).toEqual([]);
});

it("keeps a mentor's own learning language, and only a known one", () => {
  localStorage.setItem(
    "loci:agent-roster",
    JSON.stringify([{ id: "a-1", language: "zh-CN" }, { id: "a-2", language: "klingon" }, { id: "a-3", language: "auto" }]),
  );
  expect(listAgents().map((agent) => agent.language)).toEqual(["zh-CN", undefined, "auto"]);
});
