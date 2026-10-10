// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Composer } from "./Composer";
import type { LearningMessageContext } from "../../learning/model/types";
import type { QuoteRequest } from "../model/quoteDraft";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => []), isTauri: () => false }));
vi.mock("@tauri-apps/api/webview", () => ({ getCurrentWebview: () => ({ onDragDropEvent: async () => () => {} }) }));
const context: LearningMessageContext = {
  sources: [{ id: "reference", kind: "web", title: "Blocking guide", url: "https://example.org/guide", quote: "Calls wait until a value arrives." }],
  widgetContext: { owner: { kind: "session", id: "original" }, id: "demo", title: "Channel demo", revision: 1, state: { capacity: 0, step: 2 } },
};
let host: HTMLDivElement;
let root: Root;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });
async function mount(onSubmit: ReturnType<typeof vi.fn>, request?: QuoteRequest, onLearningContextChange = vi.fn()) {
  await act(async () => root.render(createElement(Composer, {
    focused: true, harness: "codex", model: "test", runtimeMode: "supervised", executionCwd: "/repo", hideProjectPicker: true,
    onFocus: () => {}, onCwdChange: () => {}, onModelChange: () => {}, onRuntimeModeChange: () => {},
    onSubmit, quoteRequest: request, onLearningContextChange,
  })));
}
async function send() {
  await act(async () => host.querySelector<HTMLButtonElement>('button[aria-label="Send"]')!.click());
}
describe("learning context in the composer", () => {
  it("prefills an editable question without sending and includes state and sources on explicit Send", async () => {
    const onSubmit = vi.fn(() => true);
    const changed = vi.fn();
    await mount(onSubmit, { id: 1, text: "Why is the sender blocked?", mode: "plain", ...context }, changed);
    expect(onSubmit).not.toHaveBeenCalled();
    expect(host.textContent).toContain("Blocking guide");
    expect(host.textContent).toContain("Channel demo");
    expect(host.querySelector<HTMLTextAreaElement>("textarea")!.value).toContain("Why is the sender blocked?");
    await send();
    expect(onSubmit).toHaveBeenCalledWith(expect.stringContaining("Why is the sender blocked?"), [], expect.objectContaining(context));
    expect(host.querySelector('[aria-label="Learning context"]')).toBeNull();
    expect(changed).toHaveBeenLastCalledWith({});
  });
  it("lets the user remove a source while retaining the widget state", async () => {
    const onSubmit = vi.fn(() => true);
    await mount(onSubmit, { id: 2, text: "Explain", mode: "plain", ...context });
    await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="Remove source Blocking guide"]')!.click());
    await send();
    expect(onSubmit.mock.calls[0][2].sources).toEqual([]);
    expect(onSubmit.mock.calls[0][2].widgetContext).toEqual(context.widgetContext);
  });
  it("retains the question and source context when the application refuses submission", async () => {
    const onSubmit = vi.fn(() => false);
    await mount(onSubmit, { id: 3, text: "Explain", mode: "plain", ...context });
    await send();
    expect(host.querySelector<HTMLTextAreaElement>("textarea")!.value).toContain("Explain");
    expect(host.textContent).toContain("Blocking guide");
    expect(host.textContent).toContain("Channel demo");
  });
});
