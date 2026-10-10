// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { adoptStoredWidget, changeWidgetState, currentWidget, parseRuntimeMessage, refreshWidget, retainWidget, seedWidget, useWidget } from "./widgetRuntime";
import { getLearningWidget, setLearningWidgetSaved, setLearningWidgetState, subscribeLearningChanges } from "./learningStore";
import type { JsonValue, StoredWidget, WidgetRef } from "./types";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("./learningStore", () => ({ getLearningWidget: vi.fn(), setLearningWidgetSaved: vi.fn(), setLearningWidgetState: vi.fn(), subscribeLearningChanges: vi.fn() }));

const spec = { id: "cache", title: "Cache", html: "<div>Cache</div>", sourceIds: ["source-a"] };
const ref = (): WidgetRef => ({ owner: { kind: "session", id: crypto.randomUUID() }, id: "cache" });
const stored = (widget: WidgetRef, saved: boolean): StoredWidget => ({ ...spec, owner: widget.owner, saved, state: {}, sourceSessionId: widget.owner.id, sourceBlockId: "block-a", revision: 1, createdAt: 1, updatedAt: 1 });
beforeEach(() => { vi.resetAllMocks(); vi.mocked(setLearningWidgetState).mockResolvedValue(undefined); });

describe("widget state ownership", () => {
  it("shares unsaved state across inline and expanded views without a native write", async () => {
    const widget = ref();
    seedWidget(widget, spec, widget.owner.id);
    await changeWidgetState(widget, { age: 10 });
    expect(seedWidget(widget, spec, widget.owner.id).state).toEqual({ age: 10 });
    expect(setLearningWidgetState).not.toHaveBeenCalled();
  });

  it("restores saved state and persists subsequent changes", async () => {
    const widget = ref();
    adoptStoredWidget({ ...stored(widget, true), state: { age: 5 } });
    expect(currentWidget(widget)?.state).toEqual({ age: 5 });
    await changeWidgetState(widget, { age: 12 });
    expect(setLearningWidgetState).toHaveBeenCalledWith(widget, { age: 12 });
  });

  it("retains the current exploratory state on an HTML revision and when explicitly saving", async () => {
    const widget = ref();
    seedWidget(widget, spec, widget.owner.id);
    await changeWidgetState(widget, { age: 10, comparison: "fresh" });
    adoptStoredWidget({ ...stored(widget, false), revision: 2, html: "<div>Revised</div>" });
    expect(currentWidget(widget)?.state).toEqual({ age: 10, comparison: "fresh" });
    vi.mocked(setLearningWidgetSaved).mockResolvedValue({ ...currentWidget(widget)!, saved: true });
    await retainWidget(widget, true);
    expect(setLearningWidgetState).toHaveBeenCalledWith(widget, { age: 10, comparison: "fresh" });
    expect(currentWidget(widget)?.saved).toBe(true);
  });

  it("does not replace the latest source when an earlier read finishes later", async () => {
    const widget = ref();
    let finishEarlier!: (value: StoredWidget) => void;
    vi.mocked(getLearningWidget).mockReturnValueOnce(new Promise((resolve) => { finishEarlier = resolve; }));
    const earlierRead = refreshWidget(widget);
    const latest = { ...stored(widget, false), revision: 2, html: "<div>Latest explanation</div>", state: { age: 22 } };
    vi.mocked(getLearningWidget).mockResolvedValueOnce(latest);
    await refreshWidget(widget);
    finishEarlier(stored(widget, true));
    await earlierRead;
    expect(currentWidget(widget)).toEqual(latest);
  });

  it("accepts retention changes at the same source revision", () => {
    const widget = ref();
    const latest = { ...stored(widget, false), revision: 2, html: "<div>Latest explanation</div>" };
    adoptStoredWidget(latest);
    adoptStoredWidget({ ...latest, saved: true });
    expect(currentWidget(widget)).toEqual({ ...latest, saved: true });
    adoptStoredWidget({ ...latest, saved: false });
    expect(currentWidget(widget)?.saved).toBe(false);
  });
});

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((accept, refuse) => { resolve = accept; reject = refuse; });
  return { promise, resolve, reject };
}

describe("native widget writes across inline and expanded panes", () => {
  let root: Root;
  let container: HTMLDivElement;

  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
  });
  afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

  async function openPanes(saved = false) {
    const widget = ref();
    const database = stored(widget, saved);
    const reads: { snapshot: StoredWidget; response: ReturnType<typeof deferred<StoredWidget>> }[] = [];
    const writes: { state: JsonValue; response: ReturnType<typeof deferred<void>> }[] = [];
    const native = { delayReads: false, saveError: undefined as Error | undefined };
    const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value));
    vi.mocked(invoke).mockImplementation(async (command, input) => {
      if (command === "learning_widget_get") {
        const snapshot = clone(database);
        if (!native.delayReads) return snapshot as never;
        const response = deferred<StoredWidget>();
        reads.push({ snapshot, response });
        return response.promise as never;
      }
      if (command === "learning_widget_save") {
        if (native.saveError) throw native.saveError;
        database.saved = (input as { saved: boolean }).saved;
        return clone(database) as never;
      }
      if (command === "learning_widget_state") {
        const state = clone((input as { state: JsonValue }).state);
        const response = deferred<void>();
        writes.push({ state, response });
        await response.promise;
        // Match Rust's saved=1 condition when the queued native write executes.
        if (database.saved) database.state = state;
        return undefined as never;
      }
      throw new Error(`Unexpected command: ${command}`);
    });
    const actual = await vi.importActual<typeof import("./learningStore")>("./learningStore");
    vi.mocked(getLearningWidget).mockImplementation(actual.getLearningWidget);
    vi.mocked(setLearningWidgetSaved).mockImplementation(actual.setLearningWidgetSaved);
    vi.mocked(setLearningWidgetState).mockImplementation(actual.setLearningWidgetState);
    vi.mocked(subscribeLearningChanges).mockImplementation(actual.subscribeLearningChanges);
    adoptStoredWidget(clone(database));
    function Pane() {
      const current = useWidget(widget, spec, widget.owner.id);
      return createElement("output", null, JSON.stringify({ saved: current.saved, state: current.state }));
    }
    await act(async () => root.render(createElement("div", null, createElement(Pane), createElement(Pane))));
    const finishReads = async () => {
      await act(async () => {
        native.delayReads = false;
        // Older native snapshots arriving last must not roll back local interaction state.
        for (const read of reads.splice(0).reverse()) read.response.resolve(read.snapshot);
      });
    };
    const shown = () => [...container.querySelectorAll("output")].map((output) => JSON.parse(output.textContent!));
    return { widget, database, reads, writes, native, finishReads, shown };
  }

  it("persists changes made while Keep is flushing the first saved state, before refresh reads return", async () => {
    const setup = await openPanes();
    await act(async () => { await changeWidgetState(setup.widget, { step: 1 }); });
    setup.native.delayReads = true;
    let saving!: Promise<void>;
    await act(async () => { saving = retainWidget(setup.widget, true); });
    expect(setup.writes).toHaveLength(1);
    expect(setup.reads).toHaveLength(2); // The real write()->changed()->two subscriptions->get path.
    let changing!: Promise<void>;
    await act(async () => { changing = changeWidgetState(setup.widget, { step: 2 }); });
    await act(async () => { setup.writes[0].response.resolve(); await saving; });
    await act(async () => {
      setup.writes[1]?.response.resolve();
      await changing;
    });
    await setup.finishReads();
    expect(setup.database.state).toEqual({ step: 2 });
    expect(setup.writes.map((write) => write.state)).toEqual([{ step: 1 }, { step: 2 }]);
    expect(setup.shown()).toEqual([{ saved: true, state: { step: 2 } }, { saved: true, state: { step: 2 } }]);
  });

  it("writes successive saved interactions in order while both panes show the latest state", async () => {
    const setup = await openPanes(true);
    let first!: Promise<void>;
    let second!: Promise<void>;
    await act(async () => {
      first = changeWidgetState(setup.widget, { step: 1 });
      second = changeWidgetState(setup.widget, { step: 2 });
    });
    expect(setup.shown()).toEqual([{ saved: true, state: { step: 2 } }, { saved: true, state: { step: 2 } }]);
    expect(setup.writes).toHaveLength(1);
    await act(async () => { setup.writes[0].response.resolve(); await first; });
    expect(setup.writes).toHaveLength(2);
    await act(async () => { setup.writes[1].response.resolve(); await second; });
    expect(setup.database.state).toEqual({ step: 2 });
  });

  it("does not let pre-Keep refresh reads undo acknowledged retention or skip later writes", async () => {
    const setup = await openPanes();
    await act(async () => { await changeWidgetState(setup.widget, { step: 1 }); });
    setup.native.delayReads = true;
    // A preceding native write starts the two refresh reads before Keep commits.
    await act(async () => { await setLearningWidgetSaved(setup.widget, false); });
    const beforeKeep = setup.reads.splice(0);
    expect(beforeKeep.map((read) => read.snapshot.saved)).toEqual([false, false]);
    let saving!: Promise<void>;
    await act(async () => { saving = retainWidget(setup.widget, true); });
    expect(currentWidget(setup.widget)?.saved).toBe(true);
    await act(async () => { for (const read of beforeKeep) read.response.resolve(read.snapshot); });
    expect(currentWidget(setup.widget)?.saved).toBe(true);
    let changing!: Promise<void>;
    await act(async () => { changing = changeWidgetState(setup.widget, { step: 2 }); });
    await act(async () => { setup.writes[0].response.resolve(); await saving; });
    await act(async () => { setup.writes[1].response.resolve(); await changing; });
    await setup.finishReads();
    expect(setup.database.state).toEqual({ step: 2 });
    expect(setup.shown()).toEqual([{ saved: true, state: { step: 2 } }, { saved: true, state: { step: 2 } }]);
  });

  it("propagates failed Keep without changing retention or discarding local state", async () => {
    const setup = await openPanes();
    await act(async () => { await changeWidgetState(setup.widget, { step: 1 }); });
    setup.native.saveError = new Error("Save unavailable");
    await act(async () => { await expect(retainWidget(setup.widget, true)).rejects.toThrow("Save unavailable"); });
    expect(setup.database.saved).toBe(false);
    expect(setup.writes).toHaveLength(0);
    expect(setup.shown()).toEqual([{ saved: false, state: { step: 1 } }, { saved: false, state: { step: 1 } }]);
  });

  it("keeps acknowledged retention and recovers later writes after the initial state write fails", async () => {
    const setup = await openPanes();
    await act(async () => { await changeWidgetState(setup.widget, { step: 1 }); });
    setup.native.delayReads = true;
    let saving!: Promise<void>;
    await act(async () => { saving = retainWidget(setup.widget, true); });
    const failure = expect(saving).rejects.toThrow("State unavailable");
    await act(async () => { setup.writes[0].response.reject(new Error("State unavailable")); await failure; });
    expect(currentWidget(setup.widget)?.saved).toBe(true);
    let changing!: Promise<void>;
    await act(async () => { changing = changeWidgetState(setup.widget, { step: 2 }); });
    await act(async () => { setup.writes[1].response.resolve(); await changing; });
    await setup.finishReads();
    expect(setup.database.state).toEqual({ step: 2 });
    expect(setup.shown()).toEqual([{ saved: true, state: { step: 2 } }, { saved: true, state: { step: 2 } }]);
  });

  it("keeps unsaved interactions local while an earlier write drains, then retains their latest state", async () => {
    const setup = await openPanes(true);
    let changing!: Promise<void>;
    await act(async () => { changing = changeWidgetState(setup.widget, { step: 1 }); });
    setup.native.delayReads = true;
    await act(async () => { await retainWidget(setup.widget, false); });
    await act(async () => { await changeWidgetState(setup.widget, { step: 2 }); });
    expect(setup.writes).toHaveLength(1);
    await act(async () => { setup.writes[0].response.resolve(); await changing; });
    await setup.finishReads();
    expect(setup.database.saved).toBe(false);
    expect(setup.database.state).toEqual({});
    expect(setup.shown()).toEqual([{ saved: false, state: { step: 2 } }, { saved: false, state: { step: 2 } }]);
    let saving!: Promise<void>;
    await act(async () => { saving = retainWidget(setup.widget, true); });
    await act(async () => { setup.writes[1].response.resolve(); await saving; });
    expect(setup.database.state).toEqual({ step: 2 });
  });
});

describe("runtime capability boundary", () => {
  it("accepts only referenced source ids and editable question text", () => {
    expect(parseRuntimeMessage({ type: "source", id: "source-a" }, ["source-a"])).toEqual({ type: "source", id: "source-a" });
    expect(parseRuntimeMessage({ type: "source", id: "another-source" }, ["source-a"])).toBeUndefined();
    expect(parseRuntimeMessage({ type: "native", command: "read_file" }, [])).toBeUndefined();
    expect(parseRuntimeMessage({ type: "ask", text: "Why?", targetSessionId: "other-session" }, [])).toEqual({ type: "ask", text: "Why?" });
  });

  it("rejects invalid JSON state and keeps resizing within the inline surface", () => {
    expect(parseRuntimeMessage({ type: "state", state: { count: Infinity } }, [])).toBeUndefined();
    const cyclic: Record<string, unknown> = {}; cyclic.self = cyclic;
    expect(parseRuntimeMessage({ type: "state", state: cyclic }, [])).toBeUndefined();
    expect(parseRuntimeMessage({ type: "resize", height: 50_000 }, [])).toEqual({ type: "resize", height: 1000 });
  });
});
