// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { agentLook, type Agent } from "./agent";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invoke(...args),
}));

import * as agentFiles from "./agentFiles";
import { loadAgentRotation } from "./agentRotation";
import { prepareAppTurn } from "./agentTurnContext";

const agent: Agent = { id: "agent", avatar: "wisp", color: "#fff", projects: [] };
const files = () => ({
  id: "agent",
  dir: "/data/agents/agent",
  soul: agentFiles.defaultSoul(),
  soulHash: "s1",
  memory: "",
  memoryHash: "m1",
  memoryPath: "/data/agents/agent/MEMORY.md",
  topics: [],
});

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
  invoke.mockReset();
  invoke.mockImplementation(async (command: string, args: { path?: string }) =>
    command === "agent_workdir_ensure" ? args.path : files());
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it.each([undefined, "  ", "小序", "Wisp"])(
  "provides the displayed name as identity without an automatic naming policy (%s)",
  async (name) => {
    const context = vi.spyOn(agentFiles, "agentContext");
    const named = { ...agent, name };
    const prepared = await prepareAppTurn(named, { id: "chat", blocks: [] }, { canRotate: false });

    expect(context).toHaveBeenCalledOnce();
    expect(context.mock.calls[0]).toHaveLength(3);
    expect(prepared.context[0]).toContain(agentLook(named).name);
    expect(prepared.context[0]).not.toContain("<agent_creation>");
    expect(named.name).toBe(name);
  },
);

it.each([
  { name: "小序" },
  { role: "Domain guide" },
  { projects: ["/code/app"] },
  { workdir: "/home/me/Loci-Dev/wisp" },
])("refreshes changed identity data without replacing the provider (%j)", async (change) => {
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  (await prepareAppTurn(agent, session, { canRotate: true })).record(session.providerSessionId);

  const changed = { ...agent, ...change };
  const refreshed = await prepareAppTurn(changed, session, { canRotate: true });
  expect(refreshed.introduces).toBe(true);
  expect(refreshed.rotates).toBe(false);
  expect(refreshed.context).toHaveLength(1);
  refreshed.record(session.providerSessionId);
  expect((await prepareAppTurn(changed, session, { canRotate: true })).context).toEqual([]);
});

it("does not refresh identity when the explicit name equals the displayed placeholder", async () => {
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  (await prepareAppTurn(agent, { ...session, providerSessionId: undefined }, { canRotate: false })).record(session.providerSessionId);
  const named = { ...agent, name: agentLook(agent).name };
  expect((await prepareAppTurn(named, session, { canRotate: false })).context).toEqual([]);
});

it("refreshes a changed Soul without replacing the provider", async () => {
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  (await prepareAppTurn(agent, session, { canRotate: true })).record(session.providerSessionId);
  invoke.mockResolvedValue({ ...files(), soul: "# Soul\n\nRead primary sources.", soulHash: "s2" });
  const refreshed = await prepareAppTurn(agent, session, { canRotate: true });
  expect(refreshed.introduces).toBe(true);
  expect(refreshed.rotates).toBe(false);
  expect(refreshed.context[0]).toContain("Read primary sources.");
});

function oldReceipt(provider: string | undefined = "native-1") {
  localStorage.setItem("loci:agent-handed", JSON.stringify({
    chat: { provider, soulHash: "s1:v8", memoryHash: "m1" },
  }));
}

it("replaces a provider carrying old global rules once while retaining the chat history", async () => {
  oldReceipt();
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    blocks: [
      { id: "u1", role: "user" as const, text: "Learn Kubernetes" },
      { id: "a1", role: "assistant" as const, text: "We agreed to start with Pods." },
    ],
  };
  const originalBlocks = [...session.blocks];
  const prepared = await prepareAppTurn(agent, session, { canRotate: true, now: 123 });

  expect(prepared.rotates).toBe(true);
  expect(prepared.introduces).toBe(true);
  expect(prepared.context[0]).toContain("Learn Kubernetes\n\nYou:\nWe agreed to start with Pods.");
  expect(session.blocks).toEqual(originalBlocks);
  expect(loadAgentRotation(session.id)).toBeUndefined();
  prepared.commitRotation();
  expect(loadAgentRotation(session.id)).toMatchObject({ at: 123, reason: "policy", afterBlockId: "a1" });
  prepared.record("native-2");

  const continued = await prepareAppTurn(agent, { ...session, providerSessionId: "native-2" }, { canRotate: true });
  expect(continued.rotates).toBe(false);
  expect(continued.context).toEqual([]);
});

it.each([undefined, "native-1"])("keeps policy reset pending when an edited turn retains the old provider (%s)", async (providerSessionId) => {
  oldReceipt();
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  const edited = await prepareAppTurn(agent, session, { canRotate: false });
  expect(edited.rotates).toBe(false);
  edited.record(providerSessionId);
  expect(agentFiles.needsAppContextReset(session.id, session.providerSessionId)).toBe(true);
  expect((await prepareAppTurn(agent, session, { canRotate: true })).rotates).toBe(true);
});

it("records the current policy after a model switch returns a different provider", async () => {
  oldReceipt();
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  const switched = await prepareAppTurn(agent, session, { canRotate: false });
  expect(switched.rotates).toBe(false);
  switched.record("native-2");
  const continued = await prepareAppTurn(agent, { ...session, providerSessionId: "native-2" }, { canRotate: true });
  expect(continued.rotates).toBe(false);
  expect(continued.context).toEqual([]);
});

it("does not reset a provider that has not been started yet", async () => {
  oldReceipt();
  const prepared = await prepareAppTurn(agent, { id: "chat", blocks: [] }, { canRotate: true });
  expect(prepared.rotates).toBe(false);
  expect(prepared.introduces).toBe(true);
});

it.each([agent, undefined])("resets an unrecorded provider after a failed switch (%j)", async (identity) => {
  oldReceipt();
  const prepared = await prepareAppTurn(identity, { id: "chat", providerSessionId: "failed-switch-provider", blocks: [] }, { canRotate: true });
  expect(prepared.rotates).toBe(true);
  prepared.commitRotation();
  prepared.record("clean-provider");
  expect((await prepareAppTurn(identity, { id: "chat", providerSessionId: "clean-provider", blocks: [] }, { canRotate: true })).rotates).toBe(false);
});

it("resets an existing provider with no context receipt because its policy is unknown", async () => {
  const prepared = await prepareAppTurn(agent, { id: "chat", providerSessionId: "native-1", blocks: [] }, { canRotate: true });
  expect(prepared.rotates).toBe(true);
  expect(prepared.introduces).toBe(true);
});

it("replaces an old plain-chat provider once with conversation excerpts and retains the UI transcript", async () => {
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    blocks: [
      { id: "u1", role: "user" as const, text: "Explain process scheduling" },
      { id: "a1", role: "assistant" as const, text: "We compared FIFO and round robin." },
    ],
  };
  const originalBlocks = [...session.blocks];
  const prepared = await prepareAppTurn(undefined, session, { canRotate: true, now: 123 });

  expect(prepared.rotates).toBe(true);
  expect(prepared.introduces).toBe(false);
  expect(prepared.context).toHaveLength(1);
  expect(prepared.context[0]).toContain("Explain process scheduling\n\nYou:\nWe compared FIFO and round robin.");
  expect(prepared.context[0]).not.toContain("<soul>");
  expect(prepared.context[0]).not.toContain("nothing was lost");
  expect(session.blocks).toEqual(originalBlocks);
  expect(invoke).not.toHaveBeenCalled();
  prepared.commitRotation();
  expect(loadAgentRotation(session.id)).toMatchObject({ reason: "policy", afterBlockId: "a1" });
  prepared.record("native-2");

  const continued = await prepareAppTurn(undefined, { ...session, providerSessionId: "native-2" }, { canRotate: true });
  expect(continued.rotates).toBe(false);
  expect(continued.context).toEqual([]);
});

it("adds no agent facts to a fresh plain-chat provider and records the current version", async () => {
  const session = { id: "chat", blocks: [] };
  const prepared = await prepareAppTurn(undefined, session, { canRotate: true });
  expect(prepared.context).toEqual([]);
  expect(prepared.rotates).toBe(false);
  expect(prepared.introduces).toBe(false);
  expect(invoke).not.toHaveBeenCalled();
  prepared.record("native-1");
  expect(agentFiles.needsAppContextReset(session.id, "native-1")).toBe(false);
  expect((await prepareAppTurn(undefined, { ...session, providerSessionId: "native-1" }, { canRotate: true })).context).toEqual([]);
});

it.each([undefined, "native-1"])("keeps plain-chat migration pending while an edited turn reuses the provider (%s)", async (providerSessionId) => {
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  const edited = await prepareAppTurn(undefined, session, { canRotate: false });
  expect(edited.rotates).toBe(false);
  expect(edited.context).toEqual([]);
  edited.record(providerSessionId);
  expect(agentFiles.needsAppContextReset(session.id, session.providerSessionId)).toBe(true);
  expect((await prepareAppTurn(undefined, session, { canRotate: true })).rotates).toBe(true);
});

it("records the current plain-chat context after a model switch returns a new provider", async () => {
  const session = { id: "chat", providerSessionId: "native-1", blocks: [] };
  const switched = await prepareAppTurn(undefined, session, { canRotate: false });
  switched.record("native-2");
  const continued = await prepareAppTurn(undefined, { ...session, providerSessionId: "native-2" }, { canRotate: true });
  expect(continued.rotates).toBe(false);
  expect(continued.context).toEqual([]);
});

it("leaves a current plain chat's context compaction to its provider", async () => {
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    context: { used: 180_000, window: 200_000 },
    blocks: [],
  };
  agentFiles.recordAppContext(session.id, session.providerSessionId);
  const prepared = await prepareAppTurn(undefined, session, { canRotate: true });
  expect(prepared.rotates).toBe(false);
  expect(prepared.context).toEqual([]);
});

it.each([agent, undefined])("retries a failed fresh-provider start with the original conversation excerpts (%j)", async (identity) => {
  oldReceipt();
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    blocks: [
      { id: "u1", role: "user" as const, text: "Design a scheduler" },
      { id: "a1", role: "assistant" as const, text: "We agreed to use a bounded queue." },
    ],
  };
  const originalBlocks = [...session.blocks];
  const first = await prepareAppTurn(identity, session, { canRotate: true });
  expect(first.rotates).toBe(true);
  first.commitRotation();
  // The old provider was forgotten; the replacement failed before binding an id.
  const unbound = {
    ...session,
    providerSessionId: undefined,
    blocks: [...session.blocks, { id: "u2", role: "user" as const, text: "Apply --dry-run" }],
  };
  const retry = await prepareAppTurn(identity, unbound, { canRotate: true });
  expect(retry.rotates).toBe(false);
  expect(retry.context[0]).toBe(first.context[0]);
  expect(retry.context[0]).toContain("Design a scheduler\n\nYou:\nWe agreed to use a bounded queue.");
  expect(retry.context.join("\n")).toContain("Apply --dry-run");
  expect(session.blocks).toEqual(originalBlocks);
  expect((await prepareAppTurn(identity, unbound, { canRotate: true })).context[0]).toBe(first.context[0]);

  retry.record("native-2");
  const continued = await prepareAppTurn(identity, { ...session, providerSessionId: "native-2" }, { canRotate: true });
  expect(continued.rotates).toBe(false);
  expect(continued.context).toEqual([]);
});

it.each([agent, undefined])("does not forget an already-bound replacement again after its first turn fails (%j)", async (identity) => {
  oldReceipt();
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    blocks: [
      { id: "u1", role: "user" as const, text: "Design a scheduler" },
      { id: "a1", role: "assistant" as const, text: "Use a bounded queue." },
    ],
  };
  const first = await prepareAppTurn(identity, session, { canRotate: true });
  first.commitRotation();
  const retry = await prepareAppTurn(identity, { ...session, providerSessionId: "native-2" }, { canRotate: true });
  expect(retry.rotates).toBe(false);
  expect(retry.context[0]).toBe(first.context[0]);
  retry.record("native-2");
  expect((await prepareAppTurn(identity, { ...session, providerSessionId: "native-2" }, { canRotate: true })).context).toEqual([]);
});

it.each([agent, undefined])("keeps an unaccepted rotation brief when editing still reuses the replaced provider (%j)", async (identity) => {
  oldReceipt();
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    blocks: [
      { id: "u1", role: "user" as const, text: "Design a scheduler" },
      { id: "a1", role: "assistant" as const, text: "Use a bounded queue." },
    ],
  };
  const first = await prepareAppTurn(identity, session, { canRotate: true });
  first.commitRotation();
  const edited = await prepareAppTurn(identity, session, { canRotate: false });
  expect(edited.rotates).toBe(false);
  edited.record(session.providerSessionId);

  const retry = await prepareAppTurn(identity, { ...session, providerSessionId: undefined }, { canRotate: true });
  expect(retry.context[0]).toBe(first.context[0]);
});

it.each([agent, undefined])("replaces a restored old provider even when a rotation brief is pending (%j)", async (identity) => {
  oldReceipt();
  const session = {
    id: "chat",
    providerSessionId: "native-1",
    blocks: [
      { id: "u1", role: "user" as const, text: "Design a scheduler" },
      { id: "a1", role: "assistant" as const, text: "Use a bounded queue." },
    ],
  };
  const first = await prepareAppTurn(identity, session, { canRotate: true });
  first.commitRotation();
  const restored = await prepareAppTurn(identity, session, { canRotate: true });
  expect(restored.rotates).toBe(true);
  expect(restored.context[0]).toBe(first.context[0]);
});

it("gives a mentor its workdir on its first turn and keeps it", async () => {
  const { createAgent, findAgent } = await import("./agent");
  const mentor = createAgent([], { name: "Lens" });
  invoke.mockImplementation(async (command: string, args: { slug?: string; path?: string }) =>
    command === "agent_workdir_create" ? `/home/me/Loci/${args.slug}`
      : command === "agent_workdir_ensure" ? args.path : files());
  const prepared = await prepareAppTurn(mentor, { id: "lens-chat", blocks: [] }, { canRotate: false });
  const identity = JSON.parse(prepared.context[0].match(/<agent>\n([\s\S]*?)\n<\/agent>/)![1]);
  expect(identity).toMatchObject({ workdir: "/home/me/Loci/lens", folders: [] });
  expect(findAgent(mentor.id)?.workdir).toBe("/home/me/Loci/lens");
});

it("still sends the turn when the workdir cannot be made", async () => {
  invoke.mockImplementation(async (command: string) => {
    if (command.startsWith("agent_workdir")) throw new Error("read-only disk");
    return files();
  });
  const prepared = await prepareAppTurn({ ...agent, workdir: "/gone" }, { id: "chat", blocks: [] }, { canRotate: false });
  expect(prepared.context[0]).toContain('"workdir": "/gone"');
});

const languageBlock = async (who: Agent) => {
  const turn = await prepareAppTurn(who, { id: "s-lang", blocks: [] }, { canRotate: false });
  return turn.context.find((part) => part.startsWith("<language>"));
};

it("tells every turn the learning language from Settings, and a mentor's own choice over it", async () => {
  expect(await languageBlock(agent)).toBeUndefined();
  localStorage.setItem("loci.learningLanguage", "zh-CN");
  expect(await languageBlock(agent)).toContain("Simplified Chinese (zh-CN)");
  expect(await languageBlock(agent)).toContain("comes before any language rule in your soul");
  expect(await languageBlock({ ...agent, language: "en" })).toContain("reads in English (en)");
  // "Follow my messages" for this mentor sends nothing, whatever Settings says.
  expect(await languageBlock({ ...agent, language: "auto" })).toBeUndefined();
});
