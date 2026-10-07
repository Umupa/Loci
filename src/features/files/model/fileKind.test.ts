import { describe, expect, it } from "vitest";
import { fileKind } from "./fileKind";

describe("fileKind", () => {
  it("recognises documents and images by extension, whatever its case", () => {
    expect(fileKind("Survey.PDF")).toBe("pdf");
    expect(fileKind("notes.md")).toBe("markdown");
    expect(fileKind("scan.JPeG")).toBe("image");
  });

  it("tries everything else as text, including dotfiles and names without an extension", () => {
    expect(fileKind("data.csv")).toBe("text");
    expect(fileKind("README")).toBe("text");
    expect(fileKind(".pdf")).toBe("text");
    // Markup is text here, never an image the webview would run as a document.
    expect(fileKind("logo.svg")).toBe("text");
  });
});
