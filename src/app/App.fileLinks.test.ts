// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { clearMocks, mockConvertFileSrc, mockIPC, mockWindows } from "@tauri-apps/api/mocks";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import App from "./App";
import { newSession } from "../features/sessions/model/session";
import { newTab } from "../features/workspace/model/layout";
import * as filePlace from "../features/files/model/filePlace";

// Model discovery is unrelated to reading a saved reply and needs signed-in CLIs.
vi.mock("../integrations/harness/core/registry", async (original) => ({
  ...(await original<typeof import("../integrations/harness/core/registry")>()),
  refreshHarnessCatalogs: vi.fn(),
}));
vi.mock("./model/preloadNavigation", () => ({ preloadNavigationWhenIdle: () => () => undefined }));

let root: Root;
let container: HTMLDivElement;
const externalOpen = vi.fn();
const requestPlace = vi.spyOn(filePlace, "requestFilePlace");

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  externalOpen.mockClear();
  requestPlace.mockClear();
  mockWindows("main");
  mockConvertFileSrc("macos");
  mockIPC((command, args) => {
    if (command === "open_path_with_default_app") return externalOpen(args);
    if (command === "read_text_file") return "# Container processes\n\nA container starts a process.";
    if (command === "stat_files") return [];
    if (["canvas_list", "session_list", "session_list_by_project", "list_directory", "skills_list", "list_fonts"].includes(command)) return [];
    if (command === "resolve_project_location") return { path: "/repo", identity: "fixture" };
    if (command.startsWith("plugin:window|") || ["set_dock_badge", "keybindings_set_overrides"].includes(command)) return;
    throw new Error(`Unexpected test IPC: ${command}`);
  }, { shouldMockEvents: true });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => {
    root.unmount();
    // The shared process bridge releases its native listeners on the next tick.
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
  container.remove();
  clearMocks();
  vi.unstubAllGlobals();
});

it("opens a project reading beside the conversation through the real app wiring", async () => {
  const session = {
    ...newSession("antigravity", "/repo"),
    blocks: [{ id: "reading", role: "assistant" as const, text: "请打开 [container-process.md](sources/container-process.md#L1-L3) 研读。\n\n[项目外文件](/outside/notes.md#L20)" }],
  };
  const tab = newTab(session.id);
  await act(async () => root.render(createElement(App, {
    resumed: { sessions: [session], tabs: [tab], activeTabId: tab.id, projectCwd: "/repo", projectReturnMemory: new Map() },
    history: [], historyCwd: "/repo",
  })));
  const link = container.querySelector<HTMLAnchorElement>('a[href^="/repo/sources/container-process.md"]');
  expect(link).not.toBeNull();
  await act(async () => link!.click());
  await vi.waitFor(async () => {
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
    expect(container.querySelector(".markdown-preview h1")?.textContent).toBe("Container processes");
  });
  expect(container.textContent).toContain("请打开");
  expect(externalOpen).not.toHaveBeenCalled();
  expect(requestPlace).toHaveBeenCalledExactlyOnceWith("/repo/sources/container-process.md", { lines: [1, 3] });
  const preview = container.querySelector(".markdown-preview h1");
  await act(async () => link!.click());
  expect(container.querySelectorAll(".markdown-preview h1")).toHaveLength(1);
  expect(container.querySelector(".markdown-preview h1")).toBe(preview);
  requestPlace.mockClear();
  // The existing policy for paths outside this project remains explicit and testable.
  await act(async () => container.querySelector<HTMLAnchorElement>('a[href="/outside/notes.md:20"]')!.click());
  expect(externalOpen).toHaveBeenCalledExactlyOnceWith({ path: "/outside/notes.md" });
  expect(requestPlace).not.toHaveBeenCalled();
});
