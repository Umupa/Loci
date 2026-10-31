import { afterEach,describe,expect,it,vi } from "vitest";
import { newSession,type Session } from "./session";
import { createSessionRemover, type SessionRemoval } from "./sessionRemoval";

const mocks = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

function fixture(mode: "archive" | "delete") {
  const closing: Session = {
    ...newSession("codex", "/tmp/project"),
    busy: true,
    blocks: [
      { id: "user", role: "user", text: "hello" },
      { id: "answer", role: "assistant", text: "partial", streaming: true },
    ],
    queuedMessages: [{ id: "queued", text: "next", attachments: [] }],
    queueStatus: "active",
  };
  const other = newSession("codex", "/tmp/project");
  let state = { sessions: [closing, other] };
  const confirmClose = vi.fn(async () => true);
  const stop = vi.fn(async () => {});
  const commit = vi.fn((removal: SessionRemoval) => {
    state = { ...state, ...removal };
  });
  mocks.invoke.mockImplementation(async (command, args) => {
    if (command === "session_upsert") {
      return { ...args.session, createdAt: 1, updatedAt: 1 };
    }
  });
  return {
    closing,
    other,
    read: () => state,
    write: (next: typeof state) => {
      state = next;
    },
    confirmClose,
    stop,
    commit,
    run: () => {
      const remover = createSessionRemover({
        mode,
        replacement: { cwd: "/tmp/project", harness: "codex" },
        workspace: {
          snapshot: () => state,
          apply: (change) => {
            if (change.type === "removed") {
              commit(change.removal);
              return;
            }
            state = {
              ...state,
              sessions: state.sessions.map((session) =>
                session.id === change.session.id ? change.session : session,
              ),
            };
          },
        },
        confirm: confirmClose,
        stop,
      });
      return remover.remove(closing.id);
    },
  };
}

afterEach(() => mocks.invoke.mockReset());

describe.each(["archive", "delete"] as const)("%s lifecycle", (mode) => {
  it("removes only that session, leaving no replacement behind", async () => {
    const f = fixture(mode);
    expect(await f.run()).toBe(true);
    expect(f.read().sessions).toEqual([f.other]);
  });

  it("preserves another agent's completion and new sessions across both waits", async () => {
    const f = fixture(mode);
    const confirm = deferred();
    const saving = deferred();
    f.confirmClose.mockImplementation(async () => {
      await confirm.promise;
      return true;
    });
    mocks.invoke.mockImplementation(async (command, args) => {
      await saving.promise;
      return command === "session_upsert"
        ? { ...args.session, createdAt: 1, updatedAt: 1 }
        : undefined;
    });
    const pending = f.run();
    const updated = {
      ...f.other,
      busy: false,
      blocks: [{ id: "done", role: "assistant" as const, text: "finished" }],
    };
    f.write({ ...f.read(), sessions: [f.closing, updated] });
    confirm.resolve();
    await vi.waitFor(() => expect(mocks.invoke).toHaveBeenCalled());
    const added = newSession("codex", "/tmp/project");
    f.write({ ...f.read(), sessions: [...f.read().sessions, added] });
    saving.resolve();
    await pending;
    expect(f.read().sessions).toEqual([updated, added]);
  });

  it("retains a stopped session and paused queue when storage fails", async () => {
    const f = fixture(mode);
    mocks.invoke.mockRejectedValue(new Error("disk unavailable"));
    await expect(f.run()).rejects.toThrow("disk unavailable");
    expect(f.stop).toHaveBeenCalledOnce();
    expect(f.commit).not.toHaveBeenCalled();
    expect(f.read().sessions[0]).toMatchObject({
      busy: false,
      queueStatus: "paused",
    });
    expect(f.read().sessions[0].blocks[1].streaming).toBeFalsy();
    expect(f.read().sessions).toHaveLength(2);
  });

  it("does not stop or write anything if confirmation is declined", async () => {
    const f = fixture(mode);
    f.confirmClose.mockResolvedValue(false);
    expect(await f.run()).toBe(false);
    expect(f.stop).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
    expect(f.read().sessions[0].busy).toBe(true);
  });
});

it("archives the flushed transcript after cancellation, with streaming stopped", async () => {
  const f = fixture("archive");
  f.stop.mockImplementation(async () => {
    f.write({
      ...f.read(),
      sessions: f.read().sessions.map((s) =>
        s.id === f.closing.id
          ? {
              ...s,
              blocks: [
                ...s.blocks,
                {
                  id: "buffered",
                  role: "assistant",
                  text: "last buffered output",
                  streaming: true,
                },
              ],
            }
          : s,
      ),
    });
  });
  await f.run();
  const [command, args] = mocks.invoke.mock.calls[0];
  expect(command).toBe("session_upsert");
  expect(args.session.blocks.at(-1)).toMatchObject({
    text: "last buffered output",
  });
  expect(args.session.blocks.at(-1).streaming).toBeFalsy();
  expect(mocks.invoke.mock.calls.map(([name]) => name)).toEqual([
    "session_upsert",
    "session_set_archived",
  ]);
});
