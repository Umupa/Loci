// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { requestOpenAppResource } from "../../../shared/lib/appResourceLinks";
import { invalidateCanvases, type Canvas } from "../../canvas/canvas";
import { openDocument } from "../../sessions/model/cards";
import { resetHarnessModelOverlays, setHarnessModels } from "../../sessions/model/models";
import { newSession } from "../../sessions/model/session";
import { agentCanvasScope } from "../model/agent";
import type { StoredDocument } from "../model/agentDocuments";
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
vi.mock("../../../integrations/harness/core/registry", () => ({
  refreshHarnessCatalogs: async () => undefined,
}));
vi.mock("../../../shared/lib/appResourceLinks", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../../shared/lib/appResourceLinks")>(),
  requestOpenAppResource: vi.fn(),
}));
vi.mock("../../sessions/model/cards", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../sessions/model/cards")>(),
  openDocument: vi.fn(),
}));
let host: HTMLDivElement;
let root: Root;
let props: ComponentProps<typeof AgentDetails>;
let documents: StoredDocument[];
let canvases: Canvas[];
let loadDocuments: () => Promise<StoredDocument[]>;
let loadCanvases: () => Promise<Canvas[]>;

const at = (day: number) => Date.UTC(2026, 9, day, 12);
const documentEntry: StoredDocument = {
  id: "shared", title: "HTTP cache primer", subject: "Networking",
  createdAt: at(1), updatedAt: at(7),
};
const canvas: Canvas = {
  id: "shared", title: "Cache map", dataJson: "{}", tags: [],
  cwd: agentCanvasScope("agent"), createdAt: at(1), updatedAt: at(8),
};
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  invalidateCanvases();
  resetHarnessModelOverlays();
  setHarnessModels("codex", [{
    id: "codex:test", harness: "codex", name: "Test Model", nativeId: "test",
  }]);
  documents = [];
  canvases = [];
  loadDocuments = async () => documents;
  loadCanvases = async () => canvases;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "agent_load") return { soul: "# Soul", memory: "", topics: [] };
    if (command === "agent_read") return { text: "[]", hash: "habits" };
    if (command === "agent_documents_list") return loadDocuments();
    if (command === "canvas_list") return loadCanvases();
    if (command === "agent_documents_get") {
      const id = (args as { id?: string }).id;
      const found = documents.find((entry) => entry.id === id);
      return found ? { ...found, body: "# HTTP cache primer\n\nA saved explanation." } : null;
    }
    throw new Error(`Unexpected command: ${command}`);
  });
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  props = {
    agent: { id: "agent", name: "Ada", avatar: "ember", color: "#fff", projects: [] },
    session: newSession("codex", "/home/me", "codex:test"),
    recents: [], refreshKey: false, onModelChange: vi.fn(), onModelSettingsChange: vi.fn(),
    onRuntimeModeChange: vi.fn(), onPickFolders: vi.fn(async () => []),
    onReset: vi.fn(), onDelete: vi.fn(), onClose: vi.fn(),
  };
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  invalidateCanvases();
  resetHarnessModelOverlays();
  localStorage.clear();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

async function render() {
  await act(async () => root.render(createElement(AgentDetails, props)));
}

function libraryButton() {
  return [...host.querySelectorAll<HTMLButtonElement>("button")].find((button) =>
    [...button.querySelectorAll("span")].some((span) => span.textContent === "Library"),
  )!;
}

async function openLibrary() {
  await act(async () => libraryButton().click());
}

function library() {
  return host.querySelector<HTMLElement>("[data-agent-library]")!;
}

function rows() {
  return [...library().querySelectorAll<HTMLButtonElement>("[data-library-kind]")];
}

function row(kind: "document" | "canvas") {
  return library().querySelector<HTMLButtonElement>(`[data-library-kind="${kind}"][data-library-id="shared"]`)!;
}

function mixedItems() {
  documents = [
    { id: "older", title: "Earlier reading", createdAt: at(1), updatedAt: at(2) },
    documentEntry,
  ];
  canvases = [
    canvas,
    { ...canvas, id: "other-agent", title: "Another agent's drawing", cwd: agentCanvasScope("other"), updatedAt: at(10) },
  ];
}

it("shows one newest-first list containing only titles, with metadata in native tooltips", async () => {
  mixedItems();
  await render();
  await openLibrary();
  expect(rows().map((entry) => [entry.dataset.libraryKind, entry.dataset.libraryId, entry.textContent])).toEqual([
    ["canvas", "shared", "Cache map"],
    ["document", "shared", "HTTP cache primer"],
    ["document", "older", "Earlier reading"],
  ]);
  expect(library().textContent).toBe("Cache mapHTTP cache primerEarlier reading");
  expect(host.querySelectorAll("h3")).toHaveLength(0);
  expect(host.textContent).not.toContain("Another agent's drawing");
  const date = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" });
  for (const [kind, updatedAt] of [["document", documentEntry.updatedAt], ["canvas", canvas.updatedAt]] as const) {
    expect(row(kind).title).toContain(date.format(updatedAt));
    expect(row(kind).title).toMatch(new RegExp(kind, "i"));
    const icon = row(kind).querySelector("svg");
    expect(icon).not.toBeNull();
    expect(icon?.closest('[aria-hidden="true"]')).not.toBeNull();
  }
  expect(row("document").title).toContain("Networking");
});

it("opens each kind through its existing reader with the correct agent or source session", async () => {
  mixedItems();
  await render();
  await openLibrary();
  await act(async () => row("document").click());
  expect(invoke).toHaveBeenCalledWith("agent_documents_get", { agent: "agent", id: "shared" });
  expect(openDocument).toHaveBeenCalledWith({
    id: "shared", title: "HTTP cache primer", subject: "Networking",
    body: "# HTTP cache primer\n\nA saved explanation.",
  }, "agent");
  await act(async () => row("canvas").click());
  expect(props.onClose).toHaveBeenCalled();
  expect(requestOpenAppResource).toHaveBeenCalledWith({ kind: "canvas", id: "shared" });
  expect(vi.mocked(props.onClose).mock.invocationCallOrder[0]).toBeLessThan(vi.mocked(requestOpenAppResource).mock.invocationCallOrder[0]);
});

it("distinguishes pending and failed sources from an empty library and retries the failed listing", async () => {
  let reject!: (reason: Error) => void;
  const pending = new Promise<StoredDocument[]>((_, fail) => { reject = fail; });
  loadDocuments = () => pending;
  await render();
  await openLibrary();
  expect(host.textContent).toContain("Loading library…");
  expect(host.textContent).not.toContain("Nothing saved yet.");
  await act(async () => reject(new Error("Listing unavailable")));
  expect(host.textContent).toContain("Some items could not be loaded.");
  expect(host.textContent).not.toContain("Nothing saved yet.");
  documents = [documentEntry];
  loadDocuments = async () => documents;
  const retry = [...host.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Retry")!;
  expect(retry).not.toBeUndefined();
  await act(async () => retry.click());
  expect(rows().map((entry) => entry.textContent)).toEqual(["HTTP cache primer"]);
  expect(host.textContent).not.toContain("Some items could not be loaded.");
  expect(host.textContent).not.toContain("Nothing saved yet.");
});

it("retains saved items from a successful source when another source fails", async () => {
  canvases = [canvas];
  loadDocuments = async () => { throw new Error("Documents unavailable"); };
  await render();
  await openLibrary();
  expect(rows().map((entry) => entry.textContent)).toEqual(["Cache map"]);
  expect(host.textContent).toContain("Some items could not be loaded.");
  expect(host.textContent).not.toContain("Nothing saved yet.");
  expect(host.textContent).not.toContain("Loading library…");
});

it("shows one empty message after both sources have loaded", async () => {
  await render();
  await openLibrary();
  expect(rows()).toHaveLength(0);
  expect(library().textContent).toBe("Nothing saved yet.");
  expect(host.textContent?.match(/Nothing saved yet\./g)).toHaveLength(1);
  expect(host.textContent).not.toContain("Loading library…");
  expect(host.textContent).not.toContain("Some items could not be loaded.");
});
