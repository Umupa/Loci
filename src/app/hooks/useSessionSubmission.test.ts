// @vitest-environment happy-dom
import { act,createElement,useRef,useState } from "react";
import { createRoot,type Root } from "react-dom/client";
import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { newSession,type Session } from "../../features/sessions/model/session";
import { createAgent, saveAgentSessionId } from "../../features/agents/model/agent";
import { saveCanvasMcpEnabled } from "../../features/settings/model/builtinMcp";
import { saveFollowUpBehavior } from "../../features/settings/model/settings";
import { registerHarness,resetHarnessIdlePark,type HarnessAdapter } from "../../integrations/harness/core/registry";
import { TurnNotReadyError, type SendTurnInput } from "../../integrations/harness/core/types";
import { useSessionRuntime,type SessionRuntime } from "./useSessionRuntime";
import { useSessionSubmission,type SessionSubmission } from "./useSessionSubmission";
import type { LearningMessageContext, WidgetRef } from "../../features/learning/model/types";

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), prepare: vi.fn(async (text: string) => text) }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke, isTauri: () => true }));
vi.mock("../../integrations/harness/core/child", () => ({ startHarnessBridge: () => () => undefined }));
vi.mock("../../features/sessions/model/promptPreparation", () => ({ preparePrompt: mocks.prepare }));
vi.mock("../../features/skills/model/skills", () => ({ isNativeCommandPrompt: () => false }));

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

type Pending = { input: SendTurnInput; done: ReturnType<typeof deferred<void>> };
let root: Root;
let host: HTMLDivElement;
let runtime: SessionRuntime;
let actions: SessionSubmission;
let pending: Pending[];
let acceptImmediately: boolean;
let adapter: HarnessAdapter;
let storedWidgetHtml: string;
let storedWidgetRevision: number;
const canStartSessionWork = vi.fn(() => true);

async function mount(initial: Session) {
  function Harness() {
    const [sessions, setSessions] = useState([initial]);
    const sessionsRef = useRef(sessions);
    // Match Workspace: useSessionRuntime owns ref and state commits.
    runtime = useSessionRuntime({ sessions, sessionsRef, setSessions });
    actions = useSessionSubmission({ runtime, canStartSessionWork });
    return createElement("output", null, JSON.stringify(sessions));
  }
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  await act(async () => root.render(createElement(Harness)));
}

function session() { return runtime.sessionsRef.current[0]; }
/** Transport assertions compare the user text, excluding app authoring rules. */
function withoutWidgetRules(text: string) { return text.replace(/\n\n<loci_(widgets|courses)>[\s\S]*?<\/loci_\1>/g, ""); }
async function settle(run: Pending) {
  await act(async () => {
    run.input.onEvent({ type: "message.completed" });
    run.input.onEvent({ type: "session.ended", code: 0 });
    run.done.resolve();
    await run.done.promise;
  });
}

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  pending = [];
  acceptImmediately = true;
  canStartSessionWork.mockReset().mockReturnValue(true);
  mocks.prepare.mockReset();
  mocks.prepare.mockImplementation(async (text: string) => text);
  mocks.invoke.mockReset();
  storedWidgetHtml = '<section data-canonical="latest">Current saved channel implementation</section>';
  storedWidgetRevision = 8;
  mocks.invoke.mockImplementation(async (command: string, args?: { session?: Session; widget?: WidgetRef }) => {
    if (command === "app_cli_path") return "/Applications/Loci.app/Contents/MacOS/loci";
    if (command === "session_upsert") return { ...args?.session, createdAt: 1, updatedAt: Date.now() };
    if (command === "learning_widget_get") return { ...args?.widget, title: "Current channel trace", html: storedWidgetHtml, sourceIds: ["pdf-source"], sourceSessionId: "original", sourceBlockId: "answer", revision: storedWidgetRevision, saved: true, state: { capacity: 99, step: 1 }, createdAt: 1, updatedAt: 8 };
    return undefined;
  });
  adapter = {
    id: "codex", live: true,
    sendTurn: vi.fn((input: SendTurnInput) => {
      const done = deferred<void>();
      pending.push({ input, done });
      if (acceptImmediately) input.onAccepted?.();
      return done.promise;
    }),
    steerTurn: vi.fn(async () => undefined),
    cancelTurn: vi.fn(async () => undefined),
    respondApproval: vi.fn(), respondQuestion: vi.fn(), keepQuestionOpen: vi.fn(),
    stopSession: vi.fn(async () => undefined), forgetSession: vi.fn(async () => undefined),
    bindSession: vi.fn(), rewindLastTurn: vi.fn(async () => ({ submitted: false })),
  };
  registerHarness(adapter);
});

afterEach(async () => {
  await act(async () => {
    for (const run of pending) run.done.resolve();
    await Promise.all(pending.map((run) => run.done.promise.catch(() => undefined)));
  });
  await act(async () => root?.unmount());
  host?.remove();
  resetHarnessIdlePark();
});

describe("source-backed learning submissions", () => {
  const context: LearningMessageContext = {
    sources: [{ id: "pdf-source", kind: "pdf", title: "Channel notes", quote: "Send blocks until a receive is available.", documentId: "document", path: "/project/notes.pdf", annotationId: "highlight", anchors: [{ page: 3, rects: [{ x: .1, y: .2, width: .6, height: .03 }] }] }],
    widgetContext: { owner: { kind: "session", id: "original" }, id: "channel", title: "Channel trace", revision: 2, state: { capacity: 0, step: 4 } },
  };
  it.each(["codex", "pi"] as const)("sends the same evidence and widget contract through %s", async (harness) => {
    registerHarness({ ...adapter, id: harness });
    await mount(newSession(harness, "/project", "test"));
    await act(async () => { expect(actions.onSubmit(session().id, "Why does this wait?", [], context)).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    const sent = pending[0].input.text;
    expect(sent).toContain("<loci_learning_context>");
    expect(sent).toContain('"page": 3');
    expect(sent).toContain('"capacity": 0');
    expect(sent).toContain('"html": "<section data-canonical=\\"latest\\">Current saved channel implementation</section>"');
    expect(sent).toContain('"revision": 8');
    expect(sent).not.toContain('"capacity": 99');
    expect(sent).toContain("source claims, your inference, and observed experiment results");
    expect(sent).toContain("loci-widget\n---\nid:");
    expect(sent).toContain("<loci_courses>");
    expect(sent).toContain("engine: build-your-own");
    expect(sent).toContain("engine: domain-navigation");
    expect(sent).toContain("=== BEFORE ===");
    const block = session().blocks.find((entry) => entry.role === "user")!;
    expect(block).toMatchObject({ text: "Why does this wait?", ...context });
    expect(block.widgetContext).not.toHaveProperty("html");
    expect(mocks.invoke).toHaveBeenCalledWith("learning_source_register", { source: context.sources![0] });
    expect(mocks.invoke).toHaveBeenCalledWith("learning_annotation_link", { id: "highlight", sessionId: session().id, blockId: block.id });
    await settle(pending[0]);
  });
  it("preserves context while a queued question is edited and later dispatched", async () => {
    await mount(newSession("codex", "/project", "test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => { actions.onSubmit(session().id, "Why this step?", [], { ...context, followUpBehavior: "queue" }); });
    const queued = session().queuedMessages![0];
    expect(queued).toMatchObject(context);
    expect(mocks.invoke.mock.calls.some(([command]) => command === "learning_widget_get")).toBe(false);
    storedWidgetHtml = "<section>Revised while this question was queued</section>";
    storedWidgetRevision = 12;
    await act(async () => actions.editQueuedMessage(session().id, queued.id, "Explain the blocked sender"));
    await settle(pending[0]);
    await act(async () => vi.waitFor(() => expect(pending).toHaveLength(2)));
    expect(pending[1].input.text).toMatch(/^Explain the blocked sender/);
    expect(pending[1].input.text).toContain('"step": 4');
    expect(pending[1].input.text).toContain("Revised while this question was queued");
    expect(pending[1].input.text).toContain('"revision": 12');
    expect(session().blocks.find((entry) => entry.text === "Explain the blocked sender")).toMatchObject(context);
    await settle(pending[1]);
  });
  it("promotes a saved unsent source question without losing its anchors", async () => {
    await mount(newSession("codex", "/project", "test"));
    await act(async () => expect(actions.saveDraft(session().id, "Explain this paragraph", [], context)).toBe(true));
    const draft = session().blocks[0];
    expect(draft).toMatchObject({ draft: true, ...context });
    expect(draft.widgetContext).not.toHaveProperty("html");
    expect(mocks.invoke.mock.calls.some(([command]) => command === "learning_widget_get")).toBe(false);
    expect(pending).toHaveLength(0);
    await act(async () => { actions.onSubmit(session().id, draft.text, [], { draftBlockId: draft.id }); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(session().blocks[0]).toMatchObject(context);
    expect(session().blocks[0].draft).toBeUndefined();
    expect(pending[0].input.text).toContain('"annotationId": "highlight"');
    expect(pending[0].input.text).toContain("Current saved channel implementation");
    await settle(pending[0]);
  });
  it("reports a removed saved explanation instead of sending a question without its context", async () => {
    const invoke = mocks.invoke.getMockImplementation()!;
    mocks.invoke.mockImplementation((command: string, args?: unknown) => command === "learning_widget_get" ? Promise.resolve(null) : invoke(command, args));
    await mount(newSession("codex", "/project", "test"));
    await act(async () => { actions.onSubmit(session().id, "Revise this explanation", [], context); });
    await vi.waitFor(() => expect(session().blocks.some((block) => block.role === "system" && block.text.includes("This explanation no longer exists"))).toBe(true));
    expect(adapter.sendTurn).not.toHaveBeenCalled();
    expect(session().blocks.find((block) => block.role === "user")).toMatchObject(context);
  });
  it("hydrates saved HTML for steering and preserves the user's original conditions", async () => {
    await mount(newSession("codex", "/project", "test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => { actions.onSubmit(session().id, "Show the blocked step", [], { ...context, followUpBehavior: "steer" }); });
    const sent = vi.mocked(adapter.steerTurn!).mock.calls[0][0].text;
    expect(sent).toContain("Current saved channel implementation");
    expect(sent).toContain('"step": 4');
    expect(session().blocks.find((block) => block.text === "Show the blocked step")?.widgetContext).toEqual(context.widgetContext);
    await settle(pending[0]);
  });
});

describe("session submission", () => {
  it("refuses new main and side work while the workspace is removing the session", async () => {
    const initial = newSession("codex", "/project", "codex:test");
    initial.blocks = [{ id: "user", role: "user", text: "Main question", btwThreads: [{
      id: "side", sourceEndBlockId: "user", createdAt: 1, updatedAt: 1,
      status: "error", harness: "codex", model: "test", messages: [{ id: "question", role: "user", text: "Explain", createdAt: 1 }],
    }] }];
    adapter.runTextPrompt = vi.fn(async () => "Recovered");
    adapter.compactContext = vi.fn(async () => undefined);
    await mount(initial);
    canStartSessionWork.mockReturnValue(false);
    await act(async () => {
      expect(actions.onSubmit(initial.id, "New turn")).toBe(false);
      expect(actions.btwSubmit(initial.id, initial.blocks, "side", "retry", "Retry")).toBe(false);
      actions.btwRetry(initial.id, initial.blocks, "side");
      await actions.compact(initial.id);
    });
    expect(adapter.sendTurn).not.toHaveBeenCalled();
    expect(adapter.runTextPrompt).not.toHaveBeenCalled();
    expect(adapter.compactContext).not.toHaveBeenCalled();
    canStartSessionWork.mockReturnValue(true);
    await act(async () => { expect(actions.btwSubmit(initial.id, initial.blocks, "side", "retry", "Retry")).toBe(true); });
    expect(adapter.runTextPrompt).toHaveBeenCalledOnce();
  });

  it("renders a 100-delta side answer and persists the final result without per-delta writes", async () => {
    const initial = newSession("codex", "/project", "codex:test");
    initial.blocks = [{ id: "user", role: "user", text: "Main question" }, { id: "answer", role: "assistant", text: "Main answer" }];
    const output = Array.from({ length: 100 }, (_, i) => `${i},`).join("");
    adapter.runTextPrompt = vi.fn(async (input) => {
      input.onThreadId?.("side-provider");
      for (let i = 0; i < 100; i += 1) input.onEvent?.({ type: "message.delta", text: `${i},` });
      input.onEvent?.({ type: "message.completed" });
      return output;
    });
    await mount(initial);
    await act(async () => { expect(actions.btwSubmit(initial.id, initial.blocks, "side", "side-user", "Explain further")).toBe(true); });
    const rendered = JSON.parse(host.textContent!)[0];
    expect(rendered.blocks[0].btwThreads[0]).toMatchObject({ status: "ready", providerThreadId: "side-provider" });
    expect(rendered.blocks[0].btwThreads[0].messages[1].text).toBe(output);
    await runtime.flushPersistence();
    const writes = mocks.invoke.mock.calls.filter(([command]) => command === "session_upsert");
    expect(writes).toHaveLength(1);
    expect(writes[0][1].session.blocks[0].btwThreads[0].messages[1].text).toBe(output);
  });

  it("commits side-question changes and deletion to React state", async () => {
    const initial = newSession("codex", "/project", "codex:test");
    initial.blocks = [{ id: "user", role: "user", text: "Main question", btwThreads: [{
      id: "side", sourceEndBlockId: "user", createdAt: 1, updatedAt: 1,
      status: "ready", harness: "codex", model: "test", messages: [],
    }] }];
    await mount(initial);
    expect(host.textContent).toContain('"model":"test"');
    await act(async () => actions.btwModelChange(initial.id, initial.blocks, "side", "new-model", {}));
    expect(session().blocks[0].btwThreads?.[0].model).toBe("new-model");
    expect(JSON.parse(host.textContent!)[0].blocks[0].btwThreads[0].model).toBe("new-model");
    await act(async () => actions.btwDelete(initial.id, session().blocks, "side"));
    expect(JSON.parse(host.textContent!)[0].blocks[0].btwThreads).toBeUndefined();
  });

  it("keeps streamed output before an approval and delivers the user's decision", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { expect(actions.onSubmit(session().id, "Read the report")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    const run = pending[0];
    await act(async () => {
      run.input.onEvent({ type: "message.delta", text: "I will inspect it." });
      run.input.onEvent({ type: "approval.requested", requestId: 7, title: "Read report", kind: "read" });
    });
    expect(session().blocks.map((block) => block.role)).toEqual(["user", "assistant", "tool"]);
    expect(session().blocks[2].approval).toEqual({ requestId: 7 });
    expect(session().blocks[1].text).toBe("I will inspect it.");
    act(() => actions.approve(session().id, 7, "allow"));
    expect(adapter.respondApproval).toHaveBeenCalledWith(session().id, 7, "allow");
    await act(async () => run.input.onEvent({ type: "approval.resolved", requestId: 7, decision: "allow" }));
    await settle(run);
    expect(session().busy).toBe(false);
    await runtime.flushPersistence();
    expect(mocks.invoke).toHaveBeenCalledWith("control_authorize_turn", { sessionId: session().id, cwd: "/project", appAccess: false, canvasAccess: true });
    expect(mocks.invoke).toHaveBeenCalledWith("control_turn_finished", { sessionId: session().id });
  });

  it("drops output from a stopped turn while a new turn is running", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    const first = pending[0];
    await act(async () => actions.stop(session().id));
    await act(async () => { first.done.resolve(); await first.done.promise; });
    await act(async () => { actions.onSubmit(session().id, "Second"); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    await act(async () => {
      first.input.onEvent({ type: "message.delta", text: "stale output" });
      pending[1].input.onEvent({ type: "message.delta", text: "current output" });
      runtime.flushEvents();
    });
    expect(session().blocks.some((block) => block.text.includes("stale output"))).toBe(false);
    expect(session().blocks.at(-1)?.text).toBe("current output");
    expect(session().busy).toBe(true);
    await settle(pending[1]);
  });

  it("preserves a queued follow-up until the active turn finishes", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => { actions.onSubmit(session().id, "Follow up", [], { followUpBehavior: "queue" }); });
    expect(pending).toHaveLength(1);
    expect(session().queuedMessages?.[0].text).toBe("Follow up");
    await settle(pending[0]);
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(withoutWidgetRules(pending[1].input.text)).toBe("Follow up");
    expect(session().queuedMessages).toBeUndefined();
    await settle(pending[1]);
  });

  it("retains a startup follow-up rejected as not ready and sends it after the turn", async () => {
    acceptImmediately = false;
    adapter.steerTurn = vi.fn(async () => { throw new TurnNotReadyError("Still connecting"); });
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => { actions.onSubmit(session().id, "Follow up", [], { followUpBehavior: "steer" }); });
    expect(session().queuedMessages?.map((message) => message.text)).toEqual(["Follow up"]);
    expect(session().blocks.map((block) => block.text)).toEqual(["First"]);
    expect(session().busy).toBe(true);
    await settle(pending[0]);
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(withoutWidgetRules(pending[1].input.text)).toBe("Follow up");
    await settle(pending[1]);
  });

  it("retains a queued row's identity until steering is accepted", async () => {
    const steer = deferred<void>();
    adapter.steerTurn = vi.fn(() => steer.promise);
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await act(async () => { actions.onSubmit(session().id, "Queued", [], { followUpBehavior: "queue" }); });
    const queued = session().queuedMessages![0];
    await act(async () => { actions.steerQueuedMessage(session().id, queued.id); });
    expect(session().queuedMessages?.[0]).toBe(queued);
    expect(session().blocks.map((block) => block.text)).toEqual(["First", "Queued"]);
    await act(async () => { steer.resolve(); await steer.promise; });
    expect(session().queuedMessages).toBeUndefined();
    expect(session().blocks.map((block) => block.text)).toEqual(["First", "Queued"]);
    await settle(pending[0]);
  });

  it.each(["edit", "delete", "stop", "switch", "close"] as const)(
    "does not deliver a stale follow-up after %s during preparation", async (change) => {
      await mount(newSession("codex", "/project", "codex:test"));
      const id = session().id;
      await act(async () => { actions.onSubmit(id, "First"); });
      const preparing = deferred<string>();
      mocks.prepare.mockImplementationOnce(() => preparing.promise);
      await act(async () => { actions.onSubmit(id, "Follow up", [], { followUpBehavior: "steer" }); });
      const queued = session().queuedMessages![0];
      await act(async () => {
        if (change === "edit") actions.editQueuedMessage(id, queued.id, "Edited");
        if (change === "delete") actions.deleteQueuedMessage(id, queued.id);
        if (change === "stop") await actions.stop(id);
        if (change === "switch") runtime.updateSessions((sessions) => sessions.map((session) => ({ ...session, harness: "claude" })));
        if (change === "close") runtime.updateSessions([]);
        preparing.resolve("Prepared follow up");
        await preparing.promise;
      });
      expect(adapter.steerTurn).not.toHaveBeenCalled();
      expect(session()?.blocks.some((block) => block.notice === "error" || block.text === "Follow up")).not.toBe(true);
      if (change === "edit") expect(session().queuedMessages?.[0]).toMatchObject({ id: queued.id, text: "Edited" });
      if (change === "delete") expect(session().queuedMessages).toBeUndefined();
      if (change === "stop") expect(session().queueStatus).toBe("paused");
      await settle(pending[0]);
    },
  );

  it("keeps a steered prompt before output streamed ahead of its acknowledgement", async () => {
    const steer = deferred<void>();
    adapter.steerTurn = vi.fn(() => steer.promise);
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await act(async () => { actions.onSubmit(session().id, "Follow up", [], { followUpBehavior: "steer" }); });
    await act(async () => {
      pending[0].input.onEvent({ type: "message.delta", text: "Follow-up answer" });
      runtime.flushEvents();
      steer.resolve();
      await steer.promise;
    });
    expect(session().blocks.map((block) => block.text)).toEqual(["First", "Follow up", "Follow-up answer"]);
    expect(session().queuedMessages).toBeUndefined();
    await settle(pending[0]);
  });

  it("retains edits made while a steering request is in flight", async () => {
    const steer = deferred<void>();
    adapter.steerTurn = vi.fn(() => steer.promise);
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await act(async () => { actions.onSubmit(session().id, "Follow up", [], { followUpBehavior: "steer" }); });
    const queued = session().queuedMessages![0];
    await act(async () => {
      actions.editQueuedMessage(session().id, queued.id, "Edited follow up");
      steer.resolve();
      await steer.promise;
    });
    expect(session().queuedMessages?.[0]).toMatchObject({ id: queued.id, text: "Edited follow up" });
    expect(session().blocks.at(-1)?.text).toBe("Follow up");
    await act(async () => actions.deleteQueuedMessage(session().id, queued.id));
    await settle(pending[0]);
  });

  it("ignores a late steering rejection after Stop and retains the paused row", async () => {
    const steer = deferred<void>();
    adapter.steerTurn = vi.fn(() => steer.promise);
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await act(async () => { actions.onSubmit(session().id, "Follow up", [], { followUpBehavior: "steer" }); });
    await act(async () => {
      await actions.stop(session().id);
      steer.reject(new Error("Old connection closed"));
      await steer.promise.catch(() => undefined);
    });
    expect(session().queueStatus).toBe("paused");
    expect(session().queuedMessages?.[0].text).toBe("Follow up");
    expect(session().blocks.some((block) => block.notice === "error")).toBe(false);
    await settle(pending[0]);
  });

  it("does not auto-send the retained row while its steering response is pending", async () => {
    const steer = deferred<void>();
    adapter.steerTurn = vi.fn(() => steer.promise);
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await act(async () => { actions.onSubmit(session().id, "Follow up", [], { followUpBehavior: "steer" }); });
    await settle(pending[0]);
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
    expect(pending).toHaveLength(1);
    await act(async () => { steer.resolve(); await steer.promise; });
    expect(session().busy).toBe(false);
    expect(session().queuedMessages).toBeUndefined();
    expect(session().blocks.filter((block) => block.text === "Follow up")).toHaveLength(1);
  });

  it("keeps old history visible until an edited replacement is accepted", async () => {
    const initial = newSession("codex", "/project", "codex:test");
    initial.blocks = [
      { id: "old-user", role: "user", text: "Original", providerTurnId: "old-turn" },
      { id: "old-answer", role: "assistant", text: "Original answer" },
    ];
    acceptImmediately = false;
    const rewind = deferred<{ submitted: boolean }>();
    adapter.rewindLastTurn = vi.fn(() => rewind.promise);
    await mount(initial);
    await act(async () => { actions.onSubmit(initial.id, "Replacement", [], { resendEdited: true }); });
    await vi.waitFor(() => expect(adapter.rewindLastTurn).toHaveBeenCalledOnce());
    expect(session().blocks[0].text).toBe("Original");
    await act(async () => rewind.resolve({ submitted: false }));
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => {
      pending[0].input.onEvent({ type: "message.delta", text: "New answer" });
      runtime.flushEvents();
    });
    expect(session().blocks.map((block) => block.text)).toEqual(["Original", "Original answer"]);
    await act(async () => { pending[0].input.onAccepted?.(); runtime.flushEvents(); });
    expect(session().blocks.map((block) => block.text)).toEqual(["Replacement", "New answer"]);
    await settle(pending[0]);
  });

  it("activates Operator per thread and preserves the request receipt", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    const id = session().id;
    await act(async () => { actions.onSubmit(id, "/operator List notes", [], { appRequestId: "app-request-1" }); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(pending[0].input.appAccess).toBe(true);
    expect(withoutWidgetRules(pending[0].input.text)).toContain("<loci_app>");
    expect(withoutWidgetRules(pending[0].input.text)).toContain("list, create, rename, and delete Excalidraw canvases");
    expect(withoutWidgetRules(pending[0].input.text)).toContain("canvas.read-data and canvas.write-data");
    expect(withoutWidgetRules(pending[0].input.text)).toContain("write-data replaces the whole scene and updates open panes");
    expect(withoutWidgetRules(pending[0].input.text)).toContain("loci' app --help");
    expect(session().blocks[0]).toMatchObject({ text: "List notes", loci: true, appRequestId: "app-request-1" });
    await settle(pending[0]);
    await act(async () => { actions.onSubmit(id, "Read the first note"); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(pending[1].input.appAccess).toBe(true);
    expect(withoutWidgetRules(pending[1].input.text)).not.toContain("<loci_app>");
    await settle(pending[1]);
  });

  it("keeps provider and local history rewound when a replacement is rejected", async () => {
    const initial = newSession("codex", "/project", "codex:test");
    initial.blocks = [
      { id: "old-user", role: "user", text: "Original", providerTurnId: "old-turn" },
      { id: "old-answer", role: "assistant", text: "Original answer" },
    ];
    acceptImmediately = false;
    const rejected = vi.fn();
    await mount(initial);
    await act(async () => { actions.onSubmit(initial.id, "Replacement", [], { resendEdited: true, onResendRejected: rejected }); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => {
      pending[0].done.reject(new Error("replacement unavailable"));
      await pending[0].done.promise.catch(() => undefined);
    });
    expect(rejected).toHaveBeenCalledExactlyOnceWith({ providerRewound: true });
    expect(session().blocks.some((block) => block.role === "user")).toBe(false);
    expect(session().blocks.some((block) => block.text === "Original answer")).toBe(false);
    expect(session().blocks.some((block) => block.text.includes("replacement unavailable"))).toBe(true);
    expect(session().busy).toBe(false);
  });



});

describe("agents that reach the built-in tools through the app's CLI", () => {
  const CLI = "'/Applications/Loci.app/Contents/MacOS/loci'";
  const users = () => session().blocks.filter((block) => block.role === "user");
  const bind = (run: Pending, providerSessionId: string) => act(async () => { run.input.onEvent({ type: "session.providerBound", providerSessionId }); });
  beforeEach(() => {
    registerHarness({ ...adapter, id: "pi" });
    registerHarness({ ...adapter, id: "antigravity" });
  });
  afterEach(() => saveCanvasMcpEnabled(true));

  it("tells a Pi agent about the project's canvases once per provider conversation", async () => {
    await mount(newSession("pi", "/project"));
    await act(async () => { expect(actions.onSubmit(session().id, "Draw the architecture")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(withoutWidgetRules(pending[0].input.text).startsWith("Draw the architecture\n\n<loci_canvas>\n")).toBe(true);
    expect(withoutWidgetRules(pending[0].input.text)).toContain(`\`${CLI} canvas TOOL --json '<arguments>'\``);
    // The note is Loci's: the transcript keeps what the user typed, and remembers that it was sent.
    expect(users()[0]).toMatchObject({ text: "Draw the architecture", canvasCli: true });
    expect(mocks.invoke).toHaveBeenCalledWith("control_authorize_turn", { sessionId: session().id, cwd: "/project", appAccess: false, canvasAccess: true });
    await bind(pending[0], "pi-conversation-1");
    await settle(pending[0]);
    await act(async () => { expect(actions.onSubmit(session().id, "Add a cache")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(withoutWidgetRules(pending[1].input.text)).toBe("Add a cache");
    expect(users().map((block) => block.canvasCli)).toEqual([true, undefined]);
  });

  it("says it again when the provider conversation is a new one", async () => {
    const initial = newSession("antigravity", "/project");
    // An earlier conversation was told; this thread has since lost its provider session.
    await mount({ ...initial, blocks: [{ id: "earlier", role: "user", text: "Earlier", canvasCli: true }, { id: "answer", role: "assistant", text: "Done" }] });
    await act(async () => { expect(actions.onSubmit(session().id, "Continue")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(withoutWidgetRules(pending[0].input.text)).toContain("<loci_canvas>");
    expect(withoutWidgetRules(pending[0].input.text)).toContain(`${CLI} canvas --help`);
  });

  it("follows the Excalidraw switch: no note and no access while it is off, the note on the first turn after it is turned on", async () => {
    saveCanvasMcpEnabled(false);
    await mount(newSession("pi", "/project"));
    await act(async () => { expect(actions.onSubmit(session().id, "Draw the architecture")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(withoutWidgetRules(pending[0].input.text)).toBe("Draw the architecture");
    expect(users()[0].canvasCli).toBeUndefined();
    expect(mocks.invoke).toHaveBeenCalledWith("control_authorize_turn", { sessionId: session().id, cwd: "/project", appAccess: false, canvasAccess: false });
    await bind(pending[0], "pi-conversation-1");
    await settle(pending[0]);
    saveCanvasMcpEnabled(true);
    await act(async () => { expect(actions.onSubmit(session().id, "Now draw it")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(withoutWidgetRules(pending[1].input.text).startsWith("Now draw it\n\n<loci_canvas>")).toBe(true);
    expect(mocks.invoke).toHaveBeenLastCalledWith("control_authorize_turn", { sessionId: session().id, cwd: "/project", appAccess: false, canvasAccess: true });
    expect(users().map((block) => block.canvasCli)).toEqual([undefined, true]);
  });

  it("sends no note outside a project, where there are no canvases to reach", async () => {
    await mount(newSession("pi", "~"));
    await act(async () => { expect(actions.onSubmit(session().id, "Hello")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(withoutWidgetRules(pending[0].input.text)).toBe("Hello");
  });

  it("leaves the agents that are given the MCP server alone", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { expect(actions.onSubmit(session().id, "Draw the architecture")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(withoutWidgetRules(pending[0].input.text)).toBe("Draw the architecture");
    expect(users()[0].canvasCli).toBeUndefined();
    expect(mocks.invoke).not.toHaveBeenCalledWith("app_cli_path");
  });


  it("resolves a run with the turn's answer once it has ended", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    let outcome: unknown;
    await act(async () => { void actions.runTurn(session().id, "Check CI").then((result) => { outcome = result; }); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => {
      pending[0].input.onEvent({ type: "message.delta", text: "All green." });
      runtime.flushEvents();
    });
    expect(outcome).toBeUndefined();
    await settle(pending[0]);
    await vi.waitFor(() => expect(outcome).toEqual({ status: "completed", text: "All green." }));
  });

  it("reports a failed run with the provider's error, and a stopped one as cancelled", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    let failed: unknown;
    await act(async () => { void actions.runTurn(session().id, "First").then((result) => { failed = result; }); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => {
      pending[0].input.onEvent({ type: "session.error", message: "Not signed in" });
      pending[0].done.resolve();
      await pending[0].done.promise;
    });
    await vi.waitFor(() => expect(failed).toMatchObject({ status: "failed", error: "Not signed in" }));

    let stopped: unknown;
    await act(async () => { void actions.runTurn(session().id, "Second").then((result) => { stopped = result; }); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    await act(async () => actions.stop(session().id));
    await act(async () => { pending[1].done.resolve(); await pending[1].done.promise; });
    await vi.waitFor(() => expect(stopped).toMatchObject({ status: "cancelled" }));
  });

  it("does not wait on a busy session, whose message would only be queued", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { actions.onSubmit(session().id, "First"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(await actions.runTurn(session().id, "Second")).toEqual({ status: "failed", text: "", error: "The session is busy." });
    expect(session().queuedMessages ?? []).toHaveLength(0);
    await settle(pending[0]);
  });

  it("never saves a hidden run", async () => {
    await mount({ ...newSession("codex", "/project", "codex:test"), ephemeral: true });
    await act(async () => { actions.onSubmit(session().id, "Run the habit"); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await settle(pending[0]);
    await act(async () => runtime.flushPersistence());
    expect(mocks.invoke.mock.calls.some(([command]) => command === "session_upsert")).toBe(false);
    // The provider is told too, so it keeps no thread of its own.
    expect(pending[0].input.ephemeral).toBe(true);
  });

  describe("an agent's conversation", () => {
    const bound = (run: Pending, providerSessionId: string) => act(async () => { run.input.onEvent({ type: "session.providerBound", providerSessionId }); });
    const files = { id: "a", dir: "/data/agents/a", soul: "# Soul\n\n- Be brief.", soulHash: "soul-1", memory: "- 2026-10-01 · CI runs on Actions", memoryHash: "memory-1", memoryPath: "/data/agents/a/MEMORY.md", topics: [] };
    async function mountAgent(extra: Partial<Session> = {}) {
      const chat = { ...newSession("codex", "/home/me", "codex:test"), ...extra };
      const agent = createAgent(["/code/app"]);
      saveAgentSessionId(agent.id, chat.id);
      const invoke = mocks.invoke.getMockImplementation()!;
      mocks.invoke.mockImplementation(async (command: string, args?: never) => command === "agent_load" ? files : invoke(command, args));
      await mount(chat);
    }

    it("queues follow-ups using the saved preference and dispatches them in order", async () => {
      saveFollowUpBehavior("queue");
      await mountAgent();
      await act(async () => { expect(actions.onSubmit(session().id, "First")).toBe(true); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      await bound(pending[0], "thread-1");
      await act(async () => {
        expect(actions.onSubmit(session().id, "Second")).toBe(true);
        expect(actions.onSubmit(session().id, "Third")).toBe(true);
      });
      expect(adapter.sendTurn).toHaveBeenCalledOnce();
      expect(adapter.steerTurn).not.toHaveBeenCalled();
      expect(session().queuedMessages?.map((message) => message.text)).toEqual(["Second", "Third"]);
      expect(session().blocks.map((block) => block.text)).toEqual(["First"]);

      await settle(pending[0]);
      await act(async () => vi.waitFor(() => expect(pending).toHaveLength(2)));
      expect(withoutWidgetRules(pending[1].input.text)).toBe("Second");
      expect(session().queuedMessages?.map((message) => message.text)).toEqual(["Third"]);

      await settle(pending[1]);
      await act(async () => vi.waitFor(() => expect(pending).toHaveLength(3)));
      expect(withoutWidgetRules(pending[2].input.text)).toBe("Third");
      expect(session().queuedMessages).toBeUndefined();
      expect(adapter.steerTurn).not.toHaveBeenCalled();
      await settle(pending[2]);
    });

    it("steers the active turn immediately using the saved preference", async () => {
      saveFollowUpBehavior("steer");
      await mountAgent();
      await act(async () => { expect(actions.onSubmit(session().id, "First")).toBe(true); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      await act(async () => { expect(actions.onSubmit(session().id, "Follow up")).toBe(true); });
      expect(adapter.steerTurn).toHaveBeenCalledWith(expect.objectContaining({
        sessionId: session().id, text: expect.stringMatching(/^Follow up\n\n<loci_widgets>/),
      }));
      expect(adapter.sendTurn).toHaveBeenCalledOnce();
      expect(session().busy).toBe(true);
      expect(session().queuedMessages).toBeUndefined();
      expect(session().blocks.map((block) => block.text)).toEqual(["First", "Follow up"]);
      await settle(pending[0]);
    });

    it("uses a changed follow-up preference for the next send", async () => {
      saveFollowUpBehavior("queue");
      await mountAgent();
      await act(async () => { expect(actions.onSubmit(session().id, "First")).toBe(true); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      await bound(pending[0], "thread-1");
      await act(async () => { expect(actions.onSubmit(session().id, "Queued")).toBe(true); });
      expect(session().queuedMessages?.map((message) => message.text)).toEqual(["Queued"]);
      expect(adapter.steerTurn).not.toHaveBeenCalled();

      saveFollowUpBehavior("steer");
      await act(async () => { expect(actions.onSubmit(session().id, "Steered")).toBe(true); });
      expect(adapter.steerTurn).toHaveBeenCalledWith(expect.objectContaining({ text: expect.stringMatching(/^Steered\n\n<loci_widgets>/) }));
      expect(session().queuedMessages?.map((message) => message.text)).toEqual(["Queued"]);
      expect(adapter.sendTurn).toHaveBeenCalledOnce();

      await settle(pending[0]);
      await act(async () => vi.waitFor(() => expect(pending).toHaveLength(2)));
      expect(withoutWidgetRules(pending[1].input.text)).toBe("Queued");
      expect(session().queuedMessages).toBeUndefined();
      await settle(pending[1]);
    });

    it("tells a fresh provider session who it is, then only what changed", async () => {
      await mountAgent();
      await act(async () => { actions.onSubmit(session().id, "What broke?"); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      const first = pending[0].input;
      expect(first.appAccess).toBe(true);
      expect(first.text.startsWith("<loci_context>")).toBe(true);
      expect(withoutWidgetRules(first.text).endsWith("</loci_context>\n\nWhat broke?")).toBe(true);
      expect(first.text).toContain("You are Ember: a resident agent in Loci");
      expect(first.text).toContain("- app: /code/app");
      expect(first.text).toContain("- Be brief.");
      expect(first.text).toContain("CI runs on Actions");
      expect(first.text).toContain("App access is always enabled in this thread.");
      // What the user sees is only what they wrote.
      expect(session().blocks[0].text).toBe("What broke?");
      await bound(pending[0], "thread-1");
      await settle(pending[0]);

      await act(async () => { actions.onSubmit(session().id, "And now?"); });
      await vi.waitFor(() => expect(pending).toHaveLength(2));
      expect(pending[1].input).toMatchObject({ appAccess: true, text: expect.stringMatching(/^And now\?\n\n<loci_widgets>/) });
      await settle(pending[1]);

      files.memory += "\n- 2026-10-02 · Deploys go through Fly";
      files.memoryHash = "memory-2";
      await act(async () => { actions.onSubmit(session().id, "Third"); });
      await vi.waitFor(() => expect(pending).toHaveLength(3));
      expect(withoutWidgetRules(pending[2].input.text)).toContain("Deploys go through Fly");
      expect(withoutWidgetRules(pending[2].input.text)).not.toContain("<soul>");
      expect(withoutWidgetRules(pending[2].input.text)).not.toContain("<loci_app>");
      await settle(pending[2]);
    });

    it("starts a fresh provider session, briefed on the chat, once its context is nearly full", async () => {
      await mountAgent({
        providerSessionId: "thread-1", context: { used: 170_000, window: 200_000 },
        blocks: [
          { id: "u1", role: "user", text: "Rename the flag to --dry-run" },
          { id: "a1", role: "assistant", text: "Renamed in cli.ts and the docs." },
        ] as Session["blocks"],
      });
      await act(async () => { actions.onSubmit(session().id, "Ship it"); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      expect(adapter.forgetSession).toHaveBeenCalledWith(session().id);
      const text = pending[0].input.text;
      expect(text).toContain("<previous_conversation>");
      expect(text).toContain("Rename the flag to --dry-run");
      expect(text).toContain("Renamed in cli.ts and the docs.");
      expect(text).toContain("<soul>");
      expect(withoutWidgetRules(text).endsWith("Ship it")).toBe(true);
      expect(session().providerSessionId).toBeUndefined();
      expect(session().context).toBeUndefined();
      await settle(pending[0]);
    });

    it("opens a new agent's chat with the app's setup message, shown as a marker", async () => {
      await mountAgent();
      await act(async () => { await actions.submit(session().id, "Ember joined", [], { agentSetup: "<agent_setup>Ask what you are for.</agent_setup>" }); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      const text = pending[0].input.text;
      // It learns who it is first, then what the app asks of it; the user's chat shows neither.
      expect(text.startsWith("<loci_context>")).toBe(true);
      expect(withoutWidgetRules(text).endsWith("<agent_setup>Ask what you are for.</agent_setup>")).toBe(true);
      expect(text).not.toContain("Ember joined");
      expect(session().blocks[0]).toMatchObject({ role: "user", text: "Ember joined", agentSetup: true });
      await settle(pending[0]);
    });

    it("sends the turn without its memory when the files cannot be read", async () => {
      await mountAgent();
      mocks.invoke.mockImplementation(async (command: string) => { if (command === "agent_load") throw new Error("disk"); return undefined; });
      await act(async () => { actions.onSubmit(session().id, "Hello"); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      expect(withoutWidgetRules(pending[0].input.text)).toBe("Hello");
      await settle(pending[0]);
    });
  });

  describe("a question left standing", () => {
    const asked = 'Which one?\n\n```loci-question\n{"questions":[{"header":"Pick","question":"Which one?","options":[{"label":"First"},{"label":"Second"}]}]}\n```';
    async function ask() {
      await mount(newSession("codex", "/project", "codex:test"));
      await act(async () => { actions.onSubmit(session().id, "Help me choose"); });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      await act(async () => { pending[0].input.onEvent({ type: "message.delta", text: asked }); runtime.flushEvents(); });
      await settle(pending[0]);
      await vi.waitFor(() => expect(session().busy).toBeFalsy());
    }

    it("stays after the turn that asked it has ended", async () => {
      await ask();
      expect(session().pendingQuestion).toMatchObject({ standing: true, title: "Pick" });
      expect(session().pendingQuestion!.questions[0].options.map((option) => option.label)).toEqual(["First", "Second"]);
    });

    it("sends the choice as the user's next message, which settles it", async () => {
      await ask();
      const question = session().pendingQuestion!;
      await act(async () => actions.answer(session().id, question.requestId, { kind: "answered", answers: { [question.questions[0].id]: [question.questions[0].options[1].id] } }));
      await vi.waitFor(() => expect(pending).toHaveLength(2));
      expect(withoutWidgetRules(pending[1].input.text)).toBe("Second");
      expect(session().pendingQuestion).toBeUndefined();
      expect(adapter.respondQuestion).not.toHaveBeenCalled();
      await settle(pending[1]);
    });

    it("is put away when skipped, and when the user writes something else", async () => {
      await ask();
      await act(async () => actions.answer(session().id, session().pendingQuestion!.requestId, { kind: "skipped" }));
      expect(session().pendingQuestion).toBeUndefined();
      expect(pending).toHaveLength(1);
    });
  });
});
