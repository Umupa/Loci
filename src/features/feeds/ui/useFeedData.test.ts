// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { V2exListSource, V2exNotification, V2exTopic } from "../model/v2ex";
import { clearFeedLists, useV2exNotifications, useV2exTopics } from "./useFeedData";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));

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
const notification = (id: number): V2exNotification => ({ id, text: `Account notification ${id}`, payload: "", created: 1 });
let container: HTMLDivElement;
let root: Root;
let topics: ReturnType<typeof useV2exTopics>;
let notifications: ReturnType<typeof useV2exNotifications>;

function Topics({ source }: { source: V2exListSource }) {
  topics = useV2exTopics(source, source.kind, false);
  return createElement("div", null, topics.items.map((item) => item.title).join(","));
}
function Notifications() {
  notifications = useV2exNotifications(true);
  return createElement("div", null, notifications.items.map((item) => item.text).join(","));
}
const renderTopics = (source: V2exListSource) => act(async () => root.render(createElement(Topics, { source })));

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  clearFeedLists();
  invoke.mockReset();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

describe("feed list request ownership", () => {
  it.each(["success", "failure"] as const)("keeps a fresh cached list when the previous refresh finishes with %s", async (result) => {
    invoke.mockResolvedValueOnce([topic(1)]).mockResolvedValueOnce([topic(2)]);
    await renderTopics({ kind: "hot" });
    await renderTopics({ kind: "latest" });
    expect(container.textContent).toBe("Topic 2");
    await renderTopics({ kind: "hot" });
    const oldRefresh = deferred<V2exTopic[]>();
    invoke.mockReturnValueOnce(oldRefresh.promise);
    await act(async () => topics.refresh());
    expect(topics.loading).toBe(true);
    await renderTopics({ kind: "latest" });
    expect(container.textContent).toBe("Topic 2");
    await act(async () => {
      if (result === "success") oldRefresh.resolve([topic(99)]);
      else oldRefresh.reject(new Error("Old Hot request failed"));
    });
    expect(container.textContent).toBe("Topic 2");
    expect(topics.error).toBeNull();
    expect(topics.loading).toBe(false);
    expect(invoke).toHaveBeenCalledTimes(3);
  });

  it("drops old account notifications immediately and reloads an enabled list after cache invalidation", async () => {
    const nextAccount = deferred<V2exNotification[]>();
    invoke.mockResolvedValueOnce([notification(1)]).mockReturnValueOnce(nextAccount.promise);
    await act(async () => root.render(createElement(Notifications)));
    expect(container.textContent).toBe("Account notification 1");
    await act(async () => clearFeedLists());
    expect(container.textContent).toBe("");
    expect(notifications.loading).toBe(true);
    await act(async () => nextAccount.resolve([notification(2)]));
    expect(container.textContent).toBe("Account notification 2");
    expect(invoke).toHaveBeenCalledTimes(2);
  });

  it("does not repopulate an invalidated account cache from a pending old response", async () => {
    const oldAccount = deferred<V2exNotification[]>();
    const nextAccount = deferred<V2exNotification[]>();
    invoke.mockReturnValueOnce(oldAccount.promise).mockReturnValueOnce(nextAccount.promise);
    await act(async () => root.render(createElement(Notifications)));
    await act(async () => clearFeedLists());
    await act(async () => oldAccount.resolve([notification(1)]));
    expect(container.textContent).toBe("");
    await act(async () => nextAccount.resolve([notification(2)]));
    expect(container.textContent).toBe("Account notification 2");
    await act(async () => root.render(null));
    await act(async () => root.render(createElement(Notifications)));
    expect(container.textContent).toBe("Account notification 2");
    expect(invoke).toHaveBeenCalledTimes(2);
  });
});
