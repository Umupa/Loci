// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { LibraryList, type LibraryEntry } from "./LibraryList";

let container: HTMLDivElement;
let root: Root;
const onOpen = vi.fn();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
  onOpen.mockClear();
});

const entry = (id: string, title: string): LibraryEntry => ({
  kind: "document",
  id,
  title,
  subtitle: "",
  icon: null,
  target: { kind: "document", document: { id, title } },
});

it("marks a row saved by the running turn, and says so to a screen reader", () => {
  act(() =>
    root.render(
      createElement(LibraryList, {
        entries: [entry("old", "Older source"), entry("new", "Virtio 1.2 — Virtqueues")],
        query: "",
        isCurrent: () => false,
        onOpen,
        empty: "",
        subject: "sources",
        isNew: (row) => row.id === "new",
      }),
    ),
  );
  const rows = [...container.querySelectorAll<HTMLElement>("[data-library-item]")];
  expect(rows.map((row) => row.hasAttribute("data-library-new"))).toEqual([false, true]);
  expect(rows[1].querySelector(".mentor-library-new")?.textContent).toBe("New");
  expect(rows[1].getAttribute("aria-label")).toBe(
    "document: Virtio 1.2 — Virtqueues (new)",
  );

  act(() => rows[1].click());
  expect(onOpen).toHaveBeenCalledWith({ kind: "document", document: { id: "new", title: "Virtio 1.2 — Virtqueues" } });
});
