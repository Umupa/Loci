// @vitest-environment happy-dom
import { act, createElement, useMemo, useRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { registerLearningSource, upsertAnnotation } from "../model/learningStore";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { documentMarkSpec } from "../../agents/model/documentMarks";
import { copyText } from "../../../platform/tauri/clipboard";
import { useReadingMarks } from "./useReadingMarks";

vi.mock("../../agents/model/agent", () => ({ findAgent: () => ({ id: "kern", name: "Kern", sessionId: "s-kern" }) }));
vi.mock("../model/learningStore", () => ({
  registerLearningSource: vi.fn(), listAnnotations: vi.fn(async () => []), subscribeLearningChanges: () => () => {},
  upsertAnnotation: vi.fn(async (annotation: unknown) => annotation), deleteAnnotation: vi.fn(),
}));
vi.mock("../../../platform/tauri/clipboard", () => ({ copyText: vi.fn(async () => undefined) }));
vi.mock("../../sessions/model/quoteDraft", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../sessions/model/quoteDraft")>(),
  requestAddToChat: vi.fn(),
}));

const TABLE = "| Phase | Meaning |\n| --- | --- |\n| Pending | accepted |";
const document_ = { id: "pods", title: "Pods", body: "" };

function Reader() {
  const ref = useRef<HTMLDivElement>(null);
  const spec = useMemo(() => documentMarkSpec(document_, "kern"), []);
  const marks = useReadingMarks(ref, spec, { agentId: "kern" });
  return createElement("div", null,
    createElement("div", { ref },
      createElement("h2", null, "Pod phase"),
      createElement("table", { "data-block-kind": "table", "data-block-source": TABLE },
        createElement("tbody", null, createElement("tr", null, createElement("td", null, "Pending"), createElement("td", null, "accepted"))))),
    marks.popover);
}

let host: HTMLDivElement; let root: Root;
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  // A laid-out reader: the table sits 100px in, with room for the handle in the margin.
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockImplementation(function (this: Element) {
    return this.tagName === "TABLE" ? new DOMRect(100, 100, 400, 200) : new DOMRect(0, 0, 800, 800);
  });
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

async function openBar() {
  await act(async () => root.render(createElement(Reader)));
  await act(async () => host.querySelector("td")!.dispatchEvent(new PointerEvent("pointerover", { bubbles: true })));
  const handle = document.querySelector<HTMLButtonElement>("[data-block-handle]");
  expect(handle?.getAttribute("aria-label")).toBe("Block actions");
  // In the margin to the table's left, level with its top.
  expect([handle!.style.left, handle!.style.top]).toEqual(["72px", "102px"]);
  await act(async () => handle!.click());
  const bar = document.querySelector('[aria-label="Table actions"]');
  expect(bar).not.toBeNull();
  return bar!;
}
const button = (bar: Element, label: string) => [...bar.querySelectorAll("button")].find((entry) => entry.textContent === label || entry.getAttribute("aria-label") === label)!;

it("asks the mentor about a table as its Markdown, cited by its section", async () => {
  const bar = await openBar();
  expect([...bar.querySelectorAll("button")].map((entry) => entry.textContent || entry.getAttribute("aria-label"))).toEqual(["Highlight", "Ask Kern", "Save to note", "Copy as Markdown"]);
  await act(async () => button(bar, "Ask Kern").click());
  const [text, mode, context] = vi.mocked(requestAddToChat).mock.calls[0];
  expect(text).toBe("> | Phase | Meaning |\n> | --- | --- |\n> | Pending | accepted |\n\n");
  expect(mode).toBe("prompt");
  expect(context).toMatchObject({ targetSessionId: "s-kern", sources: [{ kind: "document", section: "Pod phase", quote: TABLE, anchor: { block: { kind: "table", index: 0, lead: "Pendingaccepted" } } }] });
  expect(registerLearningSource).toHaveBeenCalledOnce();
  expect(document.querySelector('[aria-label="Table actions"]')).toBeNull();
});

it("copies a table as a quote of its Markdown linked to its section", async () => {
  const bar = await openBar();
  await act(async () => button(bar, "Copy as Markdown").click());
  expect(vi.mocked(copyText).mock.calls[0][0]).toMatch(/^> \| Phase \| Meaning \|\n> \| --- \| --- \|\n> \| Pending \| accepted \|\n>\n> — \[Pods · Pod phase\]\(loci:\/\/source\/[\w-]+#section=Pod%20phase&quote=Pendingaccepted\)$/);
});

it("highlights the whole table, then opens its highlight's bar from the handle", async () => {
  const bar = await openBar();
  await act(async () => button(bar, "Highlight").click());
  const saved = vi.mocked(upsertAnnotation).mock.calls[0][0];
  expect(saved).toMatchObject({ target: { kind: "document", agentId: "kern", documentId: "pods" }, anchor: { exact: TABLE, block: { kind: "table" } }, source: { quote: TABLE, annotationId: saved.id } });
  expect(document.querySelector('[aria-label="Highlight actions"][role="toolbar"]')).not.toBeNull();
  expect(host.querySelector("table")!.getAttribute("data-block-mark")).toBe("selected");
  expect(document.querySelector("[data-block-handle]")?.getAttribute("aria-label")).toBe("Highlight actions");
});
