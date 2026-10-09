// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { newSession, type Session } from "../../features/sessions/model/session";
import { agentTurnId, useAgentDelegation, type AgentDelegation } from "./useAgentDelegation";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission, SubmitOptions } from "./useSessionSubmission";

let root: Root;
let sessions: Session[];
let rerender: () => void;
let delegation: AgentDelegation;
const submit = vi.fn(async (_id: string, _text: string, _files: unknown[], _options?: SubmitOptions) => true);
const saved = new Map<string, Session>();

function setSessions(next: Session[]) {
  sessions = next;
  act(() => rerender());
}
const chat = (over: Partial<Session> = {}): Session => ({ ...newSession("codex", "/home/me", "codex:test"), id: "chat",
  blocks: [{ id: "u1", role: "user", text: "Review both" }], busy: true, ...over });
const child = (id: string): Session => ({ ...newSession("codex", "/code/app", "codex:test"), id, title: `Session ${id}`,
  blocks: [{ id: `${id}-u`, role: "user", text: "go", appRequestId: id }, { id: `${id}-a`, role: "assistant", text: `Done ${id}` }] });

beforeEach(async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  submit.mockClear();
  saved.clear();
  sessions = [chat(), child("a"), child("b")];
  function Harness() {
    const runtime = {
      sessions,
      sessionsRef: { get current() { return sessions; } },
      updateSessions: (update: (current: Session[]) => Session[]) => { sessions = update(sessions); },
      bindRestoredSession: vi.fn(),
    } as unknown as SessionRuntime;
    delegation = useAgentDelegation({ runtime, submission: { submit } as unknown as SessionSubmission, loadSession: async (id) => saved.get(id) ?? null });
    return null;
  }
  root = createRoot(document.createElement("div"));
  rerender = () => root.render(createElement(Harness, { key: undefined }));
  await act(async () => rerender());
});
afterEach(async () => { await act(async () => root.unmount()); });

it("groups a turn by the message that started it", () => {
  expect(agentTurnId(chat())).toBe("u1");
  expect(agentTurnId({ blocks: [] })).toBe("");
});

it("reports a turn's launches together, once the turn has ended and the agent is idle", async () => {
  const a = delegation.monitor("chat", "a", "a", "/code/app", "Review a");
  const b = delegation.monitor("chat", "b", "b", "/code/app", "Review b");
  a.accept();
  b.accept();
  a({ status: "completed", text: "Done a" });
  b({ status: "failed", text: "", error: "Not signed in" });
  // Both stopped while the agent is still wrapping up its own turn.
  expect(submit).not.toHaveBeenCalled();
  setSessions(sessions.map((session) => session.id === "chat" ? { ...session, busy: false } : session));
  await vi.waitFor(() => expect(submit).toHaveBeenCalledOnce());
  const [id, text, , options] = submit.mock.calls[0];
  expect(id).toBe("chat");
  expect(text).toBe("2 sessions finished");
  expect(options?.agentCompletion?.completion).toMatchObject({ sessionCount: 2, status: "failed" });
  expect(options?.agentCompletion?.report).toContain("Done a");
  expect(options?.agentCompletion?.report).toContain("Not signed in");
  expect(options?.appRequestId).toMatch(/^agent-completion-batch-/);
  // Delivered once, however often the app re-renders.
  setSessions([...sessions]);
  expect(submit).toHaveBeenCalledOnce();
});

it("waits behind the user's own queued messages and pending questions", async () => {
  const a = delegation.monitor("chat", "a", "a", "/code/app", "Review a");
  a.accept();
  a({ status: "completed", text: "Done a" });
  setSessions(sessions.map((session) => session.id === "chat"
    ? { ...session, busy: false, queuedMessages: [{ id: "q", text: "one more thing", attachments: [] }] } : session));
  await Promise.resolve();
  expect(submit).not.toHaveBeenCalled();
  setSessions(sessions.map((session) => session.id === "chat" ? { ...session, queuedMessages: undefined } : session));
  await vi.waitFor(() => expect(submit).toHaveBeenCalledOnce());
  expect(submit.mock.calls[0][1]).toBe("Finished: Session a");
});

it("says nothing about a session the agent stopped itself", async () => {
  const a = delegation.monitor("chat", "a", "a", "/code/app", "Review a");
  const b = delegation.monitor("chat", "b", "b", "/code/app", "Review b");
  a.accept();
  b.accept();
  a({ status: "completed", text: "Done a" });
  delegation.dismiss("chat", "b");
  setSessions(sessions.map((session) => session.id === "chat" ? { ...session, busy: false } : session));
  await vi.waitFor(() => expect(submit).toHaveBeenCalledOnce());
  expect(submit.mock.calls[0][3]?.agentCompletion?.completion).toMatchObject({ sessionId: "a" });
});

it("brings back a chat that was put away to hand it its report", async () => {
  const a = delegation.monitor("chat", "a", "a", "/code/app", "Review a");
  a.accept();
  saved.set("chat", chat({ busy: false }));
  setSessions(sessions.filter((session) => session.id !== "chat"));
  a({ status: "completed", text: "Done a" });
  await vi.waitFor(() => expect(submit).toHaveBeenCalledOnce());
  expect(sessions.some((session) => session.id === "chat")).toBe(true);
});
