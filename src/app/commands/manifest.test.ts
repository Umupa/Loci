import { readFileSync, writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { COMMANDS } from "./index";
import { commandManifest } from "./registry";

const MANIFEST = new URL("../../../src-tauri/resources/cli-commands.json", import.meta.url);

describe("the CLI manifest", () => {
  it("matches the command definitions (run `npm run gen:cli` after changing them)", () => {
    const expected = `${JSON.stringify(commandManifest(COMMANDS.values()), null, 2)}\n`;
    if (process.env.UPDATE_CLI_MANIFEST === "1") writeFileSync(MANIFEST, expected);
    expect(readFileSync(MANIFEST, "utf8")).toBe(expected);
  });
});
