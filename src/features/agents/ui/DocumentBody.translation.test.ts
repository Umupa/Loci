// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { mergeTranslation, sourceUnits, serializeTranslation } from "../../learning/model/sourceTranslation";
import { DocumentBody, shownDocument } from "./DocumentBody";

const disk = vi.hoisted(() => ({ text: null as string | null }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async (command: string) => command === "source_translation_read" ? disk.text : null) }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
vi.mock("../../learning/model/learningStore", () => ({
  registerLearningSource: vi.fn(async () => undefined), listAnnotations: vi.fn(async () => []), subscribeLearningChanges: () => () => {},
  upsertAnnotation: vi.fn(), deleteAnnotation: vi.fn(),
}));
vi.mock("../../sessions/model/quoteDraft", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../sessions/model/quoteDraft")>(),
  requestAddToChat: vi.fn(),
}));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("article", null, text) }));

const BODY = "# Pods\n\nPods are the smallest deployable units of computing that you can create and manage in Kubernetes.\n\n## Pod phase\n\nThe phase of a Pod is a simple, high-level summary of where the Pod is in its lifecycle.\n";
const source = shownDocument({ id: "pods", title: "Pods", body: BODY, sourceUrl: "https://kubernetes.io/pods", createdAt: 1, updatedAt: 2 });
let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  localStorage.clear();
  localStorage.setItem("loci:agent-roster", JSON.stringify([{ id: "a", name: "Kern", folder: "/m/kern", sessionId: "chat", language: "zh-CN" }]));
  disk.text = null;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.clearAllMocks(); vi.unstubAllGlobals(); });

const render = (section?: string) => act(async () => { root.render(createElement(DocumentBody, { document: source, agentId: "a", section, bare: true })); });
const text = (selector: string) => container.querySelector<HTMLElement>(selector);

it("offers to have an English source translated when nothing is yet", async () => {
  await render();
  expect(text("[data-translation-bar]")?.textContent).toContain("Not translated into 简体中文 yet");
  expect(text("[data-reading-text]")?.hidden).toBe(false);
  await act(async () => [...container.querySelectorAll("button")].find((button) => button.textContent === "Ask Kern to translate")!.click());
  expect(requestAddToChat).toHaveBeenCalledWith(expect.stringContaining('"Pods" (pods) into Simplified Chinese with documents.translate'), "plain", { targetSessionId: "chat" });
});

it("shows the translation in place of the original, the original, or both", async () => {
  const units = sourceUnits(BODY);
  disk.text = serializeTranslation("pods", mergeTranslation(units.slice(1), "## Pod 阶段\n\nPod 的阶段是一个简单的高层概要。\n", { language: "zh-CN", units: [] }));
  await render("Pod phase");
  expect(text("[data-reading-text]")?.hidden).toBe(true);
  expect(text("[data-translated-text]")?.textContent).toContain("Pod 的阶段是一个简单的高层概要");
  expect(text("[data-translation-bar]")?.textContent).toContain("Translated by Kern, not the original");
  await act(async () => text('[role="radio"][aria-checked="false"]:nth-child(2)')!.click());
  expect(text("[data-reading-text]")?.hidden).toBe(false);
  expect(text("[data-translated-text]")).toBeNull();
  await act(async () => [...container.querySelectorAll<HTMLElement>('[role="radio"]')].find((radio) => radio.textContent === "Both")!.click());
  expect(text(".translation-pair__original")?.textContent).toContain("high-level summary");
  expect(text(".translation-pair__translated")?.textContent).toContain("高层概要");
  expect(localStorage.getItem("loci.translationView")).toBe("both");
});
