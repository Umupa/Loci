import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { forgetHarnessSession } from "../../integrations/harness/core/registry";
import { killAllChildren } from "../../integrations/harness/core/child";
import { newSession } from "../../features/sessions/model/session";
import { setFileDraft } from "../../features/files/model/fileDrafts";
import {
  askQuitConfirmation,
  closeBusyWindow,
  confirmDiscardFileDrafts,
  persistAndCloseWindow,
  persistQuitState,
  commitQuit,
  reportQuitPoll,
  setQuitWorkspace,
} from "./appLifecycle";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({
  ask: vi.fn().mockResolvedValue(true),
}));
vi.mock("../../features/sessions/data/sessionStore", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../features/sessions/data/sessionStore")>();
  return {
    ...actual,
    loadWorkspaceSnapshot: vi.fn().mockResolvedValue(null),
    listInFlightSessions: vi.fn().mockResolvedValue([]),
    listSessionsByProject: vi.fn().mockResolvedValue([]),
    getSession: vi.fn().mockResolvedValue(null),
  };
});
vi.mock("../../integrations/harness/core/registry", () => ({
  bindHarnessSession: vi.fn(),
  isLiveHarness: vi.fn(),
  forgetHarnessSession: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("../../integrations/harness/core/child", () => ({
  killAllChildren: vi.fn().mockResolvedValue(undefined),
}));

describe("closing with unsaved file edits", () => {
  const draft = { text: "edited", base: "saved" };
  afterEach(() => {
    setFileDraft("/repo/src/main.rs", null);
    vi.mocked(ask).mockReset().mockResolvedValue(true);
  });

  it("closes without asking when nothing is unsaved", async () => {
    await expect(confirmDiscardFileDrafts(false)).resolves.toBe(true);
    expect(ask).not.toHaveBeenCalled();
  });

  it("keeps edits when the window only hides to the tray", async () => {
    setFileDraft("/repo/src/main.rs", draft);
    await expect(confirmDiscardFileDrafts(true)).resolves.toBe(true);
    expect(ask).not.toHaveBeenCalled();
  });

  it("asks once before discarding unsaved edits", async () => {
    setFileDraft("/repo/src/main.rs", draft);
    vi.mocked(ask).mockResolvedValueOnce(false);
    await expect(confirmDiscardFileDrafts(false)).resolves.toBe(false);
    expect(ask).toHaveBeenCalledWith(
      "Close Loci and discard unsaved changes to your files?",
      expect.objectContaining({ kind: "warning", okLabel: "Discard changes", cancelLabel: "Keep editing" }),
    );

    vi.mocked(ask).mockResolvedValueOnce(true);
    await expect(confirmDiscardFileDrafts(false)).resolves.toBe(true);
  });
});

describe("idle window close persistence", () => {
  beforeEach(() => { vi.mocked(invoke).mockReset().mockResolvedValue(undefined); });

  it.each([false, true])("waits for durable state before closing (toTray=%s)", async (toTray) => {
    let saved!: () => void;
    const persistence = new Promise<void>((resolve) => { saved = resolve; });
    const closing = persistAndCloseWindow(() => persistence, toTray);
    await Promise.resolve();
    expect(invoke).not.toHaveBeenCalled();
    saved();
    await closing;
    expect(invoke).toHaveBeenCalledExactlyOnceWith(toTray ? "hide_window" : "destroy_window");
  });

  it.each([false, true])("keeps the window open after failure and permits retry (toTray=%s)", async (toTray) => {
    const persist = vi.fn().mockRejectedValueOnce(new Error("disk unavailable")).mockResolvedValue(undefined);
    await expect(persistAndCloseWindow(persist, toTray)).rejects.toThrow("disk unavailable");
    expect(invoke).not.toHaveBeenCalled();
    await persistAndCloseWindow(persist, toTray);
    expect(invoke).toHaveBeenCalledExactlyOnceWith(toTray ? "hide_window" : "destroy_window");
  });

  it("does not close when the actual session write fails", async () => {
    const session = { ...newSession("codex", "/project"), blocks: [{ id: "user", role: "user" as const, text: "Unsaved" }] };
    vi.mocked(invoke).mockImplementation(async (command) => {
      if (command === "session_upsert") throw new Error("write failed");
    });
    await expect(persistAndCloseWindow(() => persistQuitState([session], "transition"), false)).rejects.toThrow("write failed");
    expect(invoke).not.toHaveBeenCalledWith("destroy_window");
  });

  it("does not erase other windows' in-flight records when an idle window closes", async () => {
    const session = newSession("codex", "/project");
    await persistAndCloseWindow(() => persistQuitState([session], "transition"), false);
    // The tab layout earlier versions saved is no longer written.
    expect(invoke).not.toHaveBeenCalledWith("workspace_set_snapshot", expect.anything());
    expect(invoke).toHaveBeenCalledWith("destroy_window");
    expect(invoke).not.toHaveBeenCalledWith("session_set_in_flight", expect.anything());
  });
});

describe("closing a busy window", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(ask).mockResolvedValue(true);
  });

  function workspace() {
    const session = newSession("codex", "C:/test");
    session.busy = true;
    session.blocks = [{ id: "user", role: "user", text: "test" }];
    const release = setQuitWorkspace(() => [session], vi.fn());
    return { session, release };
  }

  it("stops only its sessions and destroys only its window", async () => {
    const { session, release } = workspace();
    try {
      await closeBusyWindow();
      expect(ask).toHaveBeenCalled();
      expect(forgetHarnessSession).toHaveBeenCalledWith("codex", session.id);
      expect(killAllChildren).not.toHaveBeenCalled();
      expect(invoke).toHaveBeenCalledWith("destroy_window");
      expect(
        vi
          .mocked(invoke)
          .mock.calls.some(([command]) => command === "confirm_quit"),
      ).toBe(false);
    } finally {
      release();
    }
  });

  it("stops both providers during an implicit model switch", async () => {
    const { session, release } = workspace();
    session.pendingSwitch = {
      from: "claude",
      fromModel: "claude:sonnet",
      fromSettings: {},
      fromProviderSessionId: "previous-thread",
    };
    try {
      await closeBusyWindow();
      expect(forgetHarnessSession).toHaveBeenCalledWith("codex", session.id);
      expect(forgetHarnessSession).toHaveBeenCalledWith("claude", session.id);
      expect(killAllChildren).not.toHaveBeenCalled();
      expect(invoke).toHaveBeenCalledWith("destroy_window");
    } finally {
      release();
    }
  });

  it("leaves the window and sessions running when closing is cancelled", async () => {
    const { release } = workspace();
    vi.mocked(ask).mockResolvedValue(false);
    try {
      await closeBusyWindow();
      expect(forgetHarnessSession).not.toHaveBeenCalled();
      expect(killAllChildren).not.toHaveBeenCalled();
      expect(invoke).not.toHaveBeenCalled();
    } finally {
      release();
    }
  });
});

describe("coordinated quit", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(ask).mockResolvedValue(true);
  });

  function busyWorkspace() {
    const session = newSession("codex", "C:/test");
    session.busy = true;
    session.blocks = [{ id: "user", role: "user", text: "test" }];
    return setQuitWorkspace(() => [session], vi.fn());
  }

  function invokedWith(command: string) {
    return vi
      .mocked(invoke)
      .mock.calls.find(([name]) => name === command)?.[1];
  }

  it("reports this window's live turns to the coordinator", async () => {
    const release = busyWorkspace();
    try {
      await reportQuitPoll(7);
      expect(invokedWith("quit_poll_reply")).toEqual({ id: 7, inFlight: 1 });
    } finally {
      release();
    }
  });

  it("reports nothing from a window with no workspace yet", async () => {
    await reportQuitPoll(2);
    expect(invokedWith("quit_poll_reply")).toEqual({ id: 2, inFlight: 0 });
  });

  it("passes a declined dialog back as a refusal", async () => {
    vi.mocked(ask).mockResolvedValue(false);
    await askQuitConfirmation(3, 2);
    expect(invokedWith("quit_decision")).toEqual({ id: 3, confirmed: false });
  });

  it("asks once using the count from every window", async () => {
    await askQuitConfirmation(4, 5);
    expect(ask).toHaveBeenCalledTimes(1);
    expect(vi.mocked(ask).mock.calls[0]?.[0]).toContain("5");
    expect(invokedWith("quit_decision")).toEqual({ id: 4, confirmed: true });
  });

  it("tells the coordinator when a required quit write fails", async () => {
    const release = busyWorkspace();
    vi.mocked(invoke).mockImplementation((command) =>
      command === "session_set_in_flight"
        ? Promise.reject(new Error("disk full"))
        : Promise.resolve(undefined),
    );
    try {
      await commitQuit(6);
      expect(invokedWith("quit_ready")).toEqual({ id: 6, persisted: false });
    } finally {
      vi.mocked(invoke).mockResolvedValue(undefined);
      release();
    }
  });

  // The whole point of the handshake: no window exits on its own.
  it("persists and reports ready without exiting the app", async () => {
    const release = busyWorkspace();
    try {
      await commitQuit(9);
      expect(invokedWith("session_set_in_flight")).toBeDefined();
      expect(invokedWith("quit_ready")).toEqual({ id: 9, persisted: true });
      expect(
        vi
          .mocked(invoke)
          .mock.calls.some(([command]) => command === "confirm_quit"),
      ).toBe(false);
    } finally {
      release();
    }
  });
});
