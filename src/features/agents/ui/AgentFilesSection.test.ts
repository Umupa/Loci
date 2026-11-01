// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => invoke(...args) }));
vi.mock("../../files/ui/FileTree", () => ({
  FileTree: ({ cwd, onOpenFile, query, empty }: { cwd: string; onOpenFile: (path: string) => void; query?: string; empty?: string }) =>
    createElement("button", { "data-tree": cwd, "data-query": query ?? "", "data-empty": empty ?? "", onClick: () => onOpenFile(`${cwd}/README.md`) }, `tree ${cwd}`),
}));

import { createAgent } from "../model/agent";
import { AgentFilesSection } from "./AgentFilesSection";

let root: Root;
let host: HTMLDivElement;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  invoke.mockReset();
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
});

async function settle() {
  for (let i = 0; i < 5; i++) await act(async () => { await Promise.resolve(); });
}

it("lists the mentor's workdir and opens its files through the callback", async () => {
  const agent = createAgent(["/code/old-project"], { name: "Lens" });
  invoke.mockImplementation(async (command: string, args: { slug?: string; path?: string }) =>
    command === "agent_workdir_create" ? `/home/me/Loci/${args.slug}` : args.path);
  const onOpenFile = vi.fn();
  act(() => root.render(createElement(AgentFilesSection, { agentId: agent.id, onOpenFile, filter: "read" })));
  await settle();
  const tree = host.querySelector<HTMLButtonElement>('[data-tree="/home/me/Loci/lens"]');
  expect(tree).not.toBeNull();
  // The library's filter reaches the working folder's tree.
  expect(tree!.dataset.query).toBe("read");
  // An empty folder says what to do, in the mentor's name.
  expect(tree!.dataset.empty).toContain("ask Lens to write one");
  act(() => tree!.click());
  expect(onOpenFile).toHaveBeenCalledWith("/home/me/Loci/lens/README.md");

  // Other folders stay folded until opened.
  expect(host.textContent).toContain("Other folders");
  expect(host.querySelector('[data-tree="/code/old-project"]')).toBeNull();
  const fold = host.querySelector<HTMLButtonElement>('button[aria-expanded="false"]')!;
  expect(fold.textContent).toContain("old-project");
  act(() => fold.click());
  // The same filter reaches every folder, which then keeps its own search field away.
  expect(host.querySelector<HTMLButtonElement>('[data-tree="/code/old-project"]')!.dataset.query).toBe("read");
});

it("says so when the working folder cannot be opened", async () => {
  const agent = createAgent();
  invoke.mockRejectedValue("Permission denied");
  act(() => root.render(createElement(AgentFilesSection, { agentId: agent.id, onOpenFile: vi.fn() })));
  await settle();
  expect(host.querySelector('[role="alert"]')?.textContent).toContain("Permission denied");
});
