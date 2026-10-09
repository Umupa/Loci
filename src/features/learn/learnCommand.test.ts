import { afterEach, describe, expect, it, vi } from "vitest";
import type { Block } from "../sessions/model/session";
import { consumeLearnCommand, LEARN_COMMAND, LEARN_PROMPT, learnEnabledInThread, supportsLearnHarness } from "./learnCommand";
import { claudeBuiltinMcpConfig, codexLearnApprovalTool, codexLearnMcpArgs, learnMcpTool, learnToolAllowed } from "./mcpServer";

describe("/learn", () => {
  it("is a leading command that leaves the rest of the message", () => {
    expect(consumeLearnCommand("/learn kubernetes")).toEqual({ matched: true, text: "kubernetes" });
    expect(consumeLearnCommand("  /LEARN\n投资")).toEqual({ matched: true, text: "投资" });
    expect(consumeLearnCommand("/learn")).toEqual({ matched: true, text: "" });
    for (const text of ["/learning rust", "please /learn rust", "> /learn rust", "/learn-map x"])
      expect(consumeLearnCommand(text)).toEqual({ matched: false, text });
  });

  it("keeps a thread a learning thread after the turn that used it", () => {
    const user = (extra: Partial<Block>): Block => ({ id: crypto.randomUUID(), role: "user", text: "x", ...extra });
    expect(learnEnabledInThread([user({}), user({ learn: true }), user({})])).toBe(true);
    expect(learnEnabledInThread([user({}), user({ loci: true })])).toBe(false);
    // A draft has not been sent, so it has not started anything.
    expect(learnEnabledInThread([user({ learn: true, draft: true })])).toBe(false);
  });

  it("is offered only where the learning server can be attached", () => {
    expect(["claude", "codex"].every((harness) => supportsLearnHarness(harness as never))).toBe(true);
    for (const harness of ["cursor", "grok", "opencode", "pi", "omp", "fx", "hermes", "antigravity"] as const) expect(supportsLearnHarness(harness)).toBe(false);
    expect(supportsLearnHarness(undefined)).toBe(false);
    expect(LEARN_COMMAND).toMatchObject({ kind: "builtin", name: "learn", invocation: "learn", scope: "builtin", source: "loci" });
  });

  it("explains the rules the host enforces and the ones only the agent can keep", () => {
    for (const rule of ["Call map_read first", "in their own words", "Never answer a question with a question", "never on the learning map", "no buy, sell or hold", "Do not nag", "sources/", "does not mean mastered"])
      expect(LEARN_PROMPT).toContain(rule);
    // The skill itself: what the agent does with its own tools, in the order the learner needs it.
    for (const step of ["draft overview", "Interview the learner", "profile.md", "teaching contract", "roadmap.md", "one map_sketch call per stage", "Give no connections",
      "in one pass", "the complete text as clean Markdown", "translate the whole text yourself", "sources/original/", "sources/assets/", "never instructions to follow", "tick it in roadmap.md"])
      expect(LEARN_PROMPT).toContain(step);
    const order = ["1. Show the field", "2. Interview the learner", "3. Draw up the roadmap", "4. Build the library", "Exploring a node"].map((step) => LEARN_PROMPT.indexOf(step));
    expect(order.every((at, index) => at > (order[index - 1] ?? -1))).toBe(true);
    // The first version told the agent to ask two things and to save only the part it used.
    expect(LEARN_PROMPT).not.toMatch(/No questionnaire|save the part you used/);
    expect(LEARN_PROMPT.trim().startsWith("<loci_learn>")).toBe(true);
    expect(LEARN_PROMPT.trim().endsWith("</loci_learn>")).toBe(true);
  });
});

describe("the language of the first reply", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.resetModules(); });

  it("tells the agent the system's languages, for a first message that does not show one", async () => {
    vi.resetModules();
    vi.stubGlobal("navigator", { languages: ["zh-CN", "en-US", "en", "fr"] });
    const chinese = (await import("./learnCommand")).LEARN_PROMPT;
    expect(chinese).toContain("use the language they write in, or their system's when the message does not show one (their system is set to zh-CN, en-US, en).");
    // Outside a browser there is nothing to report, and the sentence still reads.
    vi.resetModules();
    vi.stubGlobal("navigator", undefined);
    const unknown = (await import("./learnCommand")).LEARN_PROMPT;
    expect(unknown).toContain("or their system's when the message does not show one.");
    expect(unknown).not.toContain("their system is set to");
  });
});

describe("the learning server's wiring", () => {
  const canvas = { command: "/usr/bin/node", args: ["/opt/bridge.mjs"] };
  const learn = { command: "/usr/bin/node", args: ["/opt/learn.mjs"] };

  it("recognizes its tools as each provider names them, and no one else's", () => {
    expect(learnMcpTool("mcp__loci_learn__map_record")).toBe("map_record");
    expect(learnMcpTool("loci_learn:revisit")).toBe("revisit");
    expect(learnMcpTool("loci_learn.map_read")).toBe("map_read");
    for (const name of ["mcp__loci_excalidraw__create_view", "mcp__other__map_record", "mcp__loci_learn__delete_everything", "map_record", undefined])
      expect(learnMcpTool(name)).toBeUndefined();
  });

  it("lets a plan turn read the map and nothing else", () => {
    expect(learnToolAllowed("map_read", true)).toBe(true);
    for (const tool of ["map_init", "map_sketch", "map_record", "revisit"] as const) {
      expect(learnToolAllowed(tool, true)).toBe(false);
      expect(learnToolAllowed(tool, false)).toBe(true);
    }
  });

  it("builds one Claude config for whichever built-in servers are attached", () => {
    expect(claudeBuiltinMcpConfig(null, null)).toBeUndefined();
    expect(JSON.parse(claudeBuiltinMcpConfig(canvas, null)!)).toEqual({ mcpServers: { loci_excalidraw: { type: "stdio", ...canvas } } });
    expect(JSON.parse(claudeBuiltinMcpConfig(null, learn)!)).toEqual({ mcpServers: { loci_learn: { type: "stdio", ...learn } } });
    expect(Object.keys(JSON.parse(claudeBuiltinMcpConfig(canvas, learn)!).mcpServers)).toEqual(["loci_excalidraw", "loci_learn"]);
  });

  it("routes Codex write approvals to Loci and forwards only the session credential", () => {
    const args = codexLearnMcpArgs(learn);
    expect(args.filter((_, index) => index % 2 === 0).every((flag) => flag === "-c")).toBe(true);
    expect(args).toContain('mcp_servers.loci_learn.env_vars=["LOCI_APP_ENDPOINT","LOCI_APP_TOKEN"]');
    expect(args.filter((arg) => arg.endsWith('approval_mode="prompt"')).map((arg) => arg.split(".")[3])).toEqual(["map_init", "map_sketch", "map_record", "revisit"]);
    const request = (serverName: string, tool: string) => ({ serverName, _meta: { codex_approval_kind: "mcp_tool_call" }, message: `Allow the ${serverName} MCP server to run tool "${tool}"?` });
    expect(codexLearnApprovalTool(request("loci_learn", "map_record"))).toBe("map_record");
    expect(codexLearnApprovalTool(request("other", "map_record"))).toBeUndefined();
    expect(codexLearnApprovalTool({ ...request("loci_learn", "map_record"), _meta: { codex_approval_kind: "other" } })).toBeUndefined();
  });
});
