// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { NOTES_CHANGED_EVENT, upsertNote } from "../../notes";
import { saveAgentDocuments, type StoredDocument } from "../model/agentDocuments";
import { AgentDocumentReader } from "./AgentDocumentReader";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../notes", () => ({ NOTES_CHANGED_EVENT: "notes-changed", upsertNote: vi.fn() }));
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
const pointerDown = (element: Element) => act(() => element.dispatchEvent(new Event("pointerdown", { bubbles: true })));

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
  const changed = vi.fn();
  window.addEventListener(NOTES_CHANGED_EVENT, changed);
  try {
    await render();
    await act(async () => button("Save as a note").click());
    expect(upsertNote).toHaveBeenCalledWith({ id: expect.any(String), title: reading.title, body: reading.body, tags: [reading.subject] });
    expect(changed).toHaveBeenCalledOnce();
    expect(button("Save as a note").disabled).toBe(true);
    expect(invoke).not.toHaveBeenCalled();
    expect(button("Remove from the library")).toBeNull();
  } finally {
    window.removeEventListener(NOTES_CHANGED_EVENT, changed);
  }
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
  expect(upsertNote).toHaveBeenCalledWith(expect.objectContaining({ title: "Revised network", body: "Revised strategy" }));
  await act(async () => button("Remove from the library").click());
  expect(invoke).toHaveBeenCalledWith("agent_documents_delete", { agent: "agent-a", id: "network" });
  expect(library.has("agent-a:network")).toBe(false);
  expect(library.has("agent-b:network")).toBe(true);
  expect(props.onClose).toHaveBeenCalledOnce();
});

it("resets its saved state when switched to another document", async () => {
  await render();
  await act(async () => button("Save as a note").click());
  props = { ...props, document: { id: "ingress", title: "Ingress", body: "Incoming traffic" } };
  await render();
  expect(container.querySelector("article")?.textContent).toBe("Incoming traffic");
  expect(button("Save as a note").disabled).toBe(false);
});
