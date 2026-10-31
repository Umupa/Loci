import { describe, expect, it } from "vitest";
import { RELEASE_IDENTIFIER, updatePrompt, updatesItself } from "./updates";

describe("updates", () => {
  it("only the installed app updates itself", () => {
    expect(updatesItself(RELEASE_IDENTIFIER)).toBe(true);
    expect(updatesItself("com.loci.desktop.dev")).toBe(false);
    expect(updatesItself("com.loci.desktop.feeds")).toBe(false);
  });

  it("shows the release notes under the version", () => {
    expect(updatePrompt({ version: "0.2.0", currentVersion: "0.1.0", body: "### Fixed\n\n- A thing.\n" })).toBe(
      "Loci 0.2.0 is available. You have 0.1.0.\n\n### Fixed\n\n- A thing.",
    );
    expect(updatePrompt({ version: "0.2.0", currentVersion: "0.1.0", body: "  " })).toBe(
      "Loci 0.2.0 is available. You have 0.1.0.",
    );
  });
});
