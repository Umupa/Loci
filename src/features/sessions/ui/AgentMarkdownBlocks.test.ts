// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AgentMarkdown } from "./AgentMarkdown";

vi.mock("../../../shared/lib/markdown/mermaidPlugin", () => ({
  createLazyMermaidPlugin: () => ({
    name: "mermaid", type: "diagram", language: "mermaid",
    getMermaid: () => ({ render: async () => ({ svg: "<svg><text>A</text></svg>" }) }),
  }),
}));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => undefined }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), isTauri: () => false, convertFileSrc: (path: string) => path }));

const text = [
  "# Pods",
  "Intro.",
  "| Phase | Meaning |\n| --- | --- |\n| `Pending` | **accepted** |",
  "```mermaid\ngraph TD; A --> B\n```",
  "```ts title=pod.ts\nconst phase = \"Pending\";\n```",
  "> | a | b |\n> |---|---|\n> | 1 | 2 |",
  "![Pod phases](https://example.com/phases.svg)",
].join("\n\n");

describe("blocks of a saved text", () => {
  let root: Root;
  let container: HTMLDivElement;
  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
  });
  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
  });
  const show = (wholeDocument: boolean) => act(async () => root.render(createElement(AgentMarkdown, {
    text, wholeDocument, sourceUrl: "https://example.com/docs/", revealOnMount: false,
  })));
  const blocks = () => [...container.querySelectorAll<HTMLElement>("[data-block-source]")]
    .map((element) => [element.dataset.blockKind, element.dataset.blockSource]);

  it("carry their Markdown as written: a table, a diagram, a code block and a picture", async () => {
    await show(true);
    expect(blocks()).toEqual([
      ["table", "| Phase | Meaning |\n| --- | --- |\n| `Pending` | **accepted** |"],
      ["mermaid", "```mermaid\ngraph TD; A --> B\n```"],
      ["code", "```ts title=pod.ts\nconst phase = \"Pending\";\n```"],
      // A table in a quote loses the quote's marks.
      ["table", "| a | b |\n|---|---|\n| 1 | 2 |"],
      ["image", "![Pod phases](https://example.com/phases.svg)"],
    ]);
    expect(container.querySelector("table")?.hasAttribute("data-block-source")).toBe(true);
  });

  it("carry nothing in a conversation's replies", async () => {
    await show(false);
    expect(blocks()).toEqual([]);
  });
});
