import { canvasMcpTool, type CanvasMcpTool } from "../../canvas/mcpServer";
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
};

/** A call to Loci's built-in Excalidraw MCP server, as Claude or Codex titles it. */
export function canvasToolCall(block: Block): CanvasToolCall | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  const tool =
    canvasMcpTool(block.tool?.title) ??
    canvasMcpTool(block.text) ??
    canvasMcpTool(block.tool?.kind);
  if (!tool) return undefined;
  const [ask, running, done] = WORDING[tool];
  // Claude reports the structured result, Codex the server's sentence.
  const checkpointId =
    tool === "create_view"
      ? block.tool?.detail?.match(
          /checkpoint ?id\\?"?\s*:\s*\\?"([A-Za-z0-9_-]{1,128})\\?"/i,
        )?.[1]
      : undefined;
  return { tool, ask, running, done, ...(checkpointId ? { checkpointId } : {}) };
}

/** Looking a deferred canvas tool up is part of using it, not a project search. */
function isCanvasToolLookup(block: Block): boolean {
  const query = block.tool?.preview?.query ?? block.tool?.title ?? block.text;
  return (
    block.role === "tool" &&
    /(?:^|\s)select:mcp__excalidraw__[a-z_,:]+$/.test(query?.trim() ?? "")
  );
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
  return calls.every((call) => call.tool === "read_me")
    ? live ? "Reading the Excalidraw reference" : "Read the Excalidraw reference"
    : live ? "Reading the canvas" : "Read the canvas";
}
