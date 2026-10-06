// @vitest-environment happy-dom
import { act, createElement, startTransition, Suspense, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { lazySurface } from "./lazySurface";

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

function deferredSurface(label: string) {
  const component = () => createElement("main", null, label);
  let resolve!: (module: { default: typeof component }) => void;
  const pending = new Promise<{ default: typeof component }>((done) => {
    resolve = done;
  });
  const load = vi.fn(() => pending);
  const Surface = lazySurface(load, { suspense: false });
  return { Surface, load, finish: () => resolve({ default: component }) };
}

it("keeps the workspace visible during the first navigation and switches directly to the page", async () => {
  const search = deferredSurface("Search content");
  function Workspace() {
    const [open, setOpen] = useState(false);
    return createElement(
      "div",
      null,
      createElement(
        "button",
        {
          onClick: () => startTransition(() => setOpen(true)),
        },
        "Search",
      ),
      createElement("main", { hidden: open }, "Workspace content"),
      open ? createElement(search.Surface) : null,
    );
  }
  await act(async () =>
    root.render(
      createElement(
        Suspense,
        { fallback: "Blank loading frame" },
        createElement(Workspace),
      ),
    ),
  );
  await act(async () => container.querySelector("button")!.click());
  expect(search.load).toHaveBeenCalledOnce();
  expect(container.querySelector("main")!.hidden).toBe(false);
  expect(container.textContent).not.toContain("Blank loading frame");

  await act(async () => search.finish());
  expect(container.querySelector("main")!.hidden).toBe(true);
  expect(container.textContent).toContain("Search content");
  expect(container.textContent).not.toContain("Blank loading frame");
});

it("uses the most recent destination when another page is clicked before the first finishes", async () => {
  const search = deferredSurface("Search content");
  const notes = deferredSurface("Notes content");
  function Workspace() {
    const [page, setPage] = useState("workspace");
    return createElement(
      "div",
      null,
      ...["search", "notes"].map((destination) =>
        createElement(
          "button",
          {
            key: destination,
            onClick: () => startTransition(() => setPage(destination)),
          },
          destination,
        ),
      ),
      createElement(
        "main",
        { hidden: page !== "workspace" },
        "Workspace content",
      ),
      page === "search" ? createElement(search.Surface) : null,
      page === "notes" ? createElement(notes.Surface) : null,
    );
  }
  await act(async () =>
    root.render(
      createElement(
        Suspense,
        { fallback: "Blank loading frame" },
        createElement(Workspace),
      ),
    ),
  );
  const buttons = container.querySelectorAll("button");
  await act(async () => buttons[0]!.click());
  await act(async () => buttons[1]!.click());
  await act(async () => search.finish());
  expect(container.querySelector("main")!.hidden).toBe(false);
  expect(container.textContent).not.toContain("Search content");

  await act(async () => notes.finish());
  expect(container.textContent).toContain("Notes content");
  expect(container.textContent).not.toContain("Search content");
  expect(container.textContent).not.toContain("Blank loading frame");
});

it("shares one import between warmup and the first render", async () => {
  const search = deferredSurface("Search content");
  expect(search.load).not.toHaveBeenCalled();
  const first = search.Surface.preload();
  const second = search.Surface.preload();
  expect(first).toBe(second);
  search.finish();
  await first;
  await act(async () =>
    root.render(
      createElement(Suspense, { fallback: null }, createElement(search.Surface)),
    ),
  );
  expect(search.load).toHaveBeenCalledOnce();
  expect(container.textContent).toBe("Search content");
});

it("retries a failed warmup when the page is opened", async () => {
  const component = () => createElement("main", null, "Search content");
  const load = vi
    .fn()
    .mockRejectedValueOnce(new Error("Warmup failed"))
    .mockResolvedValue({ default: component });
  const Surface = lazySurface(load);
  await expect(Surface.preload()).rejects.toThrow("Warmup failed");
  await act(async () => root.render(createElement(Surface)));
  expect(load).toHaveBeenCalledTimes(2);
  expect(container.textContent).toBe("Search content");
});
