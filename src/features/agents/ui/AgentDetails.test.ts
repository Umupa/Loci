// @vitest-environment happy-dom
import { act, createElement, type ComponentProps, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { saveModelControls } from "../../settings/model/settings";
import { resetHarnessModelOverlays, setHarnessModels } from "../../sessions/model/models";
import { newSession } from "../../sessions/model/session";
import { AgentDetails } from "./AgentDetails";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../../integrations/harness/core/availability", () => ({
  getHarnessAvailabilitySnapshot: () => 0,
  hasProbedHarnessAvailability: () => true,
  isHarnessAvailable: () => true,
  harnessUnavailableHint: () => "",
  probeHarnessAvailability: async () => undefined,
  subscribeHarnessAvailability: () => () => undefined,
}));
vi.mock("../../../integrations/harness/core/registry", () => ({ refreshHarnessCatalogs: async () => undefined }));
vi.mock("../../../shared/ui/Popover", () => ({
  Popover: ({ children, role, onKeyDown, ...props }: {
    children: ReactNode;
    role?: string;
    onKeyDown?: React.KeyboardEventHandler<HTMLDivElement>;
    "aria-label"?: string;
  }) => createElement("div", { role, onKeyDown, "aria-label": props["aria-label"] }, children),
}));

let root: Root;
let container: HTMLDivElement;
let props: ComponentProps<typeof AgentDetails>;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  resetHarnessModelOverlays();
  setHarnessModels("codex", [{
    id: "codex:test", harness: "codex", name: "Test Model", nativeId: "test",
    settings: [{ id: "effort", label: "Effort", kind: "select", value: "high", options: [
      { value: "high", label: "High" }, { value: "low", label: "Low" },
    ] }],
  }]);
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "agent_load") return { soul: "# Soul", memory: "", topics: [] };
    if (command === "agent_read") return { text: "[]", hash: "habits" };
    if (command === "agent_documents_list" || command === "canvas_list") return [];
    throw new Error(`Unexpected command: ${command}`);
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  props = {
    agent: { id: "agent", name: "Ada", avatar: "ember", color: "#fff", projects: [] },
    session: { ...newSession("codex", "/home/me", "codex:test"), modelSettings: { effort: "high" } },
    recents: [], refreshKey: false, onModelChange: vi.fn(), onModelSettingsChange: vi.fn(),
    onRuntimeModeChange: vi.fn(), onPickFolders: vi.fn(async () => []),
    onReset: vi.fn(), onDelete: vi.fn(), onClose: vi.fn(),
  };
});

afterEach(() => {
  act(() => root.unmount());
  resetHarnessModelOverlays();
  container.remove();
  localStorage.clear();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

async function render() {
  await act(async () => root.render(createElement(AgentDetails, props)));
}
function button(label: string) {
  return container.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`);
}

it("uses the saved beside setting and changes the resident agent's model options", async () => {
  saveModelControls("beside");
  await render();
  const effort = button("Effort: High")!;
  expect(effort).not.toBeNull();
  expect(button("Codex Test Model")?.textContent).toBe("Test Model");
  act(() => effort.click());
  const menu = container.querySelector('[role="menu"][aria-label="Effort"]')!;
  const low = [...menu.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent === "Low")!;
  act(() => low.click());
  expect(props.onModelSettingsChange).toHaveBeenCalledWith({ effort: "low" });
  expect(props.onModelChange).not.toHaveBeenCalled();
});

it("moves model options between the menu and beside the picker when settings change", async () => {
  await render();
  const modelMenu = () => container.querySelector('[role="menu"][aria-label="Model and settings"]');
  const menuEffort = () => [...(modelMenu()?.querySelectorAll("button") ?? [])].find((item) => item.textContent?.startsWith("Effort"));
  expect(button("Effort: High")).toBeNull();
  act(() => container.querySelector<HTMLButtonElement>('button[aria-label^="Codex Test Model"]')!.click());
  expect(menuEffort()).toBeDefined();
  act(() => saveModelControls("beside"));
  expect(button("Effort: High")).not.toBeNull();
  expect(modelMenu()).toBeNull();
  act(() => saveModelControls("menu"));
  expect(button("Effort: High")).toBeNull();
  expect(menuEffort()).toBeDefined();
});
