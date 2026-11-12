// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { newSession, type Block, type Session } from "../../sessions/model/session";
import { createAgent, findAgent, removeAgent, saveAgentDefaults, saveAgentSessionId } from "./agent";
import { loadNewAgentAccess, markAgentAccessMigrated, saveNewAgentAccess } from "./agentAccess";
import { planAgentContext, recordAgentContext } from "./agentFiles";
import { loadAgentRotation } from "./agentRotation";
import { clearAgentContext, ensureAgentSession, sessionFromDefaults } from "./agentWorkspace";

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
    removeItem: (key: string) => stored.delete(key),
  });
});
afterEach(() => vi.unstubAllGlobals());

function host(saved: Session[] = []) {
  const added: Session[] = [];
  return {
    added,
    home: vi.fn(async () => "/home/me"),
    workdir: vi.fn(async (_id: string): Promise<string> => { throw new Error("no folder"); }),
    load: vi.fn(async (id: string) => saved.find((session) => session.id === id)),
    create: vi.fn((cwd: string) => newSession("codex", cwd, "codex:test")),
    add: vi.fn((session: Session) => void added.push(session)),
  };
}

it("starts an agent's conversation once, at home with Full access", async () => {
  const { id } = createAgent();
  const first = host();
  const [a, b] = await Promise.all([
    ensureAgentSession(id, first),
    ensureAgentSession(id, first),
  ]);
  expect(a).toBe(b);
  expect(first.create).toHaveBeenCalledTimes(1);
  expect(a).toMatchObject({ cwd: "/home/me", runtimeMode: "full-access" });
  expect(findAgent(id)?.sessionId).toBe(a!.id);
  expect(first.added).toEqual([a]);
});

it("starts new mentors with the default chosen for new mentors", async () => {
  saveNewAgentAccess("supervised");
  expect(loadNewAgentAccess()).toBe("supervised");
  const { id } = createAgent();
  const session = (await ensureAgentSession(id, host()))!;
  expect(session.runtimeMode).toBe("supervised");
  // Reopening a mentor created now does not migrate it to Full access.
  const again = host([session]);
  expect(await ensureAgentSession(id, again)).toMatchObject({ runtimeMode: "supervised" });
});

it("switches an existing mentor's saved chat to Full access once", async () => {
  const { id } = createAgent();
  saveAgentSessionId(id, "old-chat");
  const saved = { ...newSession("codex", "/home/me", "codex:test", "auto"), id: "old-chat" };
  const migrated = await ensureAgentSession(id, host([saved]));
  expect(migrated).toMatchObject({ id: "old-chat", runtimeMode: "full-access" });
  expect(findAgent(id)?.accessMigrated).toBe(true);
});

it("keeps a permission mode chosen after the migration", async () => {
  const { id } = createAgent();
  saveAgentSessionId(id, "old-chat");
  const saved = { ...newSession("codex", "/home/me", "codex:test", "auto"), id: "old-chat" };
  await ensureAgentSession(id, host([saved]));
  // The user picks Supervised in the mentor's settings after the switch.
  const chosen = { ...saved, runtimeMode: "supervised" as const };
  markAgentAccessMigrated(id);
  expect(await ensureAgentSession(id, host([chosen]))).toMatchObject({ runtimeMode: "supervised" });
});

it("starts a new agent's conversation in its workdir", async () => {
  const { id } = createAgent();
  const opening = host();
  opening.workdir.mockImplementation(async () => "/home/me/Loci/ember");
  expect(await ensureAgentSession(id, opening)).toMatchObject({ cwd: "/home/me/Loci/ember" });
  expect(opening.home).not.toHaveBeenCalled();
});

it("keeps a saved conversation in the folder it started in", async () => {
  const { id } = createAgent();
  const session = (await ensureAgentSession(id, host()))!;
  const again = host([session]);
  again.workdir.mockImplementation(async () => "/home/me/Loci/ember");
  expect(await ensureAgentSession(id, again)).toMatchObject({ cwd: "/home/me" });
  expect(again.workdir).not.toHaveBeenCalled();
});

it("starts a new chat from the mentor's stored defaults, even when the catalog does not know the model yet", async () => {
  const { id } = createAgent();
  saveAgentDefaults(id, {
    provider: "grok",
    model: "grok:deepseek-flash",
    mode: "full-access",
    effort: "high",
    modelSettings: { effort: "high" },
  });
  // The empty conversation a create makes is released, so `load` finds nothing.
  const fresh = (await ensureAgentSession(id, host()))!;
  expect(fresh).toMatchObject({
    harness: "grok",
    model: "grok:deepseek-flash",
    runtimeMode: "full-access",
    modelSettings: { effort: "high" },
  });
  // The conversation that is opened keeps the saved defaults on the mentor.
  expect(findAgent(id)?.defaults?.model).toBe("grok:deepseek-flash");
  // A saved chat is resumed as it is, without being re-seeded.
  const again = host([fresh]);
  expect(await ensureAgentSession(id, again)).toBe(fresh);
});

it("builds a session from defaults without a catalog entry", () => {
  const session = sessionFromDefaults("/home/me", {
    provider: "grok",
    model: "grok:magpie/custom-model",
    mode: "supervised",
    modelSettings: { effort: "low" },
  });
  expect(session).toMatchObject({ harness: "grok", model: "grok:magpie/custom-model", runtimeMode: "supervised", modelSettings: { effort: "low" } });
});

it("comes back to the same conversation, and starts over only when it is gone", async () => {
  const { id } = createAgent();
  const session = (await ensureAgentSession(id, host()))!;
  const again = host([session]);
  expect(await ensureAgentSession(id, again)).toBe(session);
  expect(again.create).not.toHaveBeenCalled();
  expect(again.added).toEqual([session]);
  const lost = host();
  const fresh = await ensureAgentSession(id, lost);
  expect(fresh!.id).not.toBe(session.id);
  expect(findAgent(id)?.sessionId).toBe(fresh!.id);
});

it("opens nothing for an agent removed meanwhile", async () => {
  const { id } = createAgent();
  const slow = host();
  slow.home.mockImplementation(async () => {
    removeAgent(id);
    return "/home/me";
  });
  expect(await ensureAgentSession(id, slow)).toBeUndefined();
  expect(slow.added).toEqual([]);
  expect(await ensureAgentSession("missing", host())).toBeUndefined();
});

function clearing(session: Session, workdir?: () => Promise<string>) {
  const order: string[] = [];
  let current = session;
  const run = () => clearAgentContext(current, {
    ...(workdir ? { workdir } : {}),
    stop: async () => void order.push("stop"),
    forget: async () => void order.push("forget"),
    update: (_id, change) => { current = change(current); },
  }, 42);
  return { order, run, current: () => current };
}

it("starts over in the same chat: the messages stay, a divider follows, and the provider is dropped", async () => {
  const { id } = createAgent();
  const said: Block[] = [
    { id: "u1", role: "user", text: "What is a sandbox?" },
    { id: "a1", role: "assistant", text: "An isolated place to run code." },
  ];
  const session: Session = { ...(await ensureAgentSession(id, host()))!, blocks: said, providerSessionId: "thread-1" };
  const files = { soulHash: "s", memoryHash: "m" };
  recordAgentContext(session.id, "thread-1", files);
  const clear = clearing(session);
  expect(await clear.run()).toBe(true);
  expect(clear.order).toEqual(["stop", "forget"]);
  const after = clear.current();
  expect(after.id).toBe(session.id);
  expect(after.blocks.slice(0, 2)).toEqual(said);
  expect(after.blocks[2]).toMatchObject({ role: "divider", startedAt: 42 });
  expect(after.providerSessionId).toBeUndefined();
  expect(findAgent(id)?.sessionId).toBe(session.id);
  // The fresh provider is told who it is again, with no brief of the chat above.
  expect(planAgentContext(session.id, undefined, files).soul).toBe(true);
  expect(loadAgentRotation(session.id)).toMatchObject({ afterBlockId: after.blocks[2].id, earlier: [] });
  // A second `/new` with nothing said since adds nothing.
  expect(await clearing(after).run()).toBe(false);
});

it("moves the chat into the workdir when it starts over, and keeps its folder when that cannot be made", async () => {
  const { id } = createAgent();
  const session: Session = { ...(await ensureAgentSession(id, host()))!, blocks: [{ id: "u1", role: "user", text: "hi" }] };
  const moved = clearing(session, async () => "/home/me/Loci/ember");
  await moved.run();
  expect(moved.current().cwd).toBe("/home/me/Loci/ember");
  const kept = clearing({ ...moved.current(), blocks: [...moved.current().blocks, { id: "u2", role: "user", text: "again" }] },
    async () => { throw new Error("gone"); });
  await kept.run();
  expect(kept.current().cwd).toBe("/home/me/Loci/ember");
});
