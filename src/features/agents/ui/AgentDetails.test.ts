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

it("keeps model options in labelled settings rows regardless of the composer preference", async () => {
  await render();
  expect(container.querySelector('[aria-orientation="vertical"]')).not.toBeNull();
  expect(button("Effort: High")).not.toBeNull();
  expect(button("Effort: High")?.closest(".agent-setting-row")?.textContent).toContain("Effort");
  act(() => saveModelControls("beside"));
  expect(button("Effort: High")).not.toBeNull();
  act(() => saveModelControls("menu"));
  expect(button("Effort: High")).not.toBeNull();
  expect(container.querySelector('[role="menu"][aria-label="Model and settings"]')).toBeNull();
});

async function editMemoryFixture(replaced: boolean) {
  let memory = "# Memory\n- 2026-10-13 · Prefers concise answers";
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "agent_load") return { id: "agent", soul: "# Soul", soulHash: "s", memory, memoryHash: "m", topics: [] };
    if (command === "agent_read") return { text: memory, hash: "current" };
    if (command === "agent_save") { memory = (args as { text: string }).text; return "saved"; }
    return original(command, args);
  });
  await render();
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>('[role="tab"]')].find((item) => item.textContent === "Memory")!.click());
  await act(async () => button("Edit: Prefers concise answers")!.click());
  act(() => {
    const field = container.querySelector<HTMLTextAreaElement>('[aria-label="Edit memory"]')!;
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(field, "Prefers examples before explanations");
    field.dispatchEvent(new Event("input", { bubbles: true }));
  });
  memory = replaced ? "# Memory\n- 2026-10-13 · This fact was replaced" : "# Memory\n- 2026-10-13 · Uses Linux\n- 2026-10-13 · Prefers concise answers";
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent === "Save")!.click());
  return memory;
}

it("edits the same memory fact after another writer inserts a row", async () => {
  const memory = await editMemoryFixture(false);
  expect(memory).toContain("Uses Linux");
  expect(memory).toContain("Prefers examples before explanations");
  expect(memory).not.toContain("Prefers concise answers");
  expect(container.querySelector('[aria-label="Edit memory"]')).toBeNull();
});

it("retains the memory draft when another writer has replaced the original fact", async () => {
  const memory = await editMemoryFixture(true);
  expect(memory).toContain("This fact was replaced");
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("This memory changed");
  expect(container.querySelector<HTMLTextAreaElement>('[aria-label="Edit memory"]')?.value).toBe("Prefers examples before explanations");
});
