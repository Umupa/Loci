import { describe, expect, it } from "vitest";
import { isNewCommand } from "./newCommand";

describe("new command", () => {
  it("matches a standalone /new command", () => {
    expect(isNewCommand("/new")).toBe(true);
    expect(isNewCommand("  /NEW\n")).toBe(true);
  });

  it("does not consume ordinary prompt text", () => {
    expect(isNewCommand("/new idea")).toBe(false);
    expect(isNewCommand("what's /new here")).toBe(false);
    expect(isNewCommand("/newer")).toBe(false);
  });
});
