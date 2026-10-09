// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { newSession, type Session } from "../../sessions/model/session";
import { createAgent, findAgent, removeAgent } from "./agent";
import { planAgentContext, recordAgentContext } from "./agentFiles";
import { ensureAgentSession, resetAgentSession } from "./agentWorkspace";

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
    load: vi.fn(async (id: string) => saved.find((session) => session.id === id)),
    create: vi.fn((cwd: string) => newSession("codex", cwd, "codex:test")),
    add: vi.fn((session: Session) => void added.push(session)),
  };
}

it("starts an agent's conversation once, at home with Auto permissions", async () => {
  const { id } = createAgent(["/code/app"]);
  const first = host();
  const [a, b] = await Promise.all([
    ensureAgentSession(id, first),
    ensureAgentSession(id, first),
  ]);
  expect(a).toBe(b);
  expect(first.create).toHaveBeenCalledTimes(1);
  expect(a).toMatchObject({ cwd: "/home/me", runtimeMode: "auto" });
  expect(findAgent(id)?.sessionId).toBe(a!.id);
  expect(first.added).toEqual([a]);
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
    runtimeMode: "auto",
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
