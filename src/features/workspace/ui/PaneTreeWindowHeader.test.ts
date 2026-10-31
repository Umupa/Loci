// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { newSession } from "../../sessions/model/session";
import type { LayoutNode } from "../model/layout";
import { PaneTree } from "./PaneTree";

vi.mock("../../sessions/ui/SessionPane", () => ({
  SessionPane: ({ session, onPaneDragStart }: { session: { id: string }; onPaneDragStart?: ComponentProps<typeof PaneHeader>["onPaneDragStart"] }) =>
    createElement(PaneHeader, { onPaneDragStart }, session.id),
}));

let host: HTMLDivElement;
let root: Root;
let width: number;
let resize: () => void;
const back = vi.fn();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.clearAllMocks();
  width = 1000;
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockImplementation(() => width);
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockImplementation(function () {
    return this.hasAttribute("data-window-pane-nav") ? 142 : 0;
  });
  vi.stubGlobal("ResizeObserver", class {
    constructor(callback: () => void) { resize = callback; }
    observe() {}
    disconnect() {}
  });
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function split(ids: string[], sizes: number[], dir: "right" | "down" = "right"): LayoutNode {
  return { type: "split", id: "split", dir, sizes, children: ids.map((id) => ({ type: "leaf", id })) };
}
function render(layout: LayoutNode, focusedId = "first") {
  const noop = vi.fn();
  const props = {
    visible: true, layout, focusedId, composerFocused: false, recents: [],
    sessions: ["first", "second", "third"].map((id) => ({ ...newSession("claude", "/project"), id })),
    onFocus: noop, onClose: noop, onRatio: noop, onCwdChange: noop, onModelChange: noop,
    onModelSettingsChange: noop, onRuntimeModeChange: noop, onSubmit: noop, onSaveDraft: noop,
    onRemoveDraft: noop, onStop: noop, onCompactContext: noop,
    onDeleteQueuedMessage: noop, onEditQueuedMessage: noop, onQueuedMessageEditingChange: noop,
    onSteerQueuedMessage: noop, onResumeQueue: noop, onApproval: noop, onQuestionReply: noop,
    onOpenFile: noop, onMovePane: noop,
    windowHeader: { leading: createElement("button", { onClick: back }, "Back") },
  } satisfies ComponentProps<typeof PaneTree>;
  act(() => root.render(createElement(PaneTree, props)));
}
const header = (id: string) => host.querySelector<HTMLElement>(`[data-pane-id="${id}"] [data-pane-header]`)!;

it("keeps window navigation fixed while focus, width and pane order change", () => {
  render(split(["first", "second"], [0.2, 0.8]));
  const nav = host.querySelector("[data-window-pane-nav]")!;
  expect(header("first").classList.contains("h-10")).toBe(true);
  expect(header("first").style.paddingLeft).toBe("150px");
  expect(header("second").style.paddingLeft).toBe("8px");
  render(split(["first", "second"], [0.2, 0.8]), "second");
  expect(host.querySelector("[data-window-pane-nav]")).toBe(nav);
  width = 500;
  act(() => resize());
  expect(header("second").style.paddingLeft).toBe("50px");
  render(split(["second", "first"], [0.5, 0.5]), "second");
  expect(header("second").style.paddingLeft).toBe("150px");
  expect(header("first").style.paddingLeft).toBe("8px");
  expect(host.querySelector("[data-window-pane-nav]")).toBe(nav);
  act(() => nav.querySelector<HTMLButtonElement>("button")!.click());
  expect(back).toHaveBeenCalledOnce();
});

it("protects every covered top header in narrow splits and leaves lower headers alone", () => {
  render(split(["first", "second", "third"], [0.05, 0.55, 0.4]));
  expect(header("first").style.paddingLeft).toBe("150px");
  expect(header("second").style.paddingLeft).toBe("100px");
  expect(header("third").style.paddingLeft).toBe("8px");
  render(split(["first", "second"], [0.5, 0.5], "down"));
  expect(header("first").hasAttribute("data-window-titlebar")).toBe(true);
  expect(header("second").hasAttribute("data-window-titlebar")).toBe(false);
  expect(header("second").style.paddingLeft).toBe("");
});
