// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SCHEME_CHANGE_EVENT } from "../../settings/model/appearance";
import { AgentMarkdown } from "./AgentMarkdown";

const { renderDiagram, getMermaid } = vi.hoisted(() => {
  const renderDiagram = vi.fn();
  return { renderDiagram, getMermaid: vi.fn((_config?: { theme: string }) => ({ render: renderDiagram })) };
});

vi.mock("../../../shared/lib/markdown/mermaidPlugin", () => ({
  createLazyMermaidPlugin: () => ({
    name: "mermaid", type: "diagram", language: "mermaid", getMermaid,
  }),
}));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => undefined }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), isTauri: () => false, convertFileSrc: (path: string) => path }));

const diagram = `<svg xmlns="http://www.w3.org/2000/svg" id="chart" width="100%" viewBox="-8 -12 1200 680" style="width:100%;height:auto;max-width:1200px">
  <defs><marker id="arrow"><path d="M 0 0 L 8 4 L 0 8"/></marker></defs>
  <path marker-end="url(#arrow)" d="M 0 0 L 100 100"/>
  <foreignObject width="180" height="60"><div xmlns="http://www.w3.org/1999/xhtml"><span class="nodeLabel">中文节点<br/>下一步</span></div></foreignObject>
  <a href="#details"><text>Details</text></a>
  <style></style>
</svg>`;

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  document.documentElement.style.setProperty("--color-background-base", "#f8f8f4");
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  renderDiagram.mockReset().mockResolvedValue({ svg: diagram });
  getMermaid.mockClear();
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  document.documentElement.style.removeProperty("--color-background-base");
  vi.unstubAllGlobals();
});

async function show(code = "graph TD; A --> B", complete = true) {
  await act(async () => root.render(createElement(AgentMarkdown, {
    text: `\`\`\`mermaid\n${code}${complete ? "\n```" : ""}`,
    streaming: !complete,
    revealOnMount: false,
  })));
  // Happy DOM's SVG parser drops style text and following siblings. Add the
  // stylesheet through the DOM so the export still exercises embedded CSS.
  const style = container.querySelector("svg style");
  if (style) style.textContent = "#chart .nodeLabel { color: #333; }";
}

const trigger = () => container.querySelector<HTMLDivElement>('[aria-label="Open Mermaid diagram full screen"]');
const dialog = () => document.querySelector<HTMLElement>('[role="dialog"]');

describe("Markdown Mermaid image preview", () => {
  it("opens a sized SVG image with Chinese labels and leaves the inline diagram unchanged", async () => {
    await show();
    const opener = trigger()!;
    const original = opener.querySelector("svg")!;
    const originalAttributes = original.getAttributeNames().map((name) => [name, original.getAttribute(name)]);
    const bubble = vi.fn();
    document.addEventListener("click", bubble);
    act(() => { opener.focus(); opener.click(); });
    document.removeEventListener("click", bubble);

    expect(dialog()?.getAttribute("aria-label")).toBe("Image preview: Mermaid diagram");
    const source = dialog()!.querySelector("img")!.getAttribute("src")!;
    expect(source).toMatch(/^data:image\/svg\+xml;charset=utf-8,/);
    const decoded = decodeURIComponent(source.slice(source.indexOf(",") + 1));
    const exported = new DOMParser().parseFromString(decoded, "image/svg+xml");
    expect(exported.querySelector("parsererror")).toBeNull();
    const svg = exported.documentElement;
    expect(svg.getAttribute("width")).toBe("1200");
    expect(svg.getAttribute("height")).toBe("680");
    expect(svg.getAttribute("viewBox")).toBe("-8 -12 1200 680");
    expect(svg.getAttribute("style")).toContain("background-color: #f8f8f4");
    expect(svg.getAttribute("style")).not.toContain("max-width");
    expect(svg.querySelector("foreignObject")?.textContent).toBe("中文节点下一步");
    expect(decoded).toContain("#chart .nodeLabel { color: #333; }");
    expect(svg.querySelector('[marker-end="url(#arrow)"]')).not.toBeNull();
    const inline = opener.querySelector("svg")!;
    expect(inline.getAttributeNames().map((name) => [name, inline.getAttribute(name)])).toEqual(originalAttributes);
    expect(inline.querySelector("foreignObject")?.textContent).toBe("中文节点下一步");
    expect(bubble).not.toHaveBeenCalled();
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Close image preview");

    act(() => dialog()!.querySelector<HTMLButtonElement>("button")!.click());
    expect(dialog()).toBeNull();
    expect(document.activeElement).toBe(opener);
  });

  it("supports Enter and Space, Escape and backdrop dismissal without closing on the image", async () => {
    await show();
    const opener = trigger()!;
    act(() => { opener.focus(); opener.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })); });
    expect(dialog()).not.toBeNull();
    act(() => window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(dialog()).toBeNull();
    expect(document.activeElement).toBe(opener);

    const space = new KeyboardEvent("keydown", { key: " ", bubbles: true, cancelable: true });
    act(() => opener.dispatchEvent(space));
    expect(space.defaultPrevented).toBe(true);
    const image = dialog()!.querySelector("img")!;
    Object.defineProperties(image, { naturalWidth: { value: 1200 }, naturalHeight: { value: 680 } });
    act(() => image.dispatchEvent(new Event("load")));
    const click = (element: Element) => act(() => {
      for (const type of ["pointerdown", "pointerup"]) {
        element.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 1, isPrimary: true, button: 0 }));
      }
    });
    click(image);
    expect(dialog()).not.toBeNull();
    click(dialog()!.querySelector('[data-image-zoom="modal"]')!);
    expect(dialog()).toBeNull();
    expect(document.activeElement).toBe(opener);
  });

  it("preserves diagram links instead of opening a preview from their click or key events", async () => {
    await show();
    const link = trigger()!.querySelector("a")!;
    act(() => {
      link.querySelector("text")!.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      link.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
      link.dispatchEvent(new KeyboardEvent("keydown", { key: " ", bubbles: true }));
    });
    expect(dialog()).toBeNull();
  });

  it("offers no image preview while loading, for invalid diagrams, or for an unfinished fence", async () => {
    let reject!: (reason: Error) => void;
    renderDiagram.mockReturnValueOnce(new Promise((_resolve, rejectRender) => { reject = rejectRender; }));
    await show();
    expect(trigger()).toBeNull();
    expect(dialog()).toBeNull();
    await act(async () => reject(new Error("Invalid diagram")));
    expect(trigger()).toBeNull();
    expect(container.querySelector(".markdown-code-shell")?.textContent).toContain("graph TD; A --> B");

    renderDiagram.mockClear();
    await show("graph TD; A -->", false);
    expect(trigger()).toBeNull();
    expect(dialog()).toBeNull();
    expect(renderDiagram).not.toHaveBeenCalled();
  });

  it("dismisses stale previews when the code, scheme, or fence completeness changes", async () => {
    await show();
    act(() => trigger()!.click());
    await show("graph TD; C --> D");
    expect(dialog()).toBeNull();
    act(() => trigger()!.click());
    const currentTheme = getMermaid.mock.calls.at(-1)?.[0] as { theme: string } | undefined;
    const nextScheme = currentTheme?.theme === "dark" ? "light" : "dark";
    await act(async () => window.dispatchEvent(new CustomEvent(SCHEME_CHANGE_EVENT, { detail: nextScheme })));
    expect(dialog()).toBeNull();
    expect(getMermaid).toHaveBeenLastCalledWith(expect.objectContaining({ theme: nextScheme === "light" ? "default" : "dark" }));
    act(() => trigger()!.click());
    await show("graph TD; C -->", false);
    expect(dialog()).toBeNull();
    expect(trigger()).toBeNull();
  });

  it("ignores an older async render after the document changes", async () => {
    let resolveOld!: (value: { svg: string }) => void;
    renderDiagram.mockReturnValueOnce(new Promise((resolve) => { resolveOld = resolve; }));
    await show("graph TD; Old --> Diagram");
    await show("graph TD; Current --> Diagram");
    expect(trigger()?.textContent).toContain("中文节点");
    await act(async () => resolveOld({ svg: diagram.replace("中文节点", "旧节点") }));
    expect(trigger()?.textContent).toContain("中文节点");
    expect(trigger()?.textContent).not.toContain("旧节点");
  });
});
