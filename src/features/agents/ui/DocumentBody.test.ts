// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { registerLearningSource } from "../../learning/model/learningStore";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { findAgent } from "../model/agent";
import { DocumentBody, findSection, shownDocument } from "./DocumentBody";
import type { FileSelection } from "../../files/hooks/useFileSelection";

const selected = vi.hoisted(() => ({ value: null as FileSelection | null, dismiss: vi.fn() }));

vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
vi.mock("../model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../learning/model/learningStore", () => ({ registerLearningSource: vi.fn() }));
vi.mock("../../sessions/model/quoteDraft", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../sessions/model/quoteDraft")>(),
  requestAddToChat: vi.fn(),
}));
vi.mock("../../files/hooks/useFileSelection", () => ({ useFileSelection: () => ({ selection: selected.value, dismiss: selected.dismiss }) }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({
  AgentMarkdown: ({ text, sourceUrl }: { text: string; sourceUrl?: string }) =>
    createElement("article", { "data-source-url": sourceUrl ?? "" }, createElement("h1", null, "Pod Lifecycle"), createElement("h2", null, "Pod  phase"), createElement("h2", null, "Container states"), text),
}));

const source = shownDocument({
  id: "k8s-pod-lifecycle", title: "Pod Lifecycle", subject: "Kubernetes", body: "Original text",
  sourceUrl: "https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/", sourceVersion: "v1.34", fetchedAt: Date.UTC(2026, 9, 10),
  createdAt: 1, updatedAt: 2,
});
let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  vi.stubGlobal("crypto", { randomUUID: () => "source-1" });
  selected.value = { text: "A Pod's phase", rect: new DOMRect(10, 20, 100, 20), range: document.createRange() };
  vi.mocked(findAgent).mockReturnValue({ sessionId: "agent-chat" } as never);
  vi.mocked(registerLearningSource).mockResolvedValue(undefined as never);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

const quoteButton = () => [...document.querySelectorAll<HTMLButtonElement>('[role="toolbar"] button')].find((button) => button.textContent?.startsWith("Quote"))!;
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

it("says where a source came from and hands its address to the text, and says nothing for the agent's own writing", async () => {
  await act(async () => root.render(createElement(DocumentBody, { document: source, agentId: "a" })));
  const line = container.querySelector("[data-document-source]")!;
  expect(line.textContent).toContain("kubernetes.io");
  expect(line.textContent).toContain("v1.34");
  expect(container.querySelector("article")?.getAttribute("data-source-url")).toBe(source.sourceUrl);
  await act(async () => root.render(createElement(DocumentBody, { document: { id: "notes", title: "Notes", body: "Mine" }, agentId: "a" })));
  expect(container.querySelector("[data-document-source]")).toBeNull();
  expect(container.querySelector("article")?.getAttribute("data-source-url")).toBe("");
});

it("puts a selected passage of a source to its agent as a quoted source, without sending anything", async () => {
  await act(async () => root.render(createElement(DocumentBody, { document: source, agentId: "a" })));
  await act(async () => quoteButton().click());
  const quoted = { id: "source-1", kind: "web", url: source.sourceUrl, title: "Pod Lifecycle", quote: "A Pod's phase" };
  expect(registerLearningSource).toHaveBeenCalledWith(quoted);
  expect(requestAddToChat).toHaveBeenCalledWith("", "plain", { sources: [quoted], targetSessionId: "agent-chat" });
});

it("quotes a selected passage of the agent's own document as plain text", async () => {
  await act(async () => root.render(createElement(DocumentBody, { document: { id: "notes", title: "Notes", body: "Mine" }, agentId: "a" })));
  await act(async () => quoteButton().click());
  expect(registerLearningSource).not.toHaveBeenCalled();
  expect(requestAddToChat).toHaveBeenCalledWith("A Pod's phase", "quote", { targetSessionId: "agent-chat" });
});

it("finds the heading a lesson starts at by its words, however it is spaced or cased", async () => {
  await act(async () => root.render(createElement(DocumentBody, { document: source, agentId: "a", section: "Pod phase" })));
  const article = container.querySelector("article")!;
  expect(findSection(article, "## pod phase")?.textContent).toBe("Pod  phase");
  expect(findSection(article, "Container")?.textContent).toBe("Container states");
  expect(findSection(article, "Probes")).toBeUndefined();
});
