// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { upsertNote } from "../../features/notes";
import { modelsFor, setHarnessModels, resetHarnessModelOverlays } from "../../features/sessions/model/models";
import { newSession, type Session } from "../../features/sessions/model/session";
import { useAppControl } from "./useAppControl";
import type { AppControlWorkspace } from "./useAppControl";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";
import { agent, testContext } from "../commands/testContext";
import type { CommandContext } from "../commands/context";

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
let commands: CommandContext;
function emit(action: string, input: Record<string, unknown>, requestId = "request-1", id = crypto.randomUUID(), namespace = "app", sessionId = "source") {
  listener!({ payload: { id, namespace, sessionId, requestId, action, input } });
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
  const workspace = { loadSession, addSession } as unknown as AppControlWorkspace;
  const submission = { submit, saveDraft: vi.fn(() => true) } as unknown as SessionSubmission;
  commands = testContext([agent("a1", "Kern")]).ctx;
  function Host() { useAppControl({ workspace, runtime, submission, commands }); return null; }
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
    const request = emit("sessions.start", { harness: "codex", model: model.id, prompt: "Hello from app" });
    await settle();
    expect(addSession).toHaveBeenCalledTimes(1);
    expect(addSession.mock.calls[0][1]).toEqual({ reveal: false });
    expect(submit).toHaveBeenCalledWith("app-source-request-1", "Hello from app", [], { appRequestId: "app-source-request-1" });
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
    expect(reply(request)?.response).toEqual({ ok: false, error: "The selected session is not open in this project" });
  });

  it("starts a session beside one in its project without placing panes", async () => {
    const target = { ...newSession("codex", "/project"), id: "beside" };
    sessionsRef.current.push(target);
    const request = emit("sessions.start", { prompt: "Beside", placement: "down", besideSessionId: target.id });
    await settle();
    expect(addSession.mock.calls[0][1]).toEqual({ reveal: false });
    expect(reply(request)?.response.ok).toBe(true);
  });
});

describe("terminal commands", () => {
  it("run through the command layer, answer once per request ID and say why they fail", async () => {
    const first = emit("templates.list", {}, "t1", undefined, "cli", "");
    const again = emit("templates.list", {}, "t1", undefined, "cli", "");
    const reused = emit("models.list", {}, "t1", undefined, "cli", "");
    const unknown = emit("nothing.here", {}, "t2", undefined, "cli", "");
    const missing = emit("courses.read", { mentor: "Nobody", id: "c" }, "t3", undefined, "cli", "");
    await settle();
    expect(reply(first)?.response.ok).toBe(true);
    expect((reply(first)?.response.result as { templates: unknown[] }).templates.length).toBeGreaterThan(0);
    expect(reply(again)?.response).toEqual(reply(first)?.response);
    expect(reply(reused)?.response.ok).toBe(false);
    expect(reply(unknown)?.response).toEqual({ ok: false, error: "Unknown command: nothing.here", code: "usage" });
    expect(reply(missing)?.response).toMatchObject({ ok: false, code: "not_found" });
  });

  it("do not widen what an agent's own app CLI reaches", async () => {
    const id = emit("templates.list", {}, "t4");
    await settle();
    expect(reply(id)?.response).toEqual({ ok: false, error: "Unknown app action: templates.list" });
  });

  it("let a mentor's own turn use the reader commands, and no other session", async () => {
    const notMentor = emit("reader.show", {}, "t5");
    await settle();
    expect(reply(notMentor)?.response).toEqual({ ok: false, error: "Only a mentor's own conversation can use this action" });
    localStorage.setItem("loci:agent-roster", JSON.stringify([{ id: "a1", sessionId: "source", avatar: "nova", color: "#000", projects: [] }]));
    const own = emit("reader.show", {}, "t6");
    await settle();
    expect(reply(own)?.response).toMatchObject({ ok: true, result: { mentor: "a1", kind: "none" } });
  });
});

