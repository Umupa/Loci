// @vitest-environment happy-dom
import { act, createElement, useContext } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { AgentTranscript } from "./AgentTranscript";
import { PooledTranscript, TranscriptPool, TranscriptPoolOutlet } from "./TranscriptPool";
import { WidgetHostContext } from "../../learning/model/widgets";

vi.mock("./AgentMarkdown", () => ({
  AgentMarkdown: ({ text }: { text: string }) => { const host = useContext(WidgetHostContext); return createElement("output", { "data-widget-host": true }, text === "widget" ? JSON.stringify(host) : text); },
  MarkdownPreview: ({ text }: { text: string }) => createElement("span", null, text),
}));

it("keeps each pooled transcript's widget owner when the outlet lives outside its pane", async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div"); document.body.append(container);
  const root = createRoot(container);
  const pool = new TranscriptPool();
  const show = async (id: string) => act(async () => root.render(createElement("div", null,
    createElement("section", { key: id, "data-pane": id }, createElement(PooledTranscript, { pool, sessionId: id },
      createElement(AgentTranscript, { widgetHost: { owner: { kind: "session", id }, sourceSessionId: id }, blocks: [{ id: `question-${id}`, role: "user", text: "Explain" }, { id: `reply-${id}`, role: "assistant", text: "widget" }], visible: true }))),
    createElement(TranscriptPoolOutlet, { pool }))));
  try {
    await show("first");
    expect(container.querySelector("[data-widget-host]")?.textContent).toContain('"sourceSessionId":"first"');
    await show("second");
    expect(container.querySelector("[data-widget-host]")?.textContent).toContain('"sourceSessionId":"second"');
    await show("first");
    expect(container.querySelector("[data-widget-host]")?.textContent).toContain('"owner":{"kind":"session","id":"first"}');
  } finally {
    await act(async () => root.unmount()); container.remove(); vi.unstubAllGlobals();
  }
});
