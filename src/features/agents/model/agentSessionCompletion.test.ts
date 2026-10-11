import { describe, expect, it, vi } from "vitest";
import { newSession } from "../../sessions/model/session";
import {
  agentSessionCompletionResult,
  AgentSessionCompletionBatches,
} from "./agentSessionCompletion";

const origin = { chatId: "chat", turn: "u1" };
function result(
  id: string,
  status: "completed" | "failed" | "cancelled" = "completed",
) {
  return agentSessionCompletionResult({
    requestId: id,
    sessionId: id,
    project: "/code/project",
    prompt: `Review ${id}`,
    outcome: {
      status,
      text: `Result ${id}`,
      ...(status === "failed" ? { error: "Launch failed" } : {}),
    },
  });
}

describe("agent completion batches", () => {
  it("waits for the launching turn and all children, even when a fast child finishes before the others launch", () => {
    const ready = vi.fn();
    const batches = new AgentSessionCompletionBatches(ready);
    const a = batches.watch(origin, "a");
    a(result("a"));
    batches.closeInactive(() => true);
    expect(ready).not.toHaveBeenCalled();
    const b = batches.watch(origin, "b");
    const c = batches.watch(origin, "c");
    c(result("c"));
    batches.closeInactive(() => false);
    expect(ready).not.toHaveBeenCalled();
    b(result("b"));
    expect(ready).toHaveBeenCalledOnce();
    const [chatId, message] = ready.mock.calls[0];
    expect(chatId).toBe("chat");
    expect(message.title).toBe("3 sessions finished");
    expect(message.completion).toMatchObject({
      sessionCount: 3,
      status: "completed",
    });
    const payload = JSON.parse(message.text.split("\n\n")[1]);
    expect(
      payload.sessions.map((entry: { sessionId: string }) => entry.sessionId),
    ).toEqual(["a", "b", "c"]);
    expect(message.text).toContain("have now stopped");
    expect(message.text).not.toContain("one consolidated update");
    // A late duplicate settles nothing twice.
    a(result("a"));
    expect(ready).toHaveBeenCalledOnce();
  });

  it("counts failures and cancellations as finished, and reports the worst of them", () => {
    const ready = vi.fn();
    const batches = new AgentSessionCompletionBatches(ready);
    const a = batches.watch(origin, "a");
    const b = batches.watch(origin, "b");
    batches.closeInactive(() => false);
    a(result("a", "cancelled"));
    expect(ready).not.toHaveBeenCalled();
    b(result("b", "failed"));
    expect(ready.mock.calls[0][1].completion.status).toBe("failed");
  });

  it("names a single session's report after it", () => {
    const ready = vi.fn();
    const batches = new AgentSessionCompletionBatches(ready);
    batches.watch(origin, "a")(result("a"));
    batches.closeInactive(() => false);
    const message = ready.mock.calls[0][1];
    expect(message).toMatchObject({
      id: "agent-completion-a",
      title: "Finished: Agent session",
      completion: { sessionId: "a", status: "completed" },
    });
    expect(message.completion.sessionCount).toBeUndefined();
    expect(JSON.parse(message.text.split("\n\n")[1])).toMatchObject({
      sessionId: "a",
      result: "Result a",
    });
  });

  it("holds a result until its launch is known to be accepted, and drops a rejected one", () => {
    const ready = vi.fn();
    const batches = new AgentSessionCompletionBatches(ready);
    const a = batches.watch(origin, "a", "a", { awaitAcceptance: true });
    const b = batches.watch(origin, "b", "b", { awaitAcceptance: true });
    a(result("a"));
    b(result("b"));
    batches.closeInactive(() => false);
    expect(ready).not.toHaveBeenCalled();
    a.accept();
    expect(ready).not.toHaveBeenCalled();
    b.discard();
    expect(ready).toHaveBeenCalledOnce();
    expect(ready.mock.calls[0][1].completion.sessionCount).toBeUndefined();
  });

  it("drops the report for a session the agent stopped itself, keeping the others", () => {
    const ready = vi.fn();
    const batches = new AgentSessionCompletionBatches(ready);
    const a = batches.watch(origin, "a");
    batches.watch(origin, "b");
    batches.watch({ chatId: "other", turn: "u1" }, "b");
    batches.closeInactive(() => false);
    a(result("a"));
    batches.dismissSession("chat", "b");
    expect(ready).toHaveBeenCalledOnce();
    expect(ready.mock.calls[0][1].completion.sessionId).toBe("a");
  });

  it("keeps later turns and other agents independent of a slow earlier group", () => {
    const ready = vi.fn();
    const batches = new AgentSessionCompletionBatches(ready);
    batches.watch(origin, "slow");
    const later = batches.watch({ chatId: "chat", turn: "u2" }, "fast");
    const other = batches.watch({ chatId: "other", turn: "u1" }, "x");
    batches.closeInactive(() => false);
    later(result("fast"));
    other(result("x"));
    expect(ready.mock.calls.map(([chatId]) => chatId)).toEqual([
      "chat",
      "other",
    ]);
  });
});

it("takes the final answer of the watched turn, and bounds a long one", () => {
  const session = newSession("codex", "/code/project", "codex:test");
  session.title = "Fix CI";
  session.blocks = [
    { id: "u1", role: "user", text: "Fix CI", appRequestId: "req" },
    { id: "a1", role: "assistant", text: "Looking." },
    { id: "a2", role: "assistant", text: "x".repeat(13_000) },
    { id: "u2", role: "user", text: "Something else" },
    { id: "a3", role: "assistant", text: "A later turn." },
  ];
  const report = agentSessionCompletionResult({
    requestId: "req",
    sessionId: session.id,
    project: "/code/project",
    prompt: "Fix CI",
    outcome: { status: "completed", text: "A later turn." },
    session,
  });
  expect(report).toMatchObject({ title: "Fix CI", truncated: true });
  expect(report.result).toHaveLength(12_000);
});
