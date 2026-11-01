// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { copyMessage } from "../../../platform/tauri/clipboard";
import { invoke } from "@tauri-apps/api/core";
import { upsertNote } from "../../notes";
import { saveAgentDocuments, type StoredDocument } from "../model/agentDocuments";
import { AgentDocumentReader } from "./AgentDocumentReader";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../../platform/tauri/clipboard", () => ({ copyMessage: vi.fn(async () => undefined) }));
vi.mock("../../notes", () => ({ upsertNote: vi.fn() }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("article", null, text) }));

const reading = { id: "network", title: "Network strategy", subject: "Sandbox", body: "Original strategy" };
const library = new Map<string, StoredDocument>();
let container: HTMLDivElement;
let root: Root;
let props: ComponentProps<typeof AgentDocumentReader>;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  library.clear();
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { agent: string; id?: string; document?: typeof reading };
    if (command === "agent_documents_get") return library.get(`${input.agent}:${input.id}`) ?? null;
    if (command === "agent_documents_upsert") {
      library.set(`${input.agent}:${input.document!.id}`, { ...input.document!, createdAt: 1, updatedAt: 2 });
      return;
    }
    if (command === "agent_documents_delete") {
      library.delete(`${input.agent}:${input.id}`);
      return;
    }
    throw new Error(`Unexpected command: ${command}`);
  });
  vi.mocked(upsertNote).mockResolvedValue(undefined as never);
  vi.stubGlobal("confirm", vi.fn(() => true));
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  props = { document: reading, focused: false, onFocus: vi.fn(), onClose: vi.fn(), onPaneDragStart: vi.fn() };
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

const render = async () => { await act(async () => root.render(createElement(AgentDocumentReader, props))); };
const button = (label: string) => container.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`)!;
const pointerDown = (element: Element) => act(() => element.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, button: 0 })));

it("focuses the document and starts a pane drag from its title bar", async () => {
  await render();
  pointerDown(container.querySelector("h2")!);
  expect(props.onFocus).toHaveBeenCalledOnce();
  expect(props.onPaneDragStart).toHaveBeenCalledOnce();
  pointerDown(container.querySelector("article")!);
  expect(props.onPaneDragStart).toHaveBeenCalledOnce();
  props = { ...props, focused: true };
  await render();
  pointerDown(container.querySelector("article")!);
  expect(props.onFocus).toHaveBeenCalledTimes(2);
});

it("keeps title bar actions out of pane dragging", async () => {
  await render();
  pointerDown(button("Save as a note").querySelector("svg")!);
  pointerDown(button("Close the document"));
  expect(props.onPaneDragStart).not.toHaveBeenCalled();
  act(() => button("Close the document").click());
  expect(props.onClose).toHaveBeenCalledOnce();
});

it("saves a standalone document as a note without looking up an agent library", async () => {
  await render();
  await act(async () => button("Save as a note").click());
  expect(upsertNote).toHaveBeenCalledWith({ id: expect.any(String), title: reading.title, body: reading.body, tags: [reading.subject] });
  expect(button("Save as a note").disabled).toBe(true);
  expect(invoke).not.toHaveBeenCalled();
  expect(button("Remove from the library")).toBeNull();
});

it("follows revisions from its own library and saves the revised document", async () => {
  library.set("agent-a:network", { ...reading, body: "Stored strategy", createdAt: 1, updatedAt: 1 });
  library.set("agent-b:network", { ...reading, body: "Other agent's strategy", createdAt: 1, updatedAt: 1 });
  props = { ...props, agentId: "agent-a" };
  await render();
  expect(container.querySelector("article")?.textContent).toBe("Stored strategy");
  await act(async () => saveAgentDocuments("agent-a", [{ ...reading, title: "Revised network", body: "Revised strategy" }]));
  expect(container.querySelector("article")?.textContent).toBe("Revised strategy");
  expect(container.querySelector("h2")?.textContent).toBe("Revised network");
  await act(async () => button("Save as a note").click());
  expect(upsertNote).toHaveBeenCalledWith(expect.objectContaining({ title: "Revised network", body: "Revised strategy", agentId: "agent-a" }));
  await act(async () => button("Remove from the library").click());
  expect(invoke).toHaveBeenCalledWith("agent_documents_delete", { agent: "agent-a", id: "network" });
  expect(library.has("agent-a:network")).toBe(false);
  expect(library.has("agent-b:network")).toBe(true);
  expect(props.onClose).toHaveBeenCalledOnce();
});

it("keeps a library document when removing it is declined", async () => {
  library.set("agent-a:network", { ...reading, createdAt: 1, updatedAt: 1 });
  const confirm = vi.mocked(window.confirm);
  confirm.mockReturnValueOnce(false);
  props = { ...props, agentId: "agent-a" };
  await render();
  await act(async () => button("Remove from the library").click());
  expect(confirm).toHaveBeenCalledWith(expect.stringContaining("Network strategy"));
  expect(invoke).not.toHaveBeenCalledWith("agent_documents_delete", expect.anything());
  expect(library.has("agent-a:network")).toBe(true);
  expect(props.onClose).not.toHaveBeenCalled();
});

it("resets its saved state when switched to another document", async () => {
  await render();
  await act(async () => button("Save as a note").click());
  props = { ...props, document: { id: "ingress", title: "Ingress", body: "Incoming traffic" } };
  await render();
  expect(container.querySelector("article")?.textContent).toBe("Incoming traffic");
  expect(button("Save as a note").disabled).toBe(false);
});


it("keeps overview navigation compact and exposes save-as-note through document actions", async () => {
  library.set("agent-a:network", { ...reading, createdAt: 1, updatedAt: 1 });
  props = { ...props, agentId: "agent-a", onBack: vi.fn(), onExpand: vi.fn() };
  await render();
  expect(container.querySelector("[data-resource-header]")).not.toBeNull();
  expect(button("Save as a note")).toBeNull();
  await act(async () => button("Document actions").click());
  const save = [...document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')].find((item) => item.textContent === "Save as a note")!;
  expect(save).toBeDefined();
  await act(async () => save.click());
  expect(upsertNote).toHaveBeenCalledWith(expect.objectContaining({ agentId: "agent-a", body: reading.body }));
  expect(props.onBack).not.toHaveBeenCalled();
});


it("keeps the reader visible when copying fails", async () => {
  library.set("agent-a:network", { ...reading, createdAt: 1, updatedAt: 1 });
  props = { ...props, agentId: "agent-a", onBack: vi.fn() };
  vi.mocked(copyMessage).mockRejectedValueOnce(new Error("Clipboard unavailable"));
  await render();
  await act(async () => button("Document actions").click());
  await act(async () => [...document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')].find((item) => item.textContent === "Copy document")!.click());
  expect(container.querySelector("article")?.textContent).toBe(reading.body);
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("Clipboard unavailable");
});
