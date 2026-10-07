import { describe, expect, it } from "vitest";
import { canvasToolCall, canvasWorkSummary } from "./canvasToolCall";
import type { Block } from "./session";
import { workSummaryLine } from "./transcriptActivity";

const tool = (title: string, extra: Partial<NonNullable<Block["tool"]>> = {}, text = title): Block =>
  ({ id: title, role: "tool", text, tool: { title, status: "completed", ...extra } });
// As recorded from Claude Code and Codex sessions.
const claudeDraw = tool("mcp__loci_excalidraw__create_view", { kind: "mcp__loci_excalidraw__create_view", detail: '{"checkpointId":"1d42adc56e354c6ea3"}' });
const claudeReference = tool("Read mcp__loci_excalidraw__read_me", { kind: "read", detail: "# Excalidraw Element Format", preview: { kind: "read", title: "mcp__loci_excalidraw__read_me" } });
const claudeLookup = tool("Find select:mcp__loci_excalidraw__read_me", { kind: "search", preview: { kind: "search", query: "select:mcp__loci_excalidraw__read_me", title: "ToolSearch" } });
const codexDraw = tool("loci_excalidraw:create_view", { kind: "other", detail: 'Diagram displayed! Checkpoint id: "9f8e7d6c5b4a392817".\nIf user asks to create a new diagram - simply create a new one from scratch.' });

describe("Excalidraw MCP calls in a transcript", () => {
  it("names each call for what it does to the drawing, for either provider", () => {
    expect(canvasToolCall(claudeDraw)).toEqual({ tool: "create_view", ask: "Draw on the canvas", running: "Drawing on the canvas", done: "Drew on the canvas", checkpointId: "1d42adc56e354c6ea3" });
    expect(canvasToolCall(codexDraw)).toMatchObject({ tool: "create_view", checkpointId: "9f8e7d6c5b4a392817" });
    expect(canvasToolCall(claudeReference)).toMatchObject({ tool: "read_me", done: "Read the Excalidraw reference" });
    expect(canvasToolCall(tool("loci_excalidraw:read_widget_context", { kind: "other" }))).toMatchObject({ tool: "read_widget_context", running: "Reading the canvas" });
    expect(canvasToolCall({ ...claudeDraw, role: "approval" })).toMatchObject({ tool: "create_view" });
  });

  it("links a drawing call to its canvas only once the call returned a checkpoint", () => {
    expect(canvasToolCall(tool("mcp__loci_excalidraw__create_view", { status: "pending" }))?.checkpointId).toBeUndefined();
    expect(canvasToolCall(tool("mcp__loci_excalidraw__create_view", { status: "failed", detail: 'Checkpoint "abc" not found — it may have expired or never existed.' }))?.checkpointId).toBeUndefined();
    // A reference that mentions checkpoints is not a drawing.
    expect(canvasToolCall({ ...claudeReference, tool: { ...claudeReference.tool, detail: 'returns a `checkpointId`: "x"' } })?.checkpointId).toBeUndefined();
  });

  it("leaves other tools, other servers and prose alone", () => {
    for (const block of [claudeLookup, tool("Read notes/excalidraw.md", { kind: "read" }), tool("mcp__claude_ai_Excalidraw__create_view"),
      tool("github:create_view", { kind: "other" }), { id: "say", role: "assistant", text: "mcp__loci_excalidraw__create_view" } as Block])
      expect(canvasToolCall(block)).toBeUndefined();
  });

  it("titles a group of canvas calls instead of calling it a project search", () => {
    expect(workSummaryLine([claudeLookup, claudeReference], false)).toBe("Read the Excalidraw reference");
    expect(workSummaryLine([claudeLookup, claudeReference, claudeDraw], true)).toBe("Drawing on the canvas");
    expect(workSummaryLine([claudeDraw], false)).toBe("Drew on the canvas");
    expect(canvasWorkSummary([tool("loci_excalidraw:read_widget_context", { kind: "other" })], false)).toBe("Read the canvas");
    // Mixed work keeps the ordinary summary.
    expect(canvasWorkSummary([claudeDraw, tool("Read src/app.ts", { kind: "read" })], false)).toBeUndefined();
    expect(canvasWorkSummary([claudeLookup], false)).toBeUndefined();
    expect(canvasWorkSummary([claudeDraw, { id: "note", role: "system", text: "Compacted" }], false)).toBeUndefined();
  });
});


it("names existing-element edits and links their returned checkpoint", () => {
  const edit = tool("loci_excalidraw:update_elements", { kind: "other", detail: '{"checkpointId":"changed_1","updatedIds":["title"]}' });
  expect(canvasToolCall(edit)).toMatchObject({ tool: "update_elements", done: "Edited canvas elements", checkpointId: "changed_1" });
  expect(canvasWorkSummary([edit], true)).toBe("Editing canvas elements");
  expect(canvasWorkSummary([edit], false)).toBe("Edited canvas elements");
  expect(canvasToolCall(tool("loci_excalidraw:get_elements", { kind: "read" }))).toMatchObject({ tool: "get_elements", done: "Inspected canvas elements" });
});
