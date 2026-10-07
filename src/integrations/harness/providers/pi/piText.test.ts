import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { HarnessEvent } from "../../core/types";

const mocks = vi.hoisted(() => ({
  close: vi.fn(),
  request: vi.fn(),
  frames: [] as Array<(record: Record<string, unknown>) => void>,
}));

vi.mock("../../core/child", () => ({
  killChild: async () => undefined,
  resolveOmpBinary: async () => ({ path: "/fake/omp" }),
  resolvePiBinary: async () => ({ path: "/fake/pi" }),
  spawnChild: async () => undefined,
  unwatchChild: () => undefined,
  watchChild: () => undefined,
}));

vi.mock("./piClient", () => ({
  PiRpc: class {
    constructor(
      _sessionId: string,
      onFrame: (record: Record<string, unknown>) => void,
    ) {
      mocks.frames.push(onFrame);
    }

    request = mocks.request;
    close = mocks.close;
    pushLine = vi.fn();
  },
}));

const { runPiTextPrompt, stopPiTextPrompt, runOmpTextPrompt, stopOmpTextPrompt } =
  await import("./piText");

async function waitFor(predicate: () => boolean, label: string) {
  for (let index = 0; index < 200; index += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw new Error(`timed out waiting for ${label}`);
}

beforeEach(() => {
  mocks.close.mockReset();
  mocks.request.mockReset().mockResolvedValue({ data: {} });
  mocks.frames.length = 0;
});

afterEach(async () => {
  await stopPiTextPrompt();
  await stopOmpTextPrompt();
});

describe.each([
  { name: "Pi", run: runPiTextPrompt },
  { name: "omp", run: runOmpTextPrompt },
])("$name text cancellation", ({ run }) => {
  it("does not submit a side prompt cancelled while queued", async () => {
    const first = run({
      cwd: "/repo",
      model: "anthropic/claude-haiku",
      prompt: "first",
    });
    await waitFor(
      () =>
        mocks.request.mock.calls.some(([request]) => request.type === "prompt"),
      "first prompt",
    );
    const controller = new AbortController();
    const queued = run({
      cwd: "/repo",
      model: "anthropic/claude-haiku",
      prompt: "cancelled",
      signal: controller.signal,
    });
    const rejected = expect(queued).rejects.toThrow();
    controller.abort();
    const frame = mocks.frames[0]!;
    frame({
      type: "message_update",
      assistantMessageEvent: { type: "text_delta", delta: "Done" },
    });
    frame({ type: "agent_settled" });
    await expect(first).resolves.toBe("Done");
    await rejected;
    expect(
      mocks.request.mock.calls.filter(([request]) => request.type === "prompt"),
    ).toHaveLength(1);
    expect(mocks.frames).toHaveLength(1);
  });

  it("cancels without waiting for a delayed prompt acknowledgement", async () => {
    let acknowledge: (() => void) | undefined;
    mocks.request.mockImplementation((request) =>
      request.type === "prompt"
        ? new Promise((resolve) => {
            acknowledge = () => resolve({ data: {} });
          })
        : Promise.resolve({ data: {} }),
    );
    const controller = new AbortController();
    const result = run({
      cwd: "/repo",
      model: "anthropic/claude-haiku",
      prompt: "slow acknowledgement",
      signal: controller.signal,
    });
    const rejected = expect(result).rejects.toThrow("cancelled");
    let settled = false;
    void result.catch(() => {
      settled = true;
    });
    await waitFor(() => acknowledge != null, "prompt submission");
    controller.abort();
    try {
      await vi.waitFor(() => expect(settled).toBe(true));
      await rejected;
      expect(mocks.close).toHaveBeenCalled();
    } finally {
      acknowledge?.();
      await rejected;
    }
  });
});

it("forwards Pi text and reasoning deltas to an isolated prompt", async () => {
  const events: HarnessEvent[] = [];
  const result = runPiTextPrompt({
    cwd: "/repo",
    model: "anthropic/claude-haiku",
    prompt: "question",
    onEvent: (event) => events.push(event),
  });

  await waitFor(
    () =>
      mocks.request.mock.calls.some(([request]) => request.type === "prompt"),
    "prompt",
  );
  const frame = mocks.frames[0]!;
  frame({
    type: "message_update",
    assistantMessageEvent: { type: "thinking_delta", delta: "Checking" },
  });
  frame({
    type: "message_update",
    assistantMessageEvent: { type: "text_delta", delta: "Partial answer" },
  });
  frame({ type: "agent_settled" });

  await expect(result).resolves.toBe("Partial answer");
  expect(events).toEqual([
    { type: "reasoning.delta", text: "Checking" },
    { type: "message.delta", text: "Partial answer" },
  ]);
});
