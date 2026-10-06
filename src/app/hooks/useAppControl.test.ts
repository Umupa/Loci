// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { upsertNote } from "../../features/notes";
import { modelsFor, setHarnessModels, resetHarnessModelOverlays } from "../../features/sessions/model/models";
import { newSession, type Session } from "../../features/sessions/model/session";
import { newTab } from "../../features/workspace/model/layout";
import { useAppControl } from "./useAppControl";
import type { useAppWorkspace } from "./useAppWorkspace";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("@tauri-apps/api/webviewWindow", () => ({ getCurrentWebviewWindow: vi.fn() }));
vi.mock("../../features/sessions/data/sessionStore", () => ({ listSessionsByProject: vi.fn(async () => []) }));
vi.mock("../../features/notes", async (load) => ({ ...await load<typeof import("../../features/notes")>(), upsertNote: vi.fn(), getNote: vi.fn(async () => null), loadNotes: vi.fn(async () => []) }));
vi.mock("../../integrations/harness/core/availability", () => ({ isHarnessAvailable: () => true }));

type Request = { id: string; namespace: string; sessionId: string; requestId: string; action: string; input: Record<string, unknown> };
let listener: ((event: { payload: Request }) => void) | undefined;
let root: Root;
let container: HTMLDivElement;
let sessionsRef: { current: Session[] };
let addSession: ReturnType<typeof vi.fn>;
let submit: ReturnType<typeof vi.fn>;
let loadSession: ReturnType<typeof vi.fn>;
let flushPersistence: ReturnType<typeof vi.fn>;

async function settle() {
  await act(async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); });
}
function emit(action: string, input: Record<string, unknown>, requestId = "request-1", id = crypto.randomUUID()) {
  listener!({ payload: { id, namespace: "app", sessionId: "source", requestId, action, input } });
  return id;
}
function reply(id: string) {
  return vi.mocked(invoke).mock.calls.find(([command, args]) => command === "control_reply" && (args as { id?: string }).id === id)?.[1] as { response: { ok: boolean; error?: string; result?: unknown } } | undefined;
}

beforeEach(async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  vi.clearAllMocks();
  setHarnessModels("codex", [{ id: "codex:test", harness: "codex", name: "Test model" }]);
  listener = undefined;
  vi.mocked(getCurrentWebviewWindow).mockReturnValue({
    listen: vi.fn(async (_name, handle) => { listener = handle; return () => { listener = undefined; }; }),
  } as unknown as ReturnType<typeof getCurrentWebviewWindow>);
  const source = { ...newSession("codex", "/project"), id: "source", busy: true };
  sessionsRef = { current: [source] };
  addSession = vi.fn((session: Session) => { sessionsRef.current.push(session); return session.id; });
  submit = vi.fn(async () => true);
  loadSession = vi.fn(async () => null);
  flushPersistence = vi.fn(async () => undefined);
  const runtime = {
    sessionsRef, bindRestoredSession: vi.fn(), flushPersistence,
    updateSessions: (update: Session[] | ((current: Session[]) => Session[])) => { sessionsRef.current = typeof update === "function" ? update(sessionsRef.current) : update; },
  } as unknown as SessionRuntime;
  const workspace = { loadSession, addSession, tabsRef: { current: [newTab(source.id)] } } as unknown as ReturnType<typeof useAppWorkspace>;
  const submission = { submit, saveDraft: vi.fn(() => true) } as unknown as SessionSubmission;
  function Host() { useAppControl({ workspace, runtime, submission }); return null; }
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  await act(async () => root.render(createElement(Host)));
});
afterEach(async () => { await act(async () => root.unmount()); container.remove(); resetHarnessModelOverlays(); vi.unstubAllGlobals(); });

describe("local app control composition", () => {
  it("coalesces duplicate writes and rejects request-id reuse with changed input", async () => {
    let finish!: (value: Awaited<ReturnType<typeof upsertNote>>) => void;
    vi.mocked(upsertNote).mockReturnValue(new Promise((resolve) => { finish = resolve; }));
    const first = emit("notes.write", { title: "A note", body: "One body" });
    const second = emit("notes.write", { title: "A note", body: "One body" });
    const conflict = emit("notes.write", { title: "A note", body: "Different" });
    await settle();
    expect(upsertNote).toHaveBeenCalledTimes(1);
    expect(reply(conflict)?.response).toEqual({ ok: false, error: "Request ID was already used with different input" });
    finish({ id: "note", slug: "a-note", title: "A note", body: "One body", tags: [], createdAt: 1, updatedAt: 1 });
    await settle();
    expect(reply(first)?.response.ok).toBe(true);
    expect(reply(second)?.response).toEqual(reply(first)?.response);
  });

  it("allows retry after a definite failed write", async () => {
    vi.mocked(upsertNote).mockRejectedValueOnce(new Error("disk full"));
    const first = emit("notes.write", { body: "Retry me" });
    await settle();
    expect(reply(first)?.response).toEqual({ ok: false, error: "disk full" });
    vi.mocked(upsertNote).mockResolvedValueOnce({ id: "note", slug: "retry", title: "Retry", body: "Retry me", tags: [], createdAt: 1, updatedAt: 1 });
    const second = emit("notes.write", { body: "Retry me" });
    await settle();
    expect(upsertNote).toHaveBeenCalledTimes(2);
    expect(reply(second)?.response.ok).toBe(true);
  });

  it("creates a background session through the actual submit path and persists acceptance", async () => {
    const model = modelsFor("codex")[0];
    const request = emit("sessions.start", { harness: "codex", model: model.id, prompt: "Hello from operator" });
    await settle();
    expect(addSession).toHaveBeenCalledTimes(1);
    expect(addSession.mock.calls[0][1]).toEqual({ reveal: false });
    expect(submit).toHaveBeenCalledWith("app-source-request-1", "Hello from operator", [], { appRequestId: "app-source-request-1" });
    expect(flushPersistence).toHaveBeenCalledOnce();
    expect(reply(request)?.response.ok).toBe(true);
  });

  it("rejects a split target belonging to another project", async () => {
    const target = { ...newSession("codex", "/other"), id: "other" };
    sessionsRef.current.push(target);
    const request = emit("sessions.start", { prompt: "Should not start", placement: "right", besideSessionId: target.id });
    await settle();
    expect(addSession).not.toHaveBeenCalled();
    expect(submit).not.toHaveBeenCalled();
    expect(reply(request)?.response).toEqual({ ok: false, error: "The selected pane is not open in this project" });
  });

  it("cannot enable operator in another thread through a send request", async () => {
    const request = emit("sessions.send", { sessionId: "other", prompt: "/operator enable control" });
    await settle();
    expect(submit).not.toHaveBeenCalled();
    expect(reply(request)?.response).toEqual({ ok: false, error: "App calls cannot enable /operator in another session" });
  });
});
