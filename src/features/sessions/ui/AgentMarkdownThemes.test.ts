// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { setTheme } from "../../settings/model/appearance";
import { buildCodeTheme, findTheme } from "../../settings/model/themes";
import { AgentMarkdown } from "./AgentMarkdown";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async () => undefined),
  convertFileSrc: (path: string) => path,
}));

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const values = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  document.documentElement.removeAttribute("style");
  document.documentElement.className = "";
  delete document.documentElement.dataset.theme;
  vi.unstubAllGlobals();
});

it("recolors an already mounted code block across dark, light and default themes", async () => {
  await act(async () => {
    setTheme("tokyo-night");
    root.render(createElement(AgentMarkdown, {
      text: "```typescript\nconst answer = 42;\n```",
      cwd: "/repo",
    }));
  });
  const codeStyles = () => Array.from(container.querySelectorAll("code [style]"))
    .map((node) => node.getAttribute("style")).join(" ").toLowerCase();
  const waitForColors = async (expected: string) => {
    await act(async () => {
      await vi.waitFor(() => expect(codeStyles()).toContain(expected), { timeout: 5000 });
    });
  };
  const dark = buildCodeTheme(findTheme("tokyo-night")!);
  await waitForColors(dark.fg!.toLowerCase());
  await act(async () => { setTheme("rose-pine"); });
  const light = buildCodeTheme(findTheme("rose-pine")!);
  await waitForColors(light.fg!.toLowerCase());
  expect(codeStyles()).not.toContain(dark.fg!.toLowerCase());
  await act(async () => { setTheme(null); });
  await waitForColors("#24292e");
  expect(codeStyles()).not.toContain(light.fg!.toLowerCase());
  expect(container.querySelector("code")?.textContent).toContain("const answer = 42;");
});
