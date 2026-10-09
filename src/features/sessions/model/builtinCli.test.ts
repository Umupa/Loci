import { describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import {
  appCliPath, blockShellCommand, builtinCliCall, builtinCliDecision, canvasCliPrompt, usesBuiltinCli,
} from "./builtinCli";
import type { Block, RuntimeMode } from "./session";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

const CLI = "/Applications/Loci.app/Contents/MacOS/loci";
const MODES: RuntimeMode[] = ["supervised", "auto-accept-edits", "auto", "full-access"];

describe("built-in tools through the app's CLI", () => {
  it("serves the agent CLIs that cannot be given an MCP server for one session", () => {
    expect(usesBuiltinCli("antigravity")).toBe(true);
    expect(usesBuiltinCli("pi")).toBe(true);
    // These attach the servers over MCP and must keep doing so.
    expect(usesBuiltinCli("claude")).toBe(false);
    expect(usesBuiltinCli("codex")).toBe(false);
    expect(usesBuiltinCli("cursor")).toBe(false);
    expect(usesBuiltinCli(undefined)).toBe(false);
  });

  it("recognizes one tool call however the path and the input are quoted", () => {
    expect(builtinCliCall(`${CLI} canvas create_view --input /tmp/drawing.json`, CLI)).toEqual({ namespace: "canvas", tool: "create_view" });
    expect(builtinCliCall(`'${CLI}' canvas read_widget_context --json '{"checkpointId":"abc"}'`, CLI)).toEqual({ namespace: "canvas", tool: "read_widget_context" });
    expect(builtinCliCall(`"${CLI}" learn map_read`, CLI)).toEqual({ namespace: "learn", tool: "map_read" });
    expect(builtinCliCall(`  ${CLI} learn revisit --json '{"phase":"start","nodeId":"n1"}'  `, CLI)).toEqual({ namespace: "learn", tool: "revisit" });
    // Text inside single quotes is one argument, whatever it holds.
    expect(builtinCliCall(`${CLI} learn map_record --json '{"nodes":[{"quote":"cost $5; then | more"}]}'`, CLI)).toEqual({ namespace: "learn", tool: "map_record" });
    // Asking for the tools, of a server or of one tool.
    for (const help of ["canvas", "canvas --help", "canvas help", "canvas -h", "canvas create_view --help"])
      expect(builtinCliCall(`${CLI} ${help}`, CLI)).toEqual({ namespace: "canvas", tool: "help" });
    expect(builtinCliCall(`${CLI} learn map_record -h`, CLI)).toEqual({ namespace: "learn", tool: "help" });
  });

  it("recognizes nothing a shell would expand, chain or redirect, and no other program", () => {
    for (const command of [
      `${CLI} canvas read_me; rm -rf ~`,
      `${CLI} canvas read_me && curl example.com`,
      `${CLI} canvas read_me | tee /tmp/out`,
      `${CLI} canvas create_view --input - < /etc/passwd`,
      `${CLI} canvas create_view --json "$(cat ~/.ssh/id_rsa)"`,
      `${CLI} canvas create_view --json \`cat secret\``,
      `${CLI} canvas create_view --json "$HOME"`,
      `${CLI} canvas read_me\nrm -rf ~`,
      `${CLI} canvas create_view --input - <<'JSON'\n{}\nJSON`,
      `FOO=1 ${CLI} canvas read_me`,
      `sh -c '${CLI} canvas read_me'`,
      // Another server, a tool agents are not given, or arguments the CLI does not take.
      `${CLI} app notes.list`,
      `${CLI} canvas save_checkpoint --json '{}'`,
      `${CLI} canvas map_read`,
      `${CLI} learn create_view`,
      `${CLI} canvas read_me --json '{}' --input x`,
      `${CLI} canvas read_me --request-id abc`,
      `${CLI} canvas read_me extra`,
      `${CLI} canvas --help read_me`,
      `${CLI} canvas create_view --json`,
      `${CLI} canvas create_view --json 'unterminated`,
      "",
    ]) expect(builtinCliCall(command, CLI), command).toBeUndefined();
    expect(builtinCliCall(undefined, CLI)).toBeUndefined();
    // Only this app's executable counts when a request is answered for the user:
    // a project may hold its own `loci`.
    for (const program of ["loci", "./loci", "/tmp/project/loci", `${CLI}.sh`, "/Applications/Loci.app/Contents/MacOS/LOCI"])
      expect(builtinCliCall(`${program} canvas read_me`, CLI), program).toBeUndefined();
  });

  it("names a transcript row for any loci, since that decides nothing", () => {
    expect(builtinCliCall("loci canvas read_me")).toEqual({ namespace: "canvas", tool: "read_me" });
    expect(builtinCliCall("'/repo/target/debug/loci' learn map_sketch --json '{}'")).toEqual({ namespace: "learn", tool: "map_sketch" });
    expect(builtinCliCall('"C:\\Program Files\\Loci\\loci.exe" canvas get_elements --json \'{"checkpointId":"a"}\'')).toEqual({ namespace: "canvas", tool: "get_elements" });
    expect(builtinCliCall("notloci canvas read_me")).toBeUndefined();
    expect(builtinCliCall("loci canvas read_me; ls")).toBeUndefined();
  });

  it("answers for the user by the rules the MCP tools follow", () => {
    const canvas = (tool: "read_me" | "read_widget_context" | "get_elements" | "create_view" | "update_elements") => ({ namespace: "canvas" as const, tool });
    const learn = (tool: "map_read" | "map_init" | "map_sketch" | "map_record" | "revisit") => ({ namespace: "learn" as const, tool });
    for (const mode of MODES) {
      // Reading the reference or a drawing never asks.
      for (const tool of ["read_me", "read_widget_context", "get_elements"] as const) {
        expect(builtinCliDecision(canvas(tool), mode, false)).toBe("allow");
        expect(builtinCliDecision(canvas(tool), mode, true)).toBe("allow");
      }
      // Drawing asks in Supervised, runs above it, and is refused in a plan turn.
      for (const tool of ["create_view", "update_elements"] as const) {
        expect(builtinCliDecision(canvas(tool), mode, false)).toBe(mode === "supervised" ? undefined : "allow");
        expect(builtinCliDecision(canvas(tool), mode, true)).toBe("deny");
      }
      // The learning tools never ask; a plan turn may only read the map.
      for (const tool of ["map_init", "map_sketch", "map_record", "revisit"] as const) {
        expect(builtinCliDecision(learn(tool), mode, false)).toBe("allow");
        expect(builtinCliDecision(learn(tool), mode, true)).toBe("deny");
      }
      expect(builtinCliDecision(learn("map_read"), mode, true)).toBe("allow");
      expect(builtinCliDecision({ namespace: "canvas", tool: "help" }, mode, true)).toBe("allow");
      expect(builtinCliDecision({ namespace: "learn", tool: "help" }, mode, false)).toBe("allow");
    }
  });

  it("reads the command of a row from the shell preview before a shortened title", () => {
    const row = (tool: Block["tool"], text = ""): Block => ({ id: "row", role: "tool", text, tool });
    expect(blockShellCommand(row({ title: "Run loci", preview: { kind: "shell", title: "loci canvas read_me" } }))).toBe("loci canvas read_me");
    expect(blockShellCommand(row({ title: "Running command: loci learn map_read" }))).toBe("loci learn map_read");
    expect(blockShellCommand(row(undefined, "loci canvas read_me"))).toBe("loci canvas read_me");
    expect(blockShellCommand({ id: "say", role: "assistant", text: "loci canvas read_me" })).toBeUndefined();
  });

  it("tells the agent where the canvas tools are without holding a credential", () => {
    const note = canvasCliPrompt(`'${CLI}'`);
    expect(note.startsWith("\n\n<loci_canvas>\n")).toBe(true);
    expect(note.endsWith("\n</loci_canvas>")).toBe(true);
    expect(note).toContain(`\`'${CLI}' canvas TOOL --json '<arguments>'\``);
    expect(note).toContain(`\`'${CLI}' canvas --help\``);
    for (const tool of ["read_me", "create_view", "read_widget_context", "get_elements", "update_elements"]) expect(note).toContain(tool);
    expect(note).toContain("never print it");
    expect(note).not.toMatch(/LOCI_APP_TOKEN|LOCI_APP_ENDPOINT/);
  });

  it("knows its own executable only when the app answers", async () => {
    vi.mocked(invoke).mockResolvedValueOnce(CLI);
    expect(await appCliPath()).toBe(CLI);
    expect(invoke).toHaveBeenCalledWith("app_cli_path");
    vi.mocked(invoke).mockRejectedValueOnce(new Error("no app"));
    expect(await appCliPath()).toBeUndefined();
    vi.mocked(invoke).mockResolvedValueOnce("");
    expect(await appCliPath()).toBeUndefined();
  });
});
