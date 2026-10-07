// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AgentMarkdown } from "./AgentMarkdown";

const openUrl = vi.hoisted(() => vi.fn().mockResolvedValue(undefined));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl }));

describe("app resource links in replies", () => {
  let root: Root;
  let container: HTMLDivElement;
  const opened = vi.fn();
  const openFile = vi.fn();
  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    openUrl.mockClear(); opened.mockClear(); openFile.mockClear();
    window.addEventListener("loci-open-resource", opened);
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
  });
  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
    window.removeEventListener("loci-open-resource", opened);
    vi.unstubAllGlobals();
  });
  async function render(text: string, streaming = false) {
    await act(async () => root.render(createElement(AgentMarkdown, {
      text, streaming, cwd: "/repo", onOpenFile: openFile,
    })));
  }
  it.each(["note", "canvas"])("opens a %s link inside this window", async (kind) => {
    await render(`已保存：[架构图](loci://${kind}/resource-1)`);
    const link = container.querySelector<HTMLAnchorElement>("a")!;
    expect(link.getAttribute("href")).toBe(`loci://${kind}/resource-1`);
    expect(link.querySelector('[aria-hidden="true"]')).not.toBeNull();
    await act(async () => link.click());
    expect(opened).toHaveBeenCalledTimes(1);
    expect((opened.mock.calls[0][0] as CustomEvent).detail).toEqual({ kind, id: "resource-1" });
    expect(openUrl).not.toHaveBeenCalled();
    expect(openFile).not.toHaveBeenCalled();
  });
  it("keeps the resource link as streaming switches to the finished reply", async () => {
    const text = "[Plan](loci://note/plan)";
    await render(text, true);
    await render(text, false);
    expect(container.querySelector("a")?.getAttribute("href")).toBe("loci://note/plan");
  });
  it.each(["loci://session/id", "loci://note/../id", "loci://canvas/id?command=delete", "loci://note/id/extra"])("does not turn an invalid resource address into a link: %s", async (href) => {
    await render(`[Invalid](${href})`);
    expect(container.querySelector("a[href]" )).toBeNull();
    expect(container.textContent).toContain("Invalid");
    expect(opened).not.toHaveBeenCalled();
  });
  it("preserves ordinary web and file navigation", async () => {
    await render("[Web](https://example.com) [File](./guide.md)");
    const links = container.querySelectorAll<HTMLAnchorElement>("a");
    await act(async () => { links[0].click(); links[1].click(); });
    expect(openUrl).toHaveBeenCalledWith("https://example.com/");
    expect(openFile).toHaveBeenCalledWith("/repo/guide.md");
    expect(opened).not.toHaveBeenCalled();
  });
});
