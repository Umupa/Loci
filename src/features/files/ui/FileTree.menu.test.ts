// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const fs = vi.hoisted(() => ({
  listDir: vi.fn(),
  listProjectFiles: vi.fn(),
  revealPath: vi.fn(async () => undefined),
}));
vi.mock("@tauri-apps/api/webview", () => ({ getCurrentWebview: () => ({ onDragDropEvent: async () => () => {} }) }));
vi.mock("../../../platform/tauri/fs", async (original) => ({ ...(await original<object>()), ...fs }));

import { FileTree, folderMenuItems } from "./FileTree";

let root: Root;
let host: HTMLDivElement;
const entries = [
  { name: "repos", path: "/w/repos", isDir: true, hidden: false },
  { name: "notes.md", path: "/w/notes.md", isDir: false, hidden: false },
  { name: ".env", path: "/w/.env", isDir: false, hidden: true },
];

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  fs.listDir.mockReset().mockImplementation(async (path: string) =>
    path === "/w/repos"
      ? [{ name: "main.c", path: "/w/repos/main.c", isDir: false, hidden: false }]
      : entries);
  fs.listProjectFiles.mockReset().mockResolvedValue([
    { name: "repos", path: "/w/repos", relative: "repos", isDir: true },
    { name: "notes.md", path: "/w/notes.md", relative: "notes.md" },
    { name: "main.c", path: "/w/repos/main.c", relative: "repos/main.c" },
  ]);
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.unstubAllGlobals(); });

async function settle() { for (let i = 0; i < 6; i++) await act(async () => { await Promise.resolve(); }); }
const menuItems = () => [...document.querySelectorAll('[role="menu"] [role^="menuitem"]')];

it("offers the folder's actions from one button, and shows only the first level", async () => {
  await act(async () => root.render(createElement(FileTree, { cwd: "/w", onOpenFile: vi.fn(), header: createElement("p", null, "~/w") })));
  await settle();
  const buttons = [...host.querySelectorAll("button")].filter((button) => !button.closest('[role="tree"]'));
  expect(buttons.map((button) => button.getAttribute("aria-label"))).toEqual(["File actions"]);
  expect(host.textContent).toContain("~/w");
  expect(host.querySelector('input[aria-label="Search files by name or path"]')).not.toBeNull();
  expect(host.textContent).toContain("repos");
  expect(host.textContent).not.toContain(".env");
  expect(host.querySelector('[role="tree"] [aria-expanded="true"]')).toBeNull();

  await act(async () => buttons[0].click());
  expect(menuItems().map((item) => item.textContent)).toEqual(expect.arrayContaining([
    expect.stringContaining("New File"), expect.stringContaining("New Folder"), expect.stringContaining("Import Files"),
    expect.stringContaining("Refresh"), expect.stringContaining("Collapse All"), expect.stringContaining("Show Hidden Files"),
  ]));
  expect(menuItems()).toHaveLength(folderMenuItems(false).filter((item) => item.kind === "item").length);
  const hidden = menuItems().find((item) => item.textContent?.includes("Show Hidden Files")) as HTMLElement;
  expect(hidden.getAttribute("aria-checked")).toBe("false");
  await act(async () => hidden.click());
  await settle();
  expect(localStorage.getItem("loci.files.showHidden")).toBe("1");
  expect(host.textContent).toContain(".env");

  await act(async () => buttons[0].click());
  const reveal = menuItems().at(-1) as HTMLElement;
  await act(async () => reveal.click());
  await settle();
  expect(fs.revealPath).toHaveBeenCalledWith("/w");
});

it("filters with a query from outside, without a search field of its own", async () => {
  await act(async () => root.render(createElement(FileTree, { cwd: "/w", onOpenFile: vi.fn(), query: "main" })));
  await settle();
  expect(host.querySelector('input[aria-label="Search files by name or path"]')).toBeNull();
  expect(host.textContent).toContain("main.c");
  expect(host.querySelector('[role="tree"]')).toBeNull();
});

it("asks the outside filter to clear when a folder match is chosen, then shows the folder", async () => {
  const onClearQuery = vi.fn();
  const tree = (query: string) => createElement(FileTree, { cwd: "/w", onOpenFile: vi.fn(), query, onClearQuery });
  await act(async () => root.render(tree("repos")));
  await settle();
  const folder = [...host.querySelectorAll<HTMLButtonElement>('[role="option"]')].find((row) => row.textContent?.includes("repos"))!;
  expect(folder.hasAttribute("data-library-item")).toBe(true);
  await act(async () => folder.click());
  expect(onClearQuery).toHaveBeenCalledOnce();
  // With the filter cleared, the chosen folder is open in the tree.
  await act(async () => root.render(tree("")));
  await settle();
  expect(host.querySelector('[role="treeitem"][title="/w/repos"]')?.getAttribute("aria-expanded")).toBe("true");
});
