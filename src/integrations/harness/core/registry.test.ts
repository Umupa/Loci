import { afterEach,describe,expect,it,vi } from "vitest";
import {
resetHarnessModelOverlays,
setHarnessModels,
} from "../../../features/sessions/model/models";
import type { HarnessId } from "../../../features/sessions/model/session";
import { registerBuiltinHarnesses } from "./register";
import {
HARNESS_IDLE_PARK_MS,
bindHarnessSession,
canCompactHarnessContext,
canRewindHarnessLastTurn,
canRunHarnessTextPrompt,
compactHarnessContext,
isLiveHarness,
listHarnesses,
refreshHarnessCatalogs,
registerHarness,
resetHarnessIdlePark,
runHarnessTextPrompt,
sendHarnessTurn,
type HarnessAdapter,
} from "./registry";
import type { SendTurnInput,SteerTurnInput } from "./types";

function stub(
  id: HarnessId,
  extra: Partial<HarnessAdapter> = {},
): HarnessAdapter {
  return {
    id,
    live: true,
    async sendTurn(_input: SendTurnInput) {},
    async steerTurn(_input: SteerTurnInput) {},
    async cancelTurn() {},
    respondApproval() {},
    async stopSession() {},
    async forgetSession() {},
    bindSession() {},
    ...extra,
  };
}

describe("harness registry", () => {
  afterEach(() => {
    resetHarnessModelOverlays();
    resetHarnessIdlePark();
    vi.useRealTimers();
  });

  it("tracks live adapters", () => {
    registerHarness(stub("codex"));
    registerHarness(stub("claude"));
    expect(isLiveHarness("codex")).toBe(true);
    expect(isLiveHarness("claude")).toBe(true);
    expect(listHarnesses().map((a) => a.id).sort()).toEqual(["claude", "codex"]);
  });

  it("advertises isolated text prompt support by harness", () => {
    registerBuiltinHarnesses();
    const ids: HarnessId[] = [
      "claude",
      "codex",
    ];

    expect(
      Object.fromEntries(ids.map((id) => [id, canRunHarnessTextPrompt(id)])),
    ).toEqual({
      claude: true,
      codex: true,
    });
  });

  it("exposes the native compaction support matrix", () => {
    registerBuiltinHarnesses();
    const ids: HarnessId[] = [
      "claude",
      "codex",
    ];

    expect(
      Object.fromEntries(ids.map((id) => [id, canCompactHarnessContext(id)])),
    ).toEqual({
      claude: true,
      codex: true,
    });
  });
  it("advertises and dispatches compaction only when an adapter supports it", async () => {
    const compactContext = vi.fn(async () => undefined);
    registerHarness(stub("codex", { compactContext }));
    registerHarness(stub("claude"));

    expect(canCompactHarnessContext("codex")).toBe(true);
    expect(canCompactHarnessContext("claude")).toBe(false);

    await compactHarnessContext({
      harness: "codex",
      sessionId: "compact-1",
      cwd: "/tmp",
      model: "codex:gpt-5.4",
      runtimeMode: "supervised",
      onEvent: () => undefined,
    });

    expect(compactContext).toHaveBeenCalledOnce();
    await expect(
      compactHarnessContext({
        harness: "claude",
        sessionId: "compact-2",
        cwd: "/tmp",
        model: "claude:sonnet",
        runtimeMode: "supervised",
        onEvent: () => undefined,
      }),
    ).rejects.toThrow("does not support manual compaction");
  });
  it("cancels an isolated text prompt through the adapter lifecycle", async () => {
    const runTextPrompt = vi.fn(() => new Promise<string>(() => undefined));
    const stopTextPrompt = vi.fn(async () => undefined);
    registerHarness(stub("claude", { runTextPrompt, stopTextPrompt }));
    const controller = new AbortController();
    const request = runHarnessTextPrompt({
      harness: "claude",
      cwd: "/tmp",
      prompt: "read-only question",
      signal: controller.signal,
    });

    controller.abort();

    await expect(request).rejects.toThrow("By-the-way request cancelled");
    expect(runTextPrompt).toHaveBeenCalledOnce();
    expect(stopTextPrompt).not.toHaveBeenCalled();
  });

  it("does not stop the shared text backend while another prompt is active", async () => {
    const runTextPrompt = vi.fn(() => new Promise<string>(() => undefined));
    const stopTextPrompt = vi.fn(async () => undefined);
    registerHarness(stub("claude", { runTextPrompt, stopTextPrompt }));
    const first = new AbortController();
    const second = new AbortController();
    const firstRequest = runHarnessTextPrompt({
      harness: "claude",
      cwd: "/tmp",
      prompt: "first",
      signal: first.signal,
    });
    const secondRequest = runHarnessTextPrompt({
      harness: "claude",
      cwd: "/tmp",
      prompt: "second",
      signal: second.signal,
    });
    first.abort();
    await expect(firstRequest).rejects.toThrow("By-the-way request cancelled");
    expect(stopTextPrompt).not.toHaveBeenCalled();
    second.abort();
    await expect(secondRequest).rejects.toThrow("By-the-way request cancelled");
    expect(stopTextPrompt).not.toHaveBeenCalled();
  });

  it("exposes the edit-last-turn support matrix", () => {
    registerBuiltinHarnesses();
    const ids: HarnessId[] = [
      "claude",
      "codex",
    ];

    expect(
      Object.fromEntries(ids.map((id) => [id, canRewindHarnessLastTurn(id)])),
    ).toEqual({
      claude: false,
      codex: true,
    });
  });

  it("refreshes only the requested catalogs", async () => {
    const codex = vi.fn(async () => undefined);
    const claude = vi.fn(async () => undefined);
    registerHarness(stub("codex", { refreshCatalog: codex }));
    registerHarness(stub("claude", { refreshCatalog: claude }));

    await refreshHarnessCatalogs(["claude"]);

    expect(claude).toHaveBeenCalledOnce();
    expect(codex).not.toHaveBeenCalled();
  });

  it("does not spawn a catalog probe twice after a live list lands", async () => {
    const codex = vi.fn(async () => {
      setHarnessModels("codex", [
        {
          id: "codex:opus",
          harness: "codex",
          name: "Opus",
          nativeId: "anthropic/opus",
        },
      ]);
    });
    registerHarness(stub("codex", { refreshCatalog: codex }));

    await refreshHarnessCatalogs(["codex"]);
    await refreshHarnessCatalogs(["codex"]);

    expect(codex).toHaveBeenCalledOnce();
  });

  it("skips catalog refresh when no harness is in use", async () => {
    const codex = vi.fn(async () => undefined);
    registerHarness(stub("codex", { refreshCatalog: codex }));
    await refreshHarnessCatalogs([]);
    expect(codex).not.toHaveBeenCalled();
  });

  it("parks a live child a few minutes after the turn settles", async () => {
    vi.useFakeTimers();
    const stopSession = vi.fn(async () => undefined);
    registerHarness(stub("claude", { stopSession }));

    await sendHarnessTurn({
      harness: "claude",
      sessionId: "s1",
      cwd: "/tmp",
      model: "claude:sonnet-5",
      text: "hi",
      runtimeMode: "supervised",
      onEvent: () => undefined,
    });

    expect(stopSession).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(HARNESS_IDLE_PARK_MS - 1);
    expect(stopSession).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(stopSession).toHaveBeenCalledWith("s1");
  });
  it("serializes provider-state operations per session", async () => {
    const order: string[] = [];
    let releaseFirst!: () => void;
    let markFirstStarted!: () => void;
    const firstStarted = new Promise<void>((resolve) => {
      markFirstStarted = resolve;
    });
    const firstGate = new Promise<void>((resolve) => {
      releaseFirst = resolve;
    });
    const compactContext = vi.fn(async (input: { sessionId: string }) => {
      order.push(`start:${input.sessionId}`);
      if (input.sessionId === "s1") {
        markFirstStarted();
        await firstGate;
      }
      order.push(`end:${input.sessionId}`);
    });
    registerHarness(stub("codex", { compactContext }));

    const compact1 = compactHarnessContext({
      harness: "codex",
      sessionId: "s1",
      cwd: "/tmp",
      model: "codex:gpt-5.4",
      runtimeMode: "supervised",
      onEvent: () => undefined,
    });
    await firstStarted;
    const compact2 = compactHarnessContext({
      harness: "codex",
      sessionId: "s1",
      cwd: "/tmp",
      model: "codex:gpt-5.4",
      runtimeMode: "supervised",
      onEvent: () => undefined,
    });
    const independent = compactHarnessContext({
      harness: "codex",
      sessionId: "s2",
      cwd: "/tmp",
      model: "codex:gpt-5.4",
      runtimeMode: "supervised",
      onEvent: () => undefined,
    });

    await independent;
    expect(order).toEqual(["start:s1", "start:s2", "end:s2"]);
    releaseFirst();
    await Promise.all([compact1, compact2]);
    expect(order).toEqual([
      "start:s1",
      "start:s2",
      "end:s2",
      "end:s1",
      "start:s1",
      "end:s1",
    ]);
  });

  it("binds a restored session and forwards its task panels", () => {
    const bindSession = vi.fn();
    const restoreTaskLists = vi.fn();
    registerHarness(stub("claude", { bindSession, restoreTaskLists }));
    const taskList = {
      key: "claude-tasks",
      items: [{ id: "1", text: "Write tests", status: "pending" as const }],
    };

    bindHarnessSession("claude", "s1", "sess_1", "/repo", "work", [
      { id: "b1", role: "user", text: "go" },
      { id: "b2", role: "tasks", text: "Write tests", taskList },
    ]);
    bindHarnessSession("claude", "s2", "sess_2", "/repo");

    expect(bindSession).toHaveBeenCalledWith("s1", "sess_1", "/repo", "work");
    expect(bindSession).toHaveBeenCalledWith("s2", "sess_2", "/repo", undefined);
    expect(restoreTaskLists).toHaveBeenCalledTimes(1);
    expect(restoreTaskLists).toHaveBeenCalledWith("s1", [taskList]);
  });
});
