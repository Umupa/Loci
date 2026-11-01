// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { newSession, type Session } from "../../sessions/model/session";
import { createAgent, findAgent, removeAgent, saveAgentDefaults, saveAgentSessionId } from "./agent";
import { loadNewAgentAccess, markAgentAccessMigrated, saveNewAgentAccess } from "./agentAccess";
import { planAgentContext, recordAgentContext } from "./agentFiles";
import { defaultsFromSession, ensureAgentSession, resetAgentSession, sessionFromDefaults } from "./agentWorkspace";

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
  const { id } = createAgent(["/code/app"]);
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

it("moves a chat into the workdir when it is reset", async () => {
  const { id } = createAgent();
  const session = (await ensureAgentSession(id, host()))!;
  const fresh = await resetAgentSession(session, {
    workdir: async () => "/home/me/Loci/ember",
    stop: async () => undefined,
    remove: async () => undefined,
    replace: () => undefined,
  });
  expect(fresh.cwd).toBe("/home/me/Loci/ember");
  const kept = await resetAgentSession(fresh, {
    workdir: async () => { throw new Error("gone"); },
    stop: async () => undefined,
    remove: async () => undefined,
    replace: () => undefined,
  });
  expect(kept.cwd).toBe("/home/me/Loci/ember");
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

it("resets a mentor's chat to its stored defaults, and to the chat's own settings without them", async () => {
  const withDefaults = createAgent();
  saveAgentDefaults(withDefaults.id, {
    provider: "codex", model: "codex:test", mode: "auto", effort: "high", modelSettings: { effort: "high" },
  });
  const chat = (await ensureAgentSession(withDefaults.id, host()))!;
  expect(defaultsFromSession(chat).modelSettings).toEqual({ effort: "high" });
  const fresh = await resetAgentSession(chat, {
    stop: async () => undefined,
    remove: async () => undefined,
    replace: () => undefined,
  });
  expect(fresh).toMatchObject({ harness: "codex", model: "codex:test", runtimeMode: "auto" });

  const plain = createAgent();
  const own = (await ensureAgentSession(plain.id, host()))!;
  const kept = await resetAgentSession(own, {
    stop: async () => undefined,
    remove: async () => undefined,
    replace: () => undefined,
  });
  expect(kept).toMatchObject({ harness: own.harness, model: own.model, runtimeMode: own.runtimeMode });
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

it("resets the chat alone: a fresh conversation that is told who it is again", async () => {
  const { id } = createAgent();
  const session = {
    ...(await ensureAgentSession(id, host()))!,
    model: "codex:other",
    modelSettings: { effort: "high" },
  };
  saveAgentDefaults(id, {
    provider: "codex", model: "codex:other", mode: "full-access", effort: "high", modelSettings: { effort: "high" },
  });
  const files = { soulHash: "s", memoryHash: "m" };
  recordAgentContext(session.id, "thread-1", files);
  expect(planAgentContext(session.id, "thread-1", files).soul).toBe(false);
  const order: string[] = [];
  const fresh = await resetAgentSession(session, {
    stop: async () => void order.push("stop"),
    remove: async () => void order.push("remove"),
    replace: () => void order.push("replace"),
  });
  expect(order).toEqual(["stop", "remove", "replace"]);
  expect(fresh).toMatchObject({
    cwd: "/home/me",
    model: "codex:other",
    modelSettings: { effort: "high" },
    runtimeMode: "full-access",
    blocks: [],
  });
  expect(findAgent(id)?.sessionId).toBe(fresh.id);
  expect(planAgentContext(session.id, "thread-1", files).soul).toBe(true);
});

it("keeps the conversation when it could not be deleted", async () => {
  const { id } = createAgent();
  const session = (await ensureAgentSession(id, host()))!;
  await expect(
    resetAgentSession(session, {
      stop: async () => undefined,
      remove: async () => {
        throw new Error("disk");
      },
      replace: () => undefined,
    }),
  ).rejects.toThrow("disk");
  expect(findAgent(id)?.sessionId).toBe(session.id);
});
