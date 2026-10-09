import { describe, expect, it } from "vitest";
import { learnToolCall, learnWorkSummary } from "./learnToolCall";
import type { Block } from "./session";
import { toolCallLabel, workSummaryLine } from "./transcriptActivity";

const tool = (title: string, extra: Partial<NonNullable<Block["tool"]>> = {}, text = title): Block =>
  ({ id: title, role: "tool", text, tool: { title, status: "completed", ...extra } });
// As recorded from Claude Code and Codex sessions.
const claudeRead = tool("Read mcp__loci_learn__map_read", { kind: "read", detail: '{"exists":false}', preview: { kind: "read", title: "mcp__loci_learn__map_read" } });
const claudeRecord = tool("mcp__loci_learn__map_record", { kind: "mcp__loci_learn__map_record", detail: '{"saved":true}' });
const claudeLookup = tool(
  "Find select:mcp__loci_learn__map_read,mcp__loci_learn__map_init,mcp__loci_learn__map_record,mcp__loci_learn__map_sketch,mcp__loci_learn__revisit",
  { kind: "search", preview: { kind: "search", query: "select:mcp__loci_learn__map_read,mcp__loci_learn__map_init,mcp__loci_learn__map_record,mcp__loci_learn__map_sketch,mcp__loci_learn__revisit", title: "ToolSearch" } },
);
const codexRecord = tool("loci_learn:map_record", { kind: "other" });
const codexRevisit = tool("loci_learn:revisit", { kind: "other" });

describe("learning map calls in a transcript", () => {
  it("names each call for what it does to the map, for either provider", () => {
    expect(learnToolCall(claudeRecord)).toEqual({ tool: "map_record", ask: "Record on the learning map", running: "Recording on the learning map", done: "Recorded on the learning map" });
    expect(learnToolCall(codexRecord)).toMatchObject({ tool: "map_record" });
    expect(learnToolCall(claudeRead)).toMatchObject({ tool: "map_read", done: "Read the learning map" });
    expect(learnToolCall(codexRevisit)).toMatchObject({ tool: "revisit", running: "Revisiting a node" });
    expect(learnToolCall({ ...claudeRecord, role: "approval" })).toMatchObject({ tool: "map_record" });
    // Elsewhere a call is labeled the same way, rather than by its raw tool name.
    expect(toolCallLabel(claudeRecord)).toBe("Record on the learning map");
  });

  it("leaves other tools, other servers and prose alone", () => {
    for (const block of [claudeLookup, tool("Read notes/learn.md", { kind: "read" }), tool("mcp__loci_excalidraw__create_view"),
      tool("mcp__other__map_record"), tool("loci_learn:delete_everything", { kind: "other" }), { id: "say", role: "assistant", text: "mcp__loci_learn__map_record" } as Block])
      expect(learnToolCall(block)).toBeUndefined();
  });

  it("titles a group of learning calls instead of calling it a project search", () => {
    expect(workSummaryLine([claudeLookup, claudeRead], false)).toBe("Read the learning map");
    expect(workSummaryLine([claudeLookup, claudeRead, claudeRecord], true)).toBe("Recording on the learning map");
    expect(workSummaryLine([claudeRecord], false)).toBe("Recorded on the learning map");
    expect(learnWorkSummary([codexRevisit], false)).toBe("Revisited a node");
    expect(learnWorkSummary([tool("loci_learn:map_sketch", { kind: "other" })], true)).toBe("Updating the learning map");
    expect(learnWorkSummary([tool("loci_learn:map_init", { kind: "other" })], false)).toBe("Updated the learning map");
    // A revisit outranks a record in the same group, which outranks a read.
    expect(learnWorkSummary([claudeRead, codexRecord, codexRevisit], false)).toBe("Revisited a node");
    // Mixed work keeps the ordinary summary.
    expect(learnWorkSummary([claudeRecord, tool("Read src/app.ts", { kind: "read" })], false)).toBeUndefined();
    expect(learnWorkSummary([claudeLookup], false)).toBeUndefined();
    expect(learnWorkSummary([claudeRecord, { id: "note", role: "system", text: "Compacted" }], false)).toBeUndefined();
  });
});

describe("learning map calls through the app's CLI", () => {
  // As an agent without the MCP server runs them: a shell row holding the command.
  const shell = (command: string, extra: Partial<NonNullable<Block["tool"]>> = {}): Block =>
    tool(command, { kind: "execute", preview: { kind: "shell", title: command }, ...extra });
  const cli = "/Applications/Loci.app/Contents/MacOS/loci";
  const read = shell(`${cli} learn map_read`);
  const record = shell(`${cli} learn map_record --input /tmp/record.json`);
  const help = shell(`${cli} learn --help`);

  it("reads as the same learning work as a call over MCP", () => {
    expect(learnToolCall(record)).toEqual({ tool: "map_record", ask: "Record on the learning map", running: "Recording on the learning map", done: "Recorded on the learning map" });
    expect(learnToolCall(read)).toMatchObject({ tool: "map_read" });
    expect(learnToolCall(shell(`'${cli}' learn revisit --json '{"phase":"start","nodeId":"n1"}'`))).toMatchObject({ tool: "revisit" });
    expect(learnToolCall({ ...record, role: "approval" })).toMatchObject({ tool: "map_record" });
    expect(toolCallLabel(record)).toBe("Record on the learning map");
  });

  it("leaves compound commands, other servers and unknown tools to the shell row", () => {
    for (const command of [`${cli} learn map_read && cat notes.md`, `${cli} canvas read_me`, `${cli} learn delete_everything`, `echo ${cli} learn map_read`])
      expect(learnToolCall(shell(command)), command).toBeUndefined();
    expect(learnToolCall(help)).toBeUndefined();
  });

  it("titles the group for the map, counting a look at the tool list as part of it", () => {
    expect(workSummaryLine([help, read], false)).toBe("Read the learning map");
    expect(workSummaryLine([help, read, record], true)).toBe("Recording on the learning map");
    expect(learnWorkSummary([read, shell("ls sources/")], false)).toBeUndefined();
  });
});
