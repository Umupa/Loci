import { describe, expect, it } from "vitest";
import { formatCodeRef, parseCodeRef } from "./codeRef";

describe("code references", () => {
  it("read the pin shorthand, plain paths and line ranges", () => {
    expect(parseCodeRef("repos/e2b-dev/runtime@3F2A9C1:packages/envd/main.go#L40-88"))
      .toEqual({ path: "repos/e2b-dev/runtime/packages/envd/main.go", commit: "3f2a9c1", lines: [40, 88] });
    expect(parseCodeRef("repos/x/a.go#L7")).toEqual({ path: "repos/x/a.go", lines: [7, 7] });
    expect(parseCodeRef("/abs/x.rs")).toEqual({ path: "/abs/x.rs" });
    // Not a commit: kept as a path.
    expect(parseCodeRef("node_modules/@types/x:y.ts")).toEqual({ path: "node_modules/@types/x:y.ts" });
    expect(parseCodeRef("a.go#L9-3")).toEqual({ path: "a.go#L9-3" });
  });

  it("write the pin shorthand", () => {
    expect(formatCodeRef("repos/x/", "abc1234", "src/a.go", [1, 2])).toBe("repos/x@abc1234:src/a.go#L1-2");
    expect(formatCodeRef("repos/x", "abc1234", "src/a.go")).toBe("repos/x@abc1234:src/a.go");
  });
});
