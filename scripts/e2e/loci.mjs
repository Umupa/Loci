// A small client for driving a running Loci through its `loci` command line,
// for end-to-end tests and the mentor evaluation. It never targets the
// installed Loci unless asked to: pass a Loci Dev or QA identifier.
//
//   import { lociCli } from "./scripts/e2e/loci.mjs";
//   const loci = lociCli({ app: "com.loci.desktop.qa" });
//   const { id } = await loci.call("mentors", "create", "--template", "learning-guide", "--provider", "agy");
//   const reply = await loci.call("mentors", "send", id, "Hello", "--wait", "--timeout", "600");
import { spawn } from "node:child_process";

export const RELEASE_IDENTIFIER = "com.loci.desktop";

/** A command Loci refused; `code` is the stable error code, `exitCode` the CLI's exit status. */
export class LociCliError extends Error {
  constructor(message, { code, exitCode, args, result }) {
    super(message);
    this.name = "LociCliError";
    this.code = code;
    this.exitCode = exitCode;
    this.args = args;
    this.result = result;
  }
}

/**
 * @param {{ bin?: string, app?: string, allowRelease?: boolean, env?: Record<string, string> }} [options]
 */
export function lociCli(options = {}) {
  const bin = options.bin ?? process.env.LOCI_BIN ?? "loci";
  const app = options.app ?? process.env.LOCI_APP_ID;
  const allowRelease = options.allowRelease ?? process.env.LOCI_ALLOW_RELEASE === "1";
  if (!app) throw new Error("Choose the Loci to drive: pass app (or set LOCI_APP_ID) to a Loci Dev or QA identifier");
  if (app === RELEASE_IDENTIFIER && !allowRelease) throw new Error("Refusing to drive the installed Loci; set LOCI_ALLOW_RELEASE=1 if you mean it");

  /** Runs one command and returns its JSON envelope and exit status. */
  function run(...args) {
    const last = args.at(-1);
    const stdin = last && typeof last === "object" && "stdin" in last ? args.pop().stdin : undefined;
    const argv = ["--app", app, ...args.map(String)];
    return new Promise((resolve, reject) => {
      const child = spawn(bin, argv, { env: { ...process.env, ...options.env }, stdio: ["pipe", "pipe", "pipe"] });
      let out = "";
      let err = "";
      child.stdout.on("data", (chunk) => { out += chunk; });
      child.stderr.on("data", (chunk) => { err += chunk; });
      child.on("error", reject);
      child.on("close", (exitCode) => {
        // --stream prints one JSON line per change; the envelope is in the last ("done") line.
        const lines = out.trim().split("\n").filter(Boolean);
        let envelope;
        try {
          const last = JSON.parse(lines.at(-1) ?? "");
          envelope = last.type === "done" ? last.response : lines.length > 1 && !last.type ? JSON.parse(out) : last;
        } catch {
          try { envelope = JSON.parse(out); } catch {
            reject(new Error(`loci ${argv.join(" ")} printed no JSON (exit ${exitCode}): ${err || out}`));
            return;
          }
        }
        resolve({ ...envelope, exitCode, lines: lines.length > 1 ? lines.map((line) => JSON.parse(line)) : undefined });
      });
      // A command that never reads stdin may exit first; its output still decides the result.
      child.stdin.on("error", () => {});
      child.stdin.end(stdin ?? "");
    });
  }

  /** Runs one command and returns its result, or throws a LociCliError. */
  async function call(...args) {
    const envelope = await run(...args);
    if (envelope.ok) return envelope.result;
    throw new LociCliError(envelope.error ?? "loci failed", { code: envelope.code, exitCode: envelope.exitCode, args, result: envelope.result });
  }

  return { app, bin, run, call };
}
