import { LEARN_MCP_NAME, learnMcpTool, type LearnMcpTool } from "../../learn/mcpServer";
import type { Block } from "./session";

export type LearnToolCall = {
  tool: LearnMcpTool;
  /** Imperative, present and past wording for the three states of a row. */
  ask: string;
  running: string;
  done: string;
};

const WORDING: Record<LearnMcpTool, [ask: string, running: string, done: string]> = {
  map_read: ["Read the learning map", "Reading the learning map", "Read the learning map"],
  map_init: ["Start the learning map", "Starting the learning map", "Started the learning map"],
  map_sketch: ["Sketch unexplored nodes", "Sketching unexplored nodes", "Sketched unexplored nodes"],
  map_record: ["Record on the learning map", "Recording on the learning map", "Recorded on the learning map"],
  revisit: ["Revisit a node", "Revisiting a node", "Revisited a node"],
};

/** A call to Loci's built-in learning MCP server, as Claude or Codex titles it. */
export function learnToolCall(block: Block): LearnToolCall | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  const tool =
    learnMcpTool(block.tool?.title) ??
    learnMcpTool(block.text) ??
    learnMcpTool(block.tool?.kind);
  if (!tool) return undefined;
  const [ask, running, done] = WORDING[tool];
  return { tool, ask, running, done };
}

/** Looking a deferred learning tool up is part of using it, not a project search. */
function isLearnToolLookup(block: Block): boolean {
  const query = block.tool?.preview?.query ?? block.tool?.title ?? block.text;
  return (
    block.role === "tool" &&
    new RegExp(`(?:^|\\s)select:mcp__${LEARN_MCP_NAME}__[a-z_,:]+$`).test(query?.trim() ?? "")
  );
}

/** A group of only learning calls is named for what it did to the map. */
export function learnWorkSummary(steps: Block[], live: boolean): string | undefined {
  if (steps.some((block) => block.role === "system")) return undefined;
  const tools = steps.filter((block) => block.role === "tool" || block.role === "approval");
  const calls = tools.flatMap((block) => learnToolCall(block) ?? []);
  if (calls.length === 0 || tools.some((block) => !learnToolCall(block) && !isLearnToolLookup(block))) return undefined;
  const did = (tool: LearnMcpTool) => calls.some((call) => call.tool === tool);
  if (did("revisit")) return live ? "Revisiting a node" : "Revisited a node";
  if (did("map_record")) return live ? "Recording on the learning map" : "Recorded on the learning map";
  if (did("map_init") || did("map_sketch")) return live ? "Updating the learning map" : "Updated the learning map";
  return live ? "Reading the learning map" : "Read the learning map";
}
