import { describe, expect, it } from "vitest";
import { appResourceUrl, fileResourcePath, fileResourceUrl, parseAppResourceUrl, resourceUrl } from "./appResourceLinks";

describe("Loci resource addresses", () => {
  it.each(["canvas", "note", "session"] as const)("round trips stable %s IDs", (kind) => {
    const id = "app-5bed7012-c8bc-445d-b95d-ead0f88e36a7-create-1";
    expect(parseAppResourceUrl(appResourceUrl(kind, id))).toEqual({ kind, id });
  });
  it.each([
    "loci://project/id", "loci://note/", "loci://note/../id", "loci://note/%69d",
    "loci://note/id#fragment", "loci://note/id?x=1", "loci://note/id/extra",
    "loci://user@note/id", "loci://note:1/id", "https://note/id", "note:id",
    "loci://NOTE/id",
  ])("rejects a noncanonical address: %s", (url) => {
    expect(parseAppResourceUrl(url)).toBeUndefined();
  });
  it("round trips compound IDs accepted by persistence", () => {
    const id = `app-app-5bed7012-c8bc-445d-b95d-ead0f88e36a7-${"s".repeat(128)}-${"n".repeat(128)}`;
    expect(id.length).toBeGreaterThan(256);
    expect(parseAppResourceUrl(appResourceUrl("note", id))).toEqual({ kind: "note", id });
  });
  it("does not construct a resource path from an arbitrary filename", () => {
    expect(() => appResourceUrl("note", "../../secret")).toThrow("Invalid resource ID");
  });
  it("round trips a project file with a page or a range of lines", () => {
    for (const place of [undefined, { page: 12 }, { lines: [10, 42] as [number, number] }]) {
      const url = fileResourceUrl("sources/巴菲特 1987.pdf", place);
      const resource = parseAppResourceUrl(url)!;
      expect(resource).toEqual({ kind: "file", id: expect.stringMatching(/^[A-Za-z0-9_-]+$/), ...(place ? { place } : {}) });
      expect(fileResourcePath(resource)).toBe("sources/巴菲特 1987.pdf");
      expect(resourceUrl(resource)).toBe(url);
    }
  });
  it.each(["/etc/passwd", "../secret", "sources/../../secret", "a//b", "a\\b", "./a"])("rejects a file link that could leave the project: %s", (path) => {
    expect(parseAppResourceUrl(fileResourceUrl(path))).toBeUndefined();
  });
  it.each(["loci://file/c291cmNlcw#p0", "loci://file/c291cmNlcw#L3", "loci://file/c291cmNlcw#x", "loci://note/id#p3", "loci://file/"])("rejects a malformed file link: %s", (url) => {
    expect(parseAppResourceUrl(url)).toBeUndefined();
  });
  it("carries a section, a quoted passage, a page or lines in a source link, and round-trips them", () => {
    const url = "loci://source/k8s-pod-lifecycle#section=Pod%20phase&quote=The%20phase%20of%20a%20Pod";
    expect(parseAppResourceUrl(url)).toEqual({ kind: "source", id: "k8s-pod-lifecycle", place: { section: "Pod phase", quote: "The phase of a Pod" } });
    expect(resourceUrl(parseAppResourceUrl(url)!)).toBe(url);
    expect(parseAppResourceUrl("loci://source/paper#p7")).toEqual({ kind: "source", id: "paper", place: { page: 7 } });
    expect(parseAppResourceUrl("loci://source/main#L12")).toEqual({ kind: "source", id: "main", place: { lines: [12, 12] } });
    const file = parseAppResourceUrl("loci://file/c291cmNlcw#L3-9&quote=fn%20main")!;
    expect(file).toEqual({ kind: "file", id: "c291cmNlcw", place: { lines: [3, 9], quote: "fn main" } });
    expect(resourceUrl(file)).toBe("loci://file/c291cmNlcw#L3-9&quote=fn%20main");
  });
  it.each([
    "loci://source/id#", "loci://source/id#quote=", "loci://source/id#quote=a&quote=b", "loci://source/id#other=x",
    "loci://source/id#quote=%E0%A4%A", "loci://source/id#L9-3", `loci://source/id#quote=${"a".repeat(501)}`,
    "loci://file/c291cmNlcw#section=Intro", "loci://file/c291cmNlcw#p2&quote=x",
  ])("rejects a malformed place: %s", (url) => {
    expect(parseAppResourceUrl(url)).toBeUndefined();
  });
});
