// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const store = vi.hoisted(() => ({ sync: vi.fn(), remove: vi.fn() }));
vi.mock("./mentorStore", () => ({ queueRosterSync: store.sync, queueMentorRemoval: store.remove }));
// The soul file lives with the host; only the roster part of a reset matters here.
vi.mock("../../../platform/transport", () => ({
  transport: { call: vi.fn(async (command: string) => command === "agent_load" ? { soul: "", soulHash: "h", memory: "", memoryHash: "m", topics: [] } : "h2") },
}));

import {
  applyAgentChanges, createAgent, findAgent, listAgents, removeAgent, reorderAgents, setRosterHost, updateAgent, type Agent,
} from "./agent";

const ROSTER_KEY = "loci:agent-roster";
const ada: Agent = { id: "ada", name: "Ada", role: "Tutor", avatar: "ember", color: "#f28c28", projects: [] };
const bo: Agent = { id: "bo", name: "Bo", avatar: "wisp", color: "#111111", projects: [] };

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem(ROSTER_KEY, JSON.stringify([ada, bo]));
  store.sync.mockClear();
  store.remove.mockClear();
});
afterEach(() => setRosterHost(undefined));

describe("the roster in a window connected to another device", () => {
  const host = { update: vi.fn(), reorder: vi.fn() };
  beforeEach(() => {
    host.update.mockClear();
    host.reorder.mockClear();
    setRosterHost(host);
  });

  it("hands the host only the fields a change touched, and writes nothing here", () => {
    const before = localStorage.getItem(ROSTER_KEY);
    updateAgent("ada", (agent) => ({ ...agent, color: "#00aa00", role: "" }));
    expect(host.update).toHaveBeenCalledExactlyOnceWith("ada", { color: "#00aa00" }, ["role"]);
    expect(localStorage.getItem(ROSTER_KEY)).toBe(before);
    expect(store.sync).not.toHaveBeenCalled();
  });

  it("sends nothing for a change that changes nothing", () => {
    updateAgent("ada", (agent) => ({ ...agent }));
    expect(host.update).not.toHaveBeenCalled();
  });

  it("resets a mentor's name through the host, as the settings page's Reset does", async () => {
    const { resetAgentDefaults } = await import("./agentFiles");
    await resetAgentDefaults("ada");
    expect(host.update).toHaveBeenCalledExactlyOnceWith("ada", {}, ["name"]);
    expect(store.sync).not.toHaveBeenCalled();
  });

  it("asks the host to reorder, and refuses to add or remove a mentor here", () => {
    reorderAgents(["bo", "ada"]);
    expect(host.reorder).toHaveBeenCalledWith(["bo", "ada"]);
    expect(listAgents().map((agent) => agent.id)).toEqual(["ada", "bo"]);
    expect(() => createAgent()).toThrow("on the device that holds the mentors");
    expect(() => removeAgent("ada")).toThrow("on the device that holds the mentors");
    expect(store.sync).not.toHaveBeenCalled();
    expect(store.remove).not.toHaveBeenCalled();
  });
});

describe("the host applying a connected window's change", () => {
  it("keeps what the window did not change, even where the window's copy was behind", () => {
    // The host renamed Ada after the window last read the roster.
    updateAgent("ada", (agent) => ({ ...agent, name: "Ada Lovelace" }));
    applyAgentChanges("ada", { color: "#00aa00" }, ["role"]);
    expect(findAgent("ada")).toMatchObject({ id: "ada", name: "Ada Lovelace", color: "#00aa00", avatar: "ember" });
    expect(findAgent("ada")).not.toHaveProperty("role");
    expect(findAgent("bo")).toEqual(bo);
    applyAgentChanges("ada", { id: "evil" } as Partial<Agent>, ["id"]);
    expect(findAgent("ada")?.id).toBe("ada");
  });
});
