// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AgentMarkdown } from "./AgentMarkdown";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), convertFileSrc: (path: string) => `asset://${path}` }));

const page = "https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/";
const text = [
  "![phases](https://kubernetes.io/images/docs/pod-phases.svg)",
  "![components](/images/docs/components.svg)",
  "![beside](figure.png)",
  "![plain](http://example.com/tracker.png)",
  "[Probes](../probes/) and [the API](https://kubernetes.io/docs/reference/) and [below](#pod-phase)",
].join("\n\n");

describe("a source's pictures and links", () => {
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
  const show = (sourceUrl?: string) => act(async () => root.render(createElement(AgentMarkdown, { text, wholeDocument: true, sourceUrl })));
  const images = () => [...container.querySelectorAll("img")].map((image) => image.getAttribute("src"));
  const links = () => [...container.querySelectorAll("a")].map((link) => link.getAttribute("href"));

  it("come from where the source was published, over https only", async () => {
    await show(page);
    expect(images()).toEqual([
      "https://kubernetes.io/images/docs/pod-phases.svg",
      "https://kubernetes.io/images/docs/components.svg",
      "https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/figure.png",
    ]);
    expect(container.querySelector("img")?.getAttribute("referrerpolicy")).toBe("no-referrer");
    expect(links()).toEqual(["https://kubernetes.io/docs/concepts/workloads/pods/probes/", "https://kubernetes.io/docs/reference/", "#pod-phase"]);
  });

  it("are never fetched for text that is not a source, such as a reply", async () => {
    await show();
    expect(images()).toEqual([]);
    expect(links()).toContain("https://kubernetes.io/docs/reference/");
  });
});
