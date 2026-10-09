import { CANVAS_MCP_NAME, canvasMcpTool, isCanvasWriteTool, type CanvasMcpTool } from "../../canvas/mcpServer";
import { blockShellCommand, builtinCliCall } from "./builtinCli";
import type { Block } from "./session";

export type CanvasToolCall = {
  tool: CanvasMcpTool;
  /** Imperative, present and past wording for the three states of a row. */
  ask: string;
  running: string;
  done: string;
  /** The checkpoint a finished drawing call returned; it names the canvas. */
  checkpointId?: string;
};

const WORDING: Record<CanvasMcpTool, [ask: string, running: string, done: string]> = {
  read_me: ["Read the Excalidraw reference", "Reading the Excalidraw reference", "Read the Excalidraw reference"],
  create_view: ["Draw on the canvas", "Drawing on the canvas", "Drew on the canvas"],
  read_widget_context: ["Read the canvas", "Reading the canvas", "Read the canvas"],
  get_elements: ["Inspect canvas elements", "Inspecting canvas elements", "Inspected canvas elements"],
  update_elements: ["Edit canvas elements", "Editing canvas elements", "Edited canvas elements"],
};

/** The canvas tool a shell row ran through the app's CLI, for agents without the MCP server. */
function canvasCliTool(block: Block): CanvasMcpTool | undefined {
  const call = builtinCliCall(blockShellCommand(block));
  return call?.namespace === "canvas" && call.tool !== "help" ? call.tool : undefined;
}

/** A call to Loci's built-in Excalidraw server: an MCP tool as Claude or Codex titles it, or the app's CLI. */
export function canvasToolCall(block: Block): CanvasToolCall | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  const tool =
    canvasMcpTool(block.tool?.title) ??
    canvasMcpTool(block.text) ??
    canvasMcpTool(block.tool?.kind) ??
    canvasCliTool(block);
  if (!tool) return undefined;
  const [ask, running, done] = WORDING[tool];
  // Claude reports the structured result, Codex and the CLI the server's sentence.
  const checkpointId =
    isCanvasWriteTool(tool)
      ? block.tool?.detail?.match(
          /checkpoint ?id\\?"?\s*:\s*\\?"([A-Za-z0-9_-]{1,128})\\?"/i,
        )?.[1]
      : undefined;
  return { tool, ask, running, done, ...(checkpointId ? { checkpointId } : {}) };
}

/** Looking a deferred canvas tool up, or listing the CLI's tools, is part of using it, not a project search. */
function isCanvasToolLookup(block: Block): boolean {
  const query = block.tool?.preview?.query ?? block.tool?.title ?? block.text;
  if (block.role === "tool" && new RegExp(`(?:^|\\s)select:mcp__${CANVAS_MCP_NAME}__[a-z_,:]+$`).test(query?.trim() ?? "")) return true;
  const call = builtinCliCall(blockShellCommand(block));
  return call?.namespace === "canvas" && call.tool === "help";
}

/** A group of only canvas calls is named for what it did to the drawing. */
export function canvasWorkSummary(
  steps: Block[],
  live: boolean,
): string | undefined {
  if (steps.some((block) => block.role === "system")) return undefined;
  const tools = steps.filter(
    (block) => block.role === "tool" || block.role === "approval",
  );
  const calls = tools.flatMap((block) => canvasToolCall(block) ?? []);
  if (
    calls.length === 0 ||
    tools.some((block) => !canvasToolCall(block) && !isCanvasToolLookup(block))
  ) {
    return undefined;
  }
  const drew = calls.some((call) => call.tool === "create_view");
  if (drew) return live ? "Drawing on the canvas" : "Drew on the canvas";
  if (calls.some(call => call.tool === "update_elements")) return live ? "Editing canvas elements" : "Edited canvas elements";
  return calls.every((call) => call.tool === "read_me")
    ? live ? "Reading the Excalidraw reference" : "Read the Excalidraw reference"
    : live ? "Reading the canvas" : "Read the canvas";
}
