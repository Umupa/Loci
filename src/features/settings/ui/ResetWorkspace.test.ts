// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ResetWorkspace } from "./ResetWorkspace";
const { ask, invoke } = vi.hoisted(() => ({ ask: vi.fn(), invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask }));
let root: Root;
let container: HTMLDivElement;
beforeEach(async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  localStorage.setItem("loci.language", "en");
  ask.mockReset().mockResolvedValue(true);
  invoke.mockReset().mockResolvedValue(undefined);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  await act(async () => root.render(createElement(ResetWorkspace)));
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});
const click = () => act(async () => container.querySelector("button")!.click());
it("requires destructive confirmation before invoking the backend", async () => {
  expect(invoke).not.toHaveBeenCalled();
  await click();
  expect(ask).toHaveBeenCalledWith(expect.stringContaining("This cannot be undone"), expect.objectContaining({ kind: "warning", cancelLabel: "Cancel", okLabel: "Reset workspace" }));
  expect(ask.mock.calls[0][0]).toContain("All settings, provider accounts and global backgrounds are kept");
  expect(invoke).toHaveBeenCalledExactlyOnceWith("workspace_reset");
});
it("does nothing when confirmation is canceled", async () => {
  ask.mockResolvedValue(false);
  await click();
  expect(invoke).not.toHaveBeenCalled();
});
it("prevents repeated clicks while the dialog is open", async () => {
  let confirm!: (value: boolean) => void;
  ask.mockReturnValue(new Promise((resolve) => { confirm = resolve; }));
  await click();
  await click();
  expect(ask).toHaveBeenCalledTimes(1);
  expect(container.querySelector("button")!.disabled).toBe(true);
  await act(async () => confirm(true));
  expect(invoke).toHaveBeenCalledTimes(1);
});
it("surfaces command failure and leaves local data alone", async () => {
  localStorage.setItem("loci.recentProjects", "original");
  invoke.mockRejectedValue(new Error("disk denied"));
  await click();
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("disk denied");
  expect(localStorage.getItem("loci.recentProjects")).toBe("original");
  expect(container.querySelector("button")!.disabled).toBe(false);
});
