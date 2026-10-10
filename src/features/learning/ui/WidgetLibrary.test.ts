// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { LEARNING_CHANGED_EVENT } from "../model/learningStore";
import type { StoredWidget, WidgetOwner } from "../model/types";
import { OPEN_WIDGET_EVENT, type OpenWidgetDetail } from "../model/widgets";
import { WidgetLibrary } from "./WidgetLibrary";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

const owner: WidgetOwner = { kind: "agent", id: "agent-a" };
function widget(title = "Cache lifecycle", widgetOwner = owner): StoredWidget {
  return {
    owner: widgetOwner, id: "cache", title, subject: "Distributed systems",
    html: "<div>Cache trace</div>", sourceIds: [], sourceSessionId: "original-chat",
    sourceBlockId: "answer", revision: 1, saved: true, state: {},
    createdAt: 1, updatedAt: new Date(2026, 9, 10).getTime(),
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((finish) => { resolve = finish; });
  return { promise, resolve };
}

let root: Root;
let container: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.mocked(invoke).mockReset().mockResolvedValue([]);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

async function render(currentOwner = owner) {
  await act(async () => root.render(createElement(WidgetLibrary, { owner: currentOwner })));
}
async function refresh() {
  await act(async () => window.dispatchEvent(new Event(LEARNING_CHANGED_EVENT)));
}
function buttons() {
  return [...container.querySelectorAll<HTMLButtonElement>("button")];
}

it("distinguishes a pending load from a confirmed empty library", async () => {
  const pending = deferred<StoredWidget[]>();
  vi.mocked(invoke).mockReturnValueOnce(pending.promise);
  await render();
  expect(container.querySelector('[role="status"]')?.textContent).toBe("Loading…");
  expect(container.textContent).not.toContain("No saved explanations yet.");

  await act(async () => pending.resolve([]));
  expect(container.querySelector('[role="status"]')).toBeNull();
  expect(container.textContent).toContain("No saved explanations yet.");
  expect(container.textContent).toContain("Keep an explanation from the chat to find it here.");
});

it("offers a retry after an initial failure without claiming the library is empty", async () => {
  vi.mocked(invoke).mockRejectedValueOnce(new Error("database unavailable"));
  await render();
  expect(container.querySelector('[role="alert"]')?.textContent).toBe("Could not load saved explanations.");
  expect(container.textContent).not.toContain("No saved explanations yet.");
  expect(container.querySelector('[role="status"]')).toBeNull();

  vi.mocked(invoke).mockResolvedValueOnce([widget()]);
  await act(async () => buttons().find((button) => button.textContent?.trim() === "Retry")!.click());
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(buttons().map((button) => button.textContent)).toEqual(["Cache lifecycle"]);
  expect(invoke).toHaveBeenLastCalledWith("learning_widgets_list", { owner, savedOnly: true });
});

it("retains available explanations when a refresh fails", async () => {
  vi.mocked(invoke).mockResolvedValueOnce([widget()]);
  await render();
  vi.mocked(invoke).mockRejectedValueOnce(new Error("refresh unavailable"));
  await refresh();
  expect(container.querySelector('[role="alert"]')).not.toBeNull();
  expect(buttons().find((button) => button.textContent === "Cache lifecycle")).toBeDefined();
});

it("keeps row text focused on the title and opens the explanation in its original context", async () => {
  const saved = widget("A retained cache trace with a complete, readable explanation title");
  vi.mocked(invoke).mockResolvedValueOnce([saved]);
  const opened = vi.fn((event: Event) => (event as CustomEvent<OpenWidgetDetail>).detail);
  window.addEventListener(OPEN_WIDGET_EVENT, opened);
  try {
    await render();
    const button = buttons()[0];
    expect(button.textContent).toBe(saved.title);
    expect(button.title).toContain(saved.title);
    expect(button.title).toContain("Interactive explanation");
    expect(button.title).toContain(saved.subject);
    expect(container.querySelector("h3")).toBeNull();
    act(() => button.click());
    expect(opened).toHaveBeenCalledOnce();
    expect(opened.mock.results[0].value).toEqual({
      widget: { owner, id: saved.id }, sourceSessionId: saved.sourceSessionId, title: saved.title,
    });
  } finally {
    window.removeEventListener(OPEN_WIDGET_EVENT, opened);
  }
});

it("does not replace a newer list when an earlier load finishes late", async () => {
  const earlier = deferred<StoredWidget[]>();
  vi.mocked(invoke).mockReturnValueOnce(earlier.promise);
  await render();
  vi.mocked(invoke).mockResolvedValueOnce([widget("Latest explanation")]);
  await refresh();
  await act(async () => earlier.resolve([widget("Stale explanation")]));
  expect(buttons().map((button) => button.textContent)).toEqual(["Latest explanation"]);
});

it("uses owner identity rather than object identity and ignores a previous owner's late response", async () => {
  vi.mocked(invoke).mockResolvedValueOnce([widget("Agent A explanation")]);
  await render();
  await render({ ...owner });
  expect(invoke).toHaveBeenCalledOnce();

  const oldRefresh = deferred<StoredWidget[]>();
  vi.mocked(invoke).mockReturnValueOnce(oldRefresh.promise);
  await refresh();
  const nextOwner: WidgetOwner = { kind: "session", id: "session-b" };
  const nextLoad = deferred<StoredWidget[]>();
  vi.mocked(invoke).mockReturnValueOnce(nextLoad.promise);
  await render(nextOwner);
  expect(buttons()).toHaveLength(0);
  expect(container.querySelector('[role="status"]')).not.toBeNull();
  await act(async () => oldRefresh.resolve([widget("Late Agent A explanation")]));
  expect(buttons()).toHaveLength(0);

  await act(async () => nextLoad.resolve([widget("Session B explanation", nextOwner)]));
  expect(buttons().map((button) => button.textContent)).toEqual(["Session B explanation"]);
});
