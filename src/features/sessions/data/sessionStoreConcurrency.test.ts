import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";

const mocks = vi.hoisted(() => ({ invoke: vi.fn() }));

vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));

type Deferred<T> = {
  promise: Promise<T>;
  resolve: (value: T) => void;
};

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

async function loadStore() {
  vi.resetModules();
  return import("./sessionStore");
}

function session(id: string) {
  return {
    id,
    cwd: "/tmp/project",
    harness: "codex" as const,
    model: "",
    modelSettings: {},
    runtimeMode: "supervised" as const,
    title: "",
    blocks: [{ id: "user", role: "user" as const, text: "hello" }],
    busy: true,
  };
}

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
});

afterEach(() => {
  mocks.invoke.mockReset();
  vi.unstubAllGlobals();
});

describe("session persistence concurrency", () => {

  it("serializes deletion after an active write and drops a queued late upsert", async () => {
    const firstWrite = deferred<unknown>();
    const commands: string[] = [];
    mocks.invoke.mockImplementation((command: string) => {
      commands.push(command);
      if (command === "session_upsert") return firstWrite.promise;
      return Promise.resolve();
    });
    const { deleteSession, upsertSession } = await loadStore();
    const { needsAppContextReset, recordAppContext } = await import("../../agents/model/agentFiles");
    const { loadAgentRotation, saveAgentRotation } = await import("../../agents/model/agentRotation");
    recordAppContext("s1", "native-1");
    saveAgentRotation("s1", { at: 1, reason: "policy", earlier: ["Previous answer"] });

    const writing = upsertSession(session("s1"));
    await vi.waitFor(() => expect(commands).toEqual(["session_upsert"]));
    const lateWrite = upsertSession({ ...session("s1"), title: "late" });
    const deleting = deleteSession("s1");

    expect(commands).toEqual(["session_upsert"]);
    expect(needsAppContextReset("s1", "native-1")).toBe(false);
    expect(loadAgentRotation("s1")).toBeDefined();
    firstWrite.resolve({
      id: "s1",
      cwd: "/tmp/project",
      harness: "codex",
      model: "",
      runtimeMode: "supervised",
      title: "",
      createdAt: 1,
      updatedAt: 1,
    });
    await Promise.all([writing, lateWrite, deleting]);

    expect(commands).toEqual(["session_upsert", "session_delete"]);
    expect(needsAppContextReset("s1", "native-1")).toBe(true);
    expect(loadAgentRotation("s1")).toBeUndefined();
  });

  it("retains the context receipt and history brief when deletion fails", async () => {
    mocks.invoke.mockRejectedValue(new Error("disk"));
    const { deleteSession } = await loadStore();
    const { needsAppContextReset, recordAppContext } = await import("../../agents/model/agentFiles");
    const { loadAgentRotation, saveAgentRotation } = await import("../../agents/model/agentRotation");
    recordAppContext("s1", "native-1");
    const rotation = { at: 1, reason: "policy" as const, earlier: ["Previous answer"] };
    saveAgentRotation("s1", rotation);

    await expect(deleteSession("s1")).rejects.toThrow("disk");

    expect(needsAppContextReset("s1", "native-1")).toBe(false);
    expect(loadAgentRotation("s1")).toEqual(rotation);
  });

  it("discards a draft-only record before reusing its open session id", async () => {
    const firstWrite = deferred<unknown>();
    const commands: string[] = [];
    mocks.invoke.mockImplementation((command: string) => {
      commands.push(command);
      if (commands.length === 1) return firstWrite.promise;
      return Promise.resolve({
        id: "s1",
        cwd: "/tmp/project",
        harness: "codex",
        model: "",
        runtimeMode: "supervised",
        title: "",
        createdAt: 1,
        updatedAt: 1,
      });
    });
    const { discardDraftSessionRecord, upsertSession } = await loadStore();

    const draftWrite = upsertSession(session("s1"));
    await vi.waitFor(() => expect(commands).toEqual(["session_upsert"]));
    const discarding = discardDraftSessionRecord("s1");
    const laterTurn = upsertSession({ ...session("s1"), title: "later" });

    firstWrite.resolve(undefined);
    await Promise.all([draftWrite, discarding, laterTurn]);
    expect(commands).toEqual([
      "session_upsert",
      "session_delete",
      "session_upsert",
    ]);
  });

  it("drains queued saves before closing", async () => {
    const firstWrite = deferred<unknown>();
    mocks.invoke
      .mockReturnValueOnce(firstWrite.promise)
      .mockResolvedValue(undefined);
    const { flushSessionWrites, upsertSession } = await loadStore();
    const active = upsertSession(session("s1"));
    await vi.waitFor(() => expect(mocks.invoke).toHaveBeenCalledOnce());
    const queued = upsertSession({ ...session("s1"), title: "latest" });
    let flushed = false;
    const flushing = flushSessionWrites().then(() => {
      flushed = true;
    });
    await Promise.resolve();
    expect(flushed).toBe(false);
    firstWrite.resolve(undefined);
    await Promise.all([active, queued, flushing]);
    expect(mocks.invoke).toHaveBeenCalledTimes(2);
    expect(flushed).toBe(true);
  });

  it("archives only after the final active-turn snapshot is durable", async () => {
    const firstWrite = deferred<unknown>();
    const commands: string[] = [];
    mocks.invoke.mockImplementation((command: string) => {
      commands.push(command);
      if (command === "session_upsert" && commands.length === 1) {
        return firstWrite.promise;
      }
      return Promise.resolve({
        id: "s1",
        cwd: "/tmp/project",
        harness: "codex",
        model: "",
        runtimeMode: "supervised",
        title: "",
        createdAt: 1,
        updatedAt: 1,
      });
    });
    const { setSessionArchived, upsertSession } = await loadStore();

    const writing = upsertSession(session("s1"));
    await vi.waitFor(() => expect(commands).toEqual(["session_upsert"]));
    const finalSnapshot = upsertSession({
      ...session("s1"),
      blocks: [
        { id: "user", role: "user", text: "hello" },
        { id: "assistant", role: "assistant", text: "final buffered output" },
      ],
    });
    const archiving = setSessionArchived("s1", true);

    expect(commands).toEqual(["session_upsert"]);
    firstWrite.resolve({
      id: "s1",
      cwd: "/tmp/project",
      harness: "codex",
      model: "",
      runtimeMode: "supervised",
      title: "",
      createdAt: 1,
      updatedAt: 1,
    });
    await Promise.all([writing, finalSnapshot, archiving]);

    expect(commands).toEqual([
      "session_upsert",
      "session_upsert",
      "session_set_archived",
    ]);
    expect(mocks.invoke.mock.calls[1]?.[1]).toMatchObject({
      session: {
        blocks: [{ text: "hello" }, { text: "final buffered output" }],
      },
    });
  });
});
