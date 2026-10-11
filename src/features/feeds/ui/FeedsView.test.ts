// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ContextMenuItem } from "../../../shared/ui/ContextMenu";
import type { V2exTopic } from "../model/v2ex";
import { clearFeedLists } from "./useFeedData";
import { FeedsView } from "./FeedsView";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
vi.mock("../../../app/shell/TitleBar", () => ({ OverlayNav: () => null }));
vi.mock("../../../app/shell/WindowControls", () => ({ WindowControls: () => null }));
vi.mock("../../../shared/hooks/useDragResize", () => ({ useDragResize: () => ({ setPaneRef: () => {}, dragging: false }) }));
vi.mock("../../../shared/ui/ContextMenu", () => ({
  ContextMenu: ({ items, onPick }: { items: ContextMenuItem[]; onPick: (id: string) => void }) => createElement("div", null,
    items.map((item) => item.kind === "item" ? createElement("button", { key: item.id, onClick: () => onPick(item.id) }, item.label) : null)),
}));
vi.mock("./V2exTopicDetail", () => ({
  relativeSeconds: () => "just now",
  V2exTopicDetail: ({ topic }: { topic: V2exTopic }) => createElement("div", { "data-topic-detail": true }, topic.title),
}));
vi.mock("./XFeedPane", () => ({ XFeedPane: () => createElement("div", null, "X panel") }));

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (cause: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const topic = (id: number): V2exTopic => ({
  id, title: `Topic ${id}`, url: `https://www.v2ex.com/t/${id}`, content: "body",
  replies: 0, created: 1, lastTouched: 1,
});
let container: HTMLDivElement;
let root: Root;
let requests: Map<number, ReturnType<typeof deferred<V2exTopic>>>;

function button(text: string) {
  const found = [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent?.includes(text));
  if (!found) throw new Error(`Missing button: ${text}`);
  return found;
}
const click = (element: HTMLElement) => act(async () => element.click());
const detail = () => container.querySelector("[data-topic-detail]")?.textContent;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  localStorage.setItem("loci.feeds.source", "v2ex-notifications");
  clearFeedLists();
  requests = new Map([[11, deferred<V2exTopic>()], [22, deferred<V2exTopic>()]]);
  invoke.mockReset().mockImplementation((command: string, args: { id?: number } = {}) => {
    if (command === "v2ex_status") return Promise.resolve({ connected: true, member: { username: "alice" } });
    if (command === "feeds_state_list") return Promise.resolve([]);
    if (command === "v2ex_notifications") return Promise.resolve([
      { id: 1, text: "Notification A", payload: "", created: 1, topicId: 11 },
      { id: 2, text: "Notification B", payload: "", created: 1, topicId: 22 },
    ]);
    if (command === "v2ex_topic") return requests.get(args.id!)!.promise;
    if (command === "v2ex_topics") return Promise.resolve([topic(33)]);
    return Promise.resolve();
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});
const mount = () => act(async () => root.render(createElement(FeedsView, { onClose: vi.fn() })));

describe("notification topic navigation", () => {
  it("shows the replacement account's notifications after saving its token", async () => {
    const previousInvoke = invoke.getMockImplementation()!;
    const nextAccount = deferred<{ connected: boolean; member: { username: string } }>();
    let replaced = false;
    invoke.mockImplementation((command: string, args?: { id?: number }) => {
      if (command === "v2ex_set_token") return nextAccount.promise;
      if (command === "v2ex_notifications" && replaced) return Promise.resolve([
        { id: 3, text: "Bob notification", payload: "", created: 1, topicId: 33 },
      ]);
      return previousInvoke(command, args);
    });
    await mount();
    expect(container.textContent).toContain("Notification A");
    await click(button("@alice"));
    const input = container.querySelector<HTMLInputElement>("#v2ex-token")!;
    await act(async () => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "bob-token");
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await click(button("Replace token"));
    expect(invoke).toHaveBeenCalledWith("v2ex_set_token", { token: "bob-token" });
    await act(async () => {
      replaced = true;
      nextAccount.resolve({ connected: true, member: { username: "bob" } });
    });
    expect(container.textContent).toContain("Bob notification");
    expect(container.textContent).not.toContain("Notification A");
    expect(container.textContent).toContain("@bob");
  });

  it.each(["success", "failure"] as const)("keeps the newest notification when an older request finishes with %s", async (result) => {
    await mount();
    await click(button("Notification A"));
    await click(button("Notification B"));
    await act(async () => requests.get(22)!.resolve(topic(22)));
    expect(detail()).toBe("Topic 22");
    await act(async () => {
      if (result === "success") requests.get(11)!.resolve(topic(11));
      else requests.get(11)!.reject(new Error("Old notification failed"));
    });
    expect(detail()).toBe("Topic 22");
    expect(container.textContent).not.toContain("Old notification failed");
    expect(invoke).toHaveBeenCalledWith("v2ex_topic", { id: 11 });
  });

  it("keeps a topic selected from another source when a notification arrives late", async () => {
    await mount();
    await click(button("Notification A"));
    await click(container.querySelector<HTMLButtonElement>('[aria-label="Choose list"]')!);
    await click(button("Hot"));
    await click(button("Topic 33"));
    expect(detail()).toBe("Topic 33");
    await act(async () => requests.get(11)!.resolve(topic(11)));
    expect(detail()).toBe("Topic 33");
  });

  it("does not carry a pending notification back after switching providers", async () => {
    await mount();
    await click(button("Notification A"));
    await click(container.querySelector<HTMLButtonElement>('[role="tab"]:last-child')!);
    expect(container.textContent).toContain("X panel");
    await act(async () => requests.get(11)!.resolve(topic(11)));
    await click(container.querySelector<HTMLButtonElement>('[role="tab"]:first-child')!);
    expect(detail()).toBeUndefined();
  });
});
