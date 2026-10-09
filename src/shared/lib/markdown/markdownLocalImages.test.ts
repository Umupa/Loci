import { describe, expect, it } from "vitest";
import { localImagePath, relativeImagePath, remarkLocalImages } from "./markdownLocalImages";

describe("pictures beside a document", () => {
  it("resolves a relative address against the document's folder", () => {
    expect(relativeImagePath("assets/pod.svg", "/learn/k8s/sources")).toBe("/learn/k8s/sources/assets/pod.svg");
    expect(relativeImagePath("./assets/a%20b.png?v=2#fig", "/learn/k8s/sources")).toBe("/learn/k8s/sources/assets/a b.png");
    // The original of a translated reading sits one folder down and shares the figures.
    expect(relativeImagePath("../assets/pod.svg", "/learn/k8s/sources/original")).toBe("/learn/k8s/sources/assets/pod.svg");
    expect(relativeImagePath("图/架构.png", "/learn/k8s")).toBe("/learn/k8s/图/架构.png");
  });

  it("leaves alone what is not beside the document", () => {
    for (const src of ["https://example.com/a.png", "//example.com/a.png", "data:image/png;base64,AAAA", "/note-assets/a.png", "/etc/passwd", "~/a.png", "file:///a.png", "", "#fig"])
      expect(relativeImagePath(src, "/learn/k8s")).toBeUndefined();
    expect(relativeImagePath("a.png", undefined)).toBeUndefined();
    expect(relativeImagePath("a.png", "~")).toBeUndefined();
  });

  it("marks such pictures before the address is sanitized, and reads the file back from the mark", () => {
    const tree = { type: "root", children: [
      { type: "paragraph", children: [{ type: "image", url: "../assets/架构 图.svg" }, { type: "image", url: "https://example.com/remote.png" }, { type: "link", url: "assets/not-an-image.md" }] },
    ] };
    remarkLocalImages({ cwd: "/learn/k8s/sources/original" })(tree);
    const [local, remote, link] = tree.children[0].children;
    expect(local.url).toMatch(/^\/local-image\/[A-Za-z0-9_-]+$/);
    expect(localImagePath(local.url)).toBe("/learn/k8s/sources/assets/架构 图.svg");
    expect(remote.url).toBe("https://example.com/remote.png");
    expect(link.url).toBe("assets/not-an-image.md");
    expect(localImagePath("/note-assets/a.png")).toBeUndefined();
    expect(localImagePath("/local-image/%%%")).toBeUndefined();
    expect(localImagePath("/local-image/")).toBeUndefined();
  });
});
