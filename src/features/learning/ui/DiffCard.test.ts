// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { DiffCard } from "./DiffCard";

const highlighter = vi.hoisted(() => ({ highlight: vi.fn(() => null), getThemes: () => ["github-light", "github-dark"] }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));
vi.mock("../../../platform/tauri/clipboard", () => ({ copyText: vi.fn() }));

let container: HTMLDivElement, root: Root;
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("keeps fully changed files readable without an expensive line diff or syntax highlighting", async () => {
  const before = Array.from({ length: 1500 }, (_, index) => `old line ${index}\n`).join("");
  const after = Array.from({ length: 1500 }, (_, index) => `new line ${index}\n`).join("");
  await act(async () => root.render(createElement(DiffCard, { id: "large", title: "Large change", file: "main.ts", before, after })));
  expect(container.querySelector('[role="status"]')?.textContent).toContain("full code");
  expect([...container.querySelectorAll("details pre code")].map((code) => code.textContent)).toEqual([before, after]);
  expect(container.querySelector(".diff-card__line")).toBeNull();
  expect(container.querySelector(".diff-card__stats")).toBeNull();
  expect(highlighter.highlight).not.toHaveBeenCalled();
});

it("uses the readable fallback for oversized identical files as well as costly edits", async () => {
  const code = `  ${"x".repeat(120_000)}\n\n`;
  await act(async () => root.render(createElement(DiffCard, { id: "long", title: "Long file", file: "main.ts", before: code, after: code })));
  const originals = [...container.querySelectorAll("details pre code")];
  expect(originals).toHaveLength(2);
  for (const original of originals) expect(original.textContent === code).toBe(true);
  expect(highlighter.highlight).not.toHaveBeenCalled();
});

it("bounds rendered rows even when a many-line file has no edits", async () => {
  const code = Array.from({ length: 2001 }, (_, index) => `same line ${index}\n`).join("");
  await act(async () => root.render(createElement(DiffCard, { id: "rows", title: "Many lines", file: "main.ts", before: code, after: code })));
  expect(container.querySelector(".diff-card__line")).toBeNull();
  expect(container.querySelectorAll("details pre code")).toHaveLength(2);
  expect(highlighter.highlight).not.toHaveBeenCalled();
});
