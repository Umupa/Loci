import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { LociCliError, lociCli } from "./loci.mjs";

/** A stand-in for the loci executable that answers what the test tells it to. */
function fakeLoci(script: string): string {
  const dir = mkdtempSync(join(tmpdir(), "loci-e2e-"));
  const bin = join(dir, "loci");
  writeFileSync(bin, `#!/bin/sh\n${script}\n`);
  chmodSync(bin, 0o755);
  return bin;
}

describe("the e2e client", () => {
  it("never targets the installed Loci unless told to", () => {
    expect(() => lociCli({ bin: "loci", app: undefined })).toThrow(/Choose the Loci/);
    expect(() => lociCli({ bin: "loci", app: "com.loci.desktop", allowRelease: false })).toThrow(/installed Loci/);
    expect(lociCli({ bin: "loci", app: "com.loci.desktop", allowRelease: true }).app).toBe("com.loci.desktop");
  });

  it("passes --app first and returns results", async () => {
    const bin = fakeLoci(`printf '{"ok":true,"result":{"args":"%s"}}\\n' "$*"`);
    const loci = lociCli({ bin, app: "com.loci.desktop.qa" });
    expect(await loci.call("mentors", "list")).toEqual({ args: "--app com.loci.desktop.qa mentors list" });
  });

  it("throws refusals with their code and exit status", async () => {
    const bin = fakeLoci(`echo '{"ok":false,"error":"No mentor x","code":"not_found"}'; exit 1`);
    const loci = lociCli({ bin, app: "com.loci.desktop.qa" });
    const error = await loci.call("mentors", "show", "x").catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(LociCliError);
    expect(error).toMatchObject({ code: "not_found", exitCode: 1, message: "No mentor x" });
  });

  it("reads the final envelope of a streamed reply", async () => {
    const bin = fakeLoci(`echo '{"type":"delta","text":"Hel"}'; echo '{"type":"delta","text":"lo"}'; echo '{"type":"done","response":{"ok":true,"result":{"status":"done","text":"Hello"}}}'`);
    const result = await lociCli({ bin, app: "com.loci.desktop.qa" }).run("mentors", "send", "m", "hi", "--wait", "--stream");
    expect(result).toMatchObject({ ok: true, result: { text: "Hello" }, exitCode: 0 });
    expect(result.lines).toHaveLength(3);
  });
});
