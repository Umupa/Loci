// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import {
  addAgentProject,
  agentForSession,
  agentLook,
  agentProjectsPhrase,
  agentState,
  agentWorksOn,
  createAgent,
  findAgent,
  listAgents,
  removeAgent,
  removeAgentProject,
  reorderAgents,
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
  expect(first.projects).toEqual([]);
});

it("takes the look and name chosen for it when it is set up", () => {
  const first = createAgent(["/code/app"], { name: "  Scout ", avatar: "dew", color: "#123456" });
  expect(first).toMatchObject({ name: "Scout", avatar: "dew", color: "#123456", projects: ["/code/app"] });
  // What was not chosen still comes from what the others are not using.
  const second = createAgent([], { name: "  " });
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

it("carries its one main job beside its name, and drops an empty one", () => {
  const { id } = createAgent();
  updateAgent(id, (agent) => ({ ...agent, name: "Scout", role: " CI watcher " }));
  expect(agentLook(findAgent(id)!)).toMatchObject({ name: "Scout", role: "CI watcher" });
  updateAgent(id, (agent) => ({ ...agent, role: " " }));
  expect(findAgent(id)?.role).toBeUndefined();
  expect(agentLook(findAgent(id)!).role).toBeUndefined();
});

it("adds each project once and takes one away by its path", () => {
  const { id } = createAgent(["/code/app"]);
  addAgentProject(id, "/code/site");
  addAgentProject(id, "/code/app/");
  expect(findAgent(id)?.projects).toEqual(["/code/app", "/code/site"]);
  expect(agentWorksOn(findAgent(id)!, "/code/site/")).toBe(true);
  removeAgentProject(id, "/code/app/");
  expect(findAgent(id)?.projects).toEqual(["/code/site"]);
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
    { id: "a-1", avatar: "ember", color: "hsl(211 92% 62%)", projects: ["/p"] },
  ]);
});

it("names its projects the way a sentence would", () => {
  const project = (name: string) => ({ path: `/code/${name}`, name });
  expect(agentProjectsPhrase([])).toBe("");
  expect(agentProjectsPhrase([project("app")])).toBe("app");
  expect(agentProjectsPhrase([project("app"), project("site")])).toBe(
    "app and site",
  );
  expect(
    agentProjectsPhrase([project("app"), project("site"), project("api")]),
  ).toBe("app, site and api");
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
          role: "assistant",
          text: "",
          tool: { title: "Run `npm test`" },
        },
      ] as never,
    }),
  ).toEqual({ status: "working", activity: "Run npm test" });
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

it("keeps the workdir and lists it before the other folders", async () => {
  const { agentFolders } = await import("./agent");
  const { id } = createAgent(["/code/app"]);
  updateAgent(id, (agent) => ({ ...agent, workdir: "/home/me/Loci/ember" }));
  const agent = findAgent(id)!;
  expect(agent.workdir).toBe("/home/me/Loci/ember");
  expect(agentFolders(agent)).toEqual(["/home/me/Loci/ember", "/code/app"]);
  updateAgent(id, (current) => ({ ...current, workdir: " " }));
  expect(findAgent(id)).not.toHaveProperty("workdir");
  expect(agentFolders(findAgent(id)!)).toEqual(["/code/app"]);
});
