// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => invoke(...args) }));

import { createAgent, findAgent, updateAgent } from "./agent";
import { ensureAgentWorkdir, setAgentWorkdir, workdirSlug } from "./agentWorkdir";

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
    removeItem: (key: string) => stored.delete(key),
  });
  invoke.mockReset();
});
afterEach(() => vi.unstubAllGlobals());

it("names the folder after the mentor in plain lowercase words", () => {
  const base = { id: "a1b2c3d4-e5f6", avatar: "nova" };
  expect(workdirSlug({ ...base, name: "Repo Lens" })).toBe("repo-lens");
  expect(workdirSlug({ ...base, name: "  Crème  Brûlée!! " })).toBe("creme-brulee");
  expect(workdirSlug({ ...base, name: "沙箱导师" })).toBe("mentor-a1b2c3d4");
  expect(workdirSlug({ ...base, name: "repos" })).toBe("mentor-a1b2c3d4");
  expect(workdirSlug({ ...base, name: "x".repeat(60) })).toHaveLength(40);
  expect(workdirSlug({ ...base, name: `${"a".repeat(39)} b` })).toBe("a".repeat(39));
  // No name of its own: the avatar's.
  expect(workdirSlug(base)).toBe("nova");
});

it("creates the workdir once and remembers it", async () => {
  const { id } = createAgent([], { name: "Lens" });
  invoke.mockImplementation(async (command: string, args: { slug?: string; path?: string }) =>
    command === "agent_workdir_create" ? `/home/me/Loci/${args.slug}` : args.path);
  const [a, b] = await Promise.all([ensureAgentWorkdir(id), ensureAgentWorkdir(id)]);
  expect(a).toBe("/home/me/Loci/lens");
  expect(b).toBe(a);
  expect(invoke).toHaveBeenCalledTimes(1);
  expect(findAgent(id)?.workdir).toBe(a);
  // Later uses only make sure it is still there.
  expect(await ensureAgentWorkdir(id)).toBe(a);
  expect(invoke).toHaveBeenLastCalledWith("agent_workdir_ensure", { path: a });
});

it("keeps a workdir another window gave the mentor meanwhile", async () => {
  const { id } = createAgent([], { name: "Lens" });
  invoke.mockImplementation(async () => {
    updateAgent(id, (agent) => ({ ...agent, workdir: "/home/me/Loci/lens" }));
    return "/home/me/Loci/lens-2";
  });
  expect(await ensureAgentWorkdir(id)).toBe("/home/me/Loci/lens");
  expect(findAgent(id)?.workdir).toBe("/home/me/Loci/lens");
});

it("points a mentor at a folder the user already has", async () => {
  const { id } = createAgent();
  invoke.mockImplementation(async (_command: string, args: { path: string }) => args.path);
  await setAgentWorkdir(id, "/home/me/Loci/sandbox-study");
  expect(invoke).toHaveBeenCalledWith("agent_workdir_ensure", { path: "/home/me/Loci/sandbox-study" });
  expect(findAgent(id)?.workdir).toBe("/home/me/Loci/sandbox-study");
});

it("knows whether a chat's folder already holds the workdir", async () => {
  const { folderHolds } = await import("./agentWorkdir");
  expect(folderHolds("/home/me", "/home/me/Loci/lens")).toBe(true);
  expect(folderHolds("/home/me/", "/home/me")).toBe(true);
  expect(folderHolds("~", "/home/me/Loci/lens")).toBe(true);
  expect(folderHolds("/home/me/Loci/lens", "/home/me/Loci/lens-2")).toBe(false);
  expect(folderHolds("/home/me", "/Volumes/study")).toBe(false);
});
