// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { MarkdownPreview } from "./AgentMarkdown";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), convertFileSrc: (path: string) => `asset://${path}` }));

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const svg = new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"/>');

describe("pictures saved with a reading", () => {
  let root: Root;
  let container: HTMLDivElement;
  const files = new Map<string, Uint8Array>();
  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    files.clear();
    vi.mocked(invoke).mockReset().mockImplementation(async (command, args) => {
      const path = (args as { path?: string } | undefined)?.path ?? "";
      if (command !== "read_binary_file" || !files.has(path)) throw new Error(`${path}: No such file or directory`);
      return files.get(path)!.buffer.slice(0) as never;
    });
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
  });
  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
  });
  async function show(text: string, cwd: string) {
    await act(async () => root.render(createElement(MarkdownPreview, { text, cwd })));
    // Each picture is read after the document is on screen.
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
  }
  const images = () => [...container.querySelectorAll("img")].map((image) => [image.getAttribute("data-local-image"), image.getAttribute("alt"), image.getAttribute("src")]);

  it("shows the figures a reading links by relative path, from the files beside it", async () => {
    files.set("/learn/k8s/sources/assets/pod-lifecycle.png", png);
    files.set("/learn/k8s/sources/assets/架构.svg", svg);
    await show("# Pod\n\n![生命周期](assets/pod-lifecycle.png)\n\n![架构](./assets/架构.svg)", "/learn/k8s/sources");
    expect(images()).toEqual([
      ["/learn/k8s/sources/assets/pod-lifecycle.png", "生命周期", "data:image/png;base64,iVBORw0KGgoBAgM="],
      ["/learn/k8s/sources/assets/架构.svg", "架构", expect.stringMatching(/^data:image\/svg\+xml;base64,/)],
    ]);
  });

  it("follows ../ from the original of a translated reading to the same figures", async () => {
    files.set("/learn/k8s/sources/assets/pod-lifecycle.png", png);
    await show("![lifecycle](../assets/pod-lifecycle.png)", "/learn/k8s/sources/original");
    expect(images()).toEqual([["/learn/k8s/sources/assets/pod-lifecycle.png", "lifecycle", "data:image/png;base64,iVBORw0KGgoBAgM="]]);
  });

  it("shows reference-style figures without changing links sharing their definition", async () => {
    files.set("/learn/k8s/sources/assets/pod.svg", svg);
    await show('![Pod diagram][figure]\n\n[Open figure][figure]\n\n[figure]: assets/pod.svg "Pod architecture"', "/learn/k8s/sources");
    expect(images()).toEqual([["/learn/k8s/sources/assets/pod.svg", "Pod diagram", expect.stringMatching(/^data:image\/svg\+xml;base64,/)]]);
    expect(container.querySelector("img")?.getAttribute("title")).toBe("Pod architecture");
    const link = container.querySelector("a");
    expect(link?.textContent).toBe("Open figure");
    expect(link?.getAttribute("href")).toBe("/learn/k8s/sources/assets/pod.svg");
  });

  it("shows nothing for a remote picture, a missing file, or a file that is not a picture", async () => {
    files.set("/learn/k8s/sources/notes.txt", new TextEncoder().encode("<html><script>x()</script>"));
    await show("![remote](https://example.com/a.png)\n\n![missing](assets/none.png)\n\n![text](notes.txt)", "/learn/k8s/sources");
    // The webview never asks the network for a picture, and a local one without picture bytes stays blank.
    expect(images()).toEqual([["/learn/k8s/sources/assets/none.png", "missing", null], ["/learn/k8s/sources/notes.txt", "text", null]]);
    expect(vi.mocked(invoke).mock.calls.map(([command]) => command)).toEqual(["read_binary_file", "read_binary_file"]);
  });
});
