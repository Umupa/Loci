import { describe, expect, it } from "vitest";
import { appResourceUrl, parseAppResourceUrl } from "./appResourceLinks";

describe("Loci resource addresses", () => {
  it.each(["canvas", "note"] as const)("round trips stable %s IDs", (kind) => {
    const id = "app-5bed7012-c8bc-445d-b95d-ead0f88e36a7-create-1";
    expect(parseAppResourceUrl(appResourceUrl(kind, id))).toEqual({ kind, id });
  });
  it.each([
    "loci://session/id", "loci://note/", "loci://note/../id", "loci://note/%69d",
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
});
