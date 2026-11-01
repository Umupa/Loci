// @vitest-environment happy-dom
import { act, createElement, type ComponentProps, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { AGENT_TEMPLATES } from "../templates";
import { saveModelControls } from "../../settings/model/settings";
import { resetHarnessModelOverlays, setHarnessModels } from "../../sessions/model/models";
import { newSession } from "../../sessions/model/session";
import { AgentDetails } from "./AgentDetails";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const dialogOpen = vi.hoisted(() => vi.fn());
vi.mock("@tauri-apps/plugin-dialog", () => ({ open: dialogOpen, ask: vi.fn(), message: vi.fn(), save: vi.fn() }));
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

it("shows the working folder and points an existing mentor at a folder the user has", async () => {
  const { createAgent, findAgent, updateAgent } = await import("../model/agent");
  const created = createAgent([], { name: "Ada" });
  const agent = updateAgent(created.id, (current) => ({ ...current, workdir: "/home/me/Loci/ada" }))!;
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation(async (command, args) =>
    command === "agent_workdir_ensure" ? (args as { path: string }).path : original(command, args));
  props = { ...props, agent };
  await render();
  const row = [...container.querySelectorAll(".agent-setting-row")].find((item) => item.textContent?.includes("Working folder"))!;
  expect(row.textContent).toContain("Loci/ada");
  expect(row.textContent).toContain("Cloned source and experiments go here.");

  dialogOpen.mockResolvedValue("/Volumes/study/sandbox-study");
  const change = [...row.querySelectorAll("button")].find((item) => item.textContent === "Change…")!;
  await act(async () => change.click());
  expect(invoke).toHaveBeenCalledWith("agent_workdir_ensure", { path: "/Volumes/study/sandbox-study" });
  expect(findAgent(agent.id)?.workdir).toBe("/Volumes/study/sandbox-study");
  // The chat started in the home folder keeps running there until it is reset.
  expect(row.textContent).toContain("Reset conversation to start it here.");
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

it("moves between settings pages with the arrow keys and one tab stop", async () => {
  await render();
  const tabs = () => [...container.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  expect(tabs().map((tab) => tab.tabIndex)).toEqual([0, -1, -1]);
  expect(container.querySelector('[role="tabpanel"]')?.getAttribute("aria-labelledby")).toBe(tabs()[0].id);

  act(() => {
    tabs()[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
  });
  expect(tabs()[1].getAttribute("aria-selected")).toBe("true");
  expect(document.activeElement).toBe(tabs()[1]);
  expect(tabs().map((tab) => tab.tabIndex)).toEqual([-1, 0, -1]);
  expect(container.querySelector('[role="tabpanel"]')?.getAttribute("aria-labelledby")).toBe(tabs()[1].id);

  act(() => {
    tabs()[1].dispatchEvent(new KeyboardEvent("keydown", { key: "End", bubbles: true, cancelable: true }));
  });
  expect(tabs()[2].getAttribute("aria-selected")).toBe("true");
  act(() => {
    tabs()[2].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
  });
  expect(tabs()[0].getAttribute("aria-selected")).toBe("true");
  act(() => {
    tabs()[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true, cancelable: true }));
  });
  expect(tabs()[2].getAttribute("aria-selected")).toBe("true");
});

it("keeps the Soul draft and says so when the save fails", async () => {
  const original = vi.mocked(invoke).getMockImplementation()!;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "agent_load") return { id: "agent", soul: "# Soul", soulHash: "s", memory: "", memoryHash: "m", topics: [] };
    if (command === "agent_save") throw new Error("Permission denied");
    return original(command, args);
  });
  await render();
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>('[role="tab"]')].find((item) => item.textContent === "Soul")!.click());
  const field = () => container.querySelector<HTMLTextAreaElement>('textarea[aria-label="Soul"]')!;
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(field(), "# Changed soul");
    field().dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () => {
    field().focus();
    field().blur();
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("Could not save the Soul");
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("Permission denied");
  expect(field().value).toBe("# Changed soul");
});

it("replaces the Soul with a template only after the warning is confirmed", async () => {
  const original = vi.mocked(invoke).getMockImplementation()!;
  const saves: unknown[] = [];
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "agent_load") return { id: "agent", soul: "# Soul\nold rules", soulHash: "s", memory: "", memoryHash: "m", topics: [] };
    if (command === "agent_read") return { text: "# Soul\nold rules", hash: "s" };
    if (command === "agent_save") { saves.push(args); return "s2"; }
    return original(command, args);
  });
  await render();
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>('[role="tab"]')].find((item) => item.textContent === "Soul")!.click());
  const field = () => container.querySelector<HTMLTextAreaElement>('textarea[aria-label="Soul"]')!;
  const lens = AGENT_TEMPLATES.find((template) => template.id === "repo-lens")!;
  const pick = async () => {
    await act(async () => [...container.querySelectorAll("button")].find((item) => item.textContent === "Replace with template…")!.click());
    const items = [...container.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')];
    expect(items.map((item) => item.textContent)).toEqual(AGENT_TEMPLATES.map((template) => expect.stringContaining(template.name)));
    await act(async () => { items.find((item) => item.textContent?.startsWith(lens.name))!.click(); await new Promise((resolve) => setTimeout(resolve, 0)); });
  };

  vi.mocked(ask).mockResolvedValueOnce(false);
  await pick();
  expect(ask).toHaveBeenCalledWith(expect.stringContaining("can't be undone"), expect.objectContaining({ kind: "warning", okLabel: "Replace" }));
  expect(saves).toEqual([]);
  expect(field().value).toBe("# Soul\nold rules");

  vi.mocked(ask).mockResolvedValueOnce(true);
  await pick();
  expect(saves).toEqual([expect.objectContaining({ agent: "agent", text: lens.soul, expectedHash: "s" })]);
  expect(field().value).toBe(lens.soul);
});
