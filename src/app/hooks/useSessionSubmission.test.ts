// @vitest-environment happy-dom
import { act,createElement,useRef,useState } from "react";
import { createRoot,type Root } from "react-dom/client";
import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { newSession,type Session } from "../../features/sessions/model/session";
import { registerHarness,resetHarnessIdlePark,type HarnessAdapter } from "../../integrations/harness/core/registry";
import { TurnNotReadyError, type SendTurnInput } from "../../integrations/harness/core/types";
import { useSessionRuntime,type SessionRuntime } from "./useSessionRuntime";
import { useSessionSubmission,type SessionSubmission } from "./useSessionSubmission";

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

async function mount(initial: Session) {
  function Harness() {
    const [sessions, setSessions] = useState([initial]);
    const sessionsRef = useRef(sessions);
    sessionsRef.current = sessions;
    runtime = useSessionRuntime({ sessions, sessionsRef, setSessions });
    actions = useSessionSubmission({ runtime });
    return null;
  }
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  await act(async () => root.render(createElement(Harness)));
}

function session() { return runtime.sessionsRef.current[0]; }
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
  mocks.prepare.mockReset();
  mocks.prepare.mockImplementation(async (text: string) => text);
  mocks.invoke.mockReset();
  mocks.invoke.mockImplementation(async (command: string, args?: { session?: Session }) => {
    if (command === "app_cli_path") return "/Applications/Loci.app/Contents/MacOS/loci";
    if (command === "session_upsert") return { ...args?.session, createdAt: 1, updatedAt: Date.now() };
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

describe("session submission", () => {
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
    expect(mocks.invoke).toHaveBeenCalledWith("control_authorize_turn", { sessionId: session().id, cwd: "/project", appAccess: false, learnAccess: false });
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
    expect(pending[1].input.text).toBe("Follow up");
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
    expect(pending[1].input.text).toBe("Follow up");
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
    expect(pending[0].input.text).toContain("<loci_app>");
    expect(pending[0].input.text).toContain("list, create, rename, and delete Excalidraw canvases");
    expect(pending[0].input.text).toContain("canvas.read-data and canvas.write-data");
    expect(pending[0].input.text).toContain("write-data replaces the whole scene and updates open panes");
    expect(pending[0].input.text).toContain("loci' app --help");
    expect(session().blocks[0]).toMatchObject({ text: "List notes", loci: true, appRequestId: "app-request-1" });
    await settle(pending[0]);
    await act(async () => { actions.onSubmit(id, "Read the first note"); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(pending[1].input.appAccess).toBe(true);
    expect(pending[1].input.text).not.toContain("<loci_app>");
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
  it("starts a learning thread with /learn: the command leaves the message, the rules go to the agent once, access stays", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { expect(actions.onSubmit(session().id, "/learn kubernetes")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(session().blocks[0]).toMatchObject({ role: "user", text: "kubernetes", learn: true });
    expect(pending[0].input).toMatchObject({ learnAccess: true, appAccess: false });
    expect(pending[0].input.text.startsWith("kubernetes\n\n<loci_learn>")).toBe(true);
    expect(mocks.invoke).toHaveBeenCalledWith("control_authorize_turn", { sessionId: session().id, cwd: "/project", appAccess: false, learnAccess: true });
    await settle(pending[0]);
    await act(async () => { expect(actions.onSubmit(session().id, "Service 是什么？")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(pending[1].input).toMatchObject({ learnAccess: true, text: "Service 是什么？" });
    expect(session().blocks.filter((block) => block.role === "user").map((block) => block.learn)).toEqual([true, undefined]);
  });

  it("continues on the map when /learn is sent alone, and tells the agent which node a session was opened from", async () => {
    await mount(newSession("codex", "/project", "codex:test"));
    await act(async () => { expect(actions.onSubmit(session().id, "/learn")).toBe(true); });
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    expect(session().blocks[0].text).toBe("Continue on my learning map.");
    await settle(pending[0]);
    await act(async () => { await actions.submit(session().id, "/learn Service", [], { learnFocus: { nodeId: "n42", intent: "revisit" } }); });
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    expect(pending[1].input.text).toContain('<loci_learn_focus>The learner opened this session from the map node with id "n42", named in their message, to revisit it.');
  });

  it("refuses /learn where the learning map cannot be reached, without starting a turn", async () => {
    await mount(newSession("codex", "~", "codex:test"));
    await act(async () => { expect(actions.onSubmit(session().id, "/learn kubernetes")).toBe(false); });
    expect(pending).toHaveLength(0);
    expect(session().blocks.some((block) => block.role === "user")).toBe(false);
    expect(JSON.stringify(session().blocks)).toContain("one learning map per project");
  });

  it("refuses /learn on a provider that is not given the learning server", async () => {
    await mount(newSession("cursor", "/project"));
    await act(async () => { expect(actions.onSubmit(session().id, "/learn kubernetes")).toBe(false); });
    expect(pending).toHaveLength(0);
    expect(JSON.stringify(session().blocks)).toContain("needs a Claude Code or Codex session");
  });
});
