import { invoke } from "@tauri-apps/api/core";
import {
  CANVAS_MCP_TOOLS,
  canvasToolAutoAllowed,
  isCanvasWriteTool,
  type CanvasMcpTool,
} from "../../canvas/mcpServer";
import type { Block, HarnessId, RuntimeMode } from "./session";
import { shellWords } from "./shellWords";

/**
 * Agent CLIs that cannot be handed an MCP server for one session without
 * editing the user's own configuration. They reach Loci's built-in canvas
 * tools by running the app's CLI (`loci canvas …`),
 * which starts the same servers for one call. A prompt tells them it exists.
 */
export const BUILTIN_CLI_HARNESSES: readonly HarnessId[] = ["antigravity", "pi"];

export function usesBuiltinCli(harness: HarnessId | undefined): boolean {
  return harness != null && BUILTIN_CLI_HARNESSES.includes(harness);
}

/** This app's executable, which is also its CLI. Undefined when it cannot be asked, as outside the desktop app. */
export async function appCliPath(): Promise<string | undefined> {
  try {
    const path = await invoke<string>("app_cli_path");
    return typeof path === "string" && path ? path : undefined;
  } catch { return undefined; }
}

/** One call of a built-in tool through the app's CLI. `help` lists the tools. */
export type BuiltinCliCall = { namespace: "canvas"; tool: CanvasMcpTool | "help" };

const HELP: readonly string[] = ["help", "--help", "-h"];

/**
 * Recognize a shell command that is exactly one built-in tool call: the CLI,
 * the server, a tool it has, and at most one input. Anything a shell would
 * expand, chain or redirect is not recognized, so the command can be trusted
 * to do what it says. With `cliPath` the program must be this app's own
 * executable; without it any `loci` is taken, which is only good for naming a
 * row in the transcript.
 */
export function builtinCliCall(command: string | undefined, cliPath?: string): BuiltinCliCall | undefined {
  const words = command ? shellWords(command.trim()) : undefined;
  if (!words) return undefined;
  const [program, namespace, name, ...rest] = words;
  if (cliPath ? program !== cliPath : !/(?:^|[/\\])loci(?:\.exe)?$/i.test(program ?? "")) return undefined;
  if (namespace !== "canvas") return undefined;
  if (name === undefined || HELP.includes(name)) return rest.length === 0 ? { namespace, tool: "help" } : undefined;
  const asksHelp = rest.length === 1 && HELP.includes(rest[0]);
  const oneInput = rest.length === 2 && (rest[0] === "--json" || rest[0] === "--input");
  if (rest.length !== 0 && !asksHelp && !oneInput) return undefined;
  const tool = CANVAS_MCP_TOOLS.find((known) => known === name);
  return tool ? { namespace, tool: asksHelp ? "help" : tool } : undefined;
}

/**
 * How Loci answers a permission request for a built-in tool call without
 * asking, with the rules the MCP tools follow: reading never asks, drawing
 * asks in Supervised, and a plan turn may only
 * read. Undefined leaves the request to the user.
 */
export function builtinCliDecision(call: BuiltinCliCall, runtimeMode: RuntimeMode, planning: boolean): "allow" | "deny" | undefined {
  if (call.tool === "help") return "allow";
  if (planning) return isCanvasWriteTool(call.tool) ? "deny" : "allow";
  return canvasToolAutoAllowed(call.tool, runtimeMode) ? "allow" : undefined;
}

/** The shell command a tool or approval row stands for, as the provider reported it. */
export function blockShellCommand(block: Block): string | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  // A shell preview retains the original command when the display title was
  // simplified. Never accept a shorter title in place of that command.
  const candidate =
    (block.tool?.preview?.kind === "shell" ? block.tool.preview.title : undefined) ??
    block.tool?.title ??
    block.text;
  return candidate?.trim().replace(/^Run(?:ning)?\s+command:\s*/i, "") || undefined;
}

/**
 * Tells an agent that this project's canvases are within reach, and how.
 * `cli` is the app's executable, quoted for the agent's shell. An agent with
 * the MCP server attached learns the same from the tool descriptions.
 */
export function canvasCliPrompt(cli: string): string {
  return `

<loci_canvas>
Loci canvas access: \`${cli} canvas TOOL --json '<arguments>'\`, or --input FILE for file input.
Tools: read_me (element format), create_view (create or extend a drawing), read_widget_context (drawing context), get_elements and update_elements (elements by id).
Argument reference: \`${cli} canvas --help\`.
Access is available during this session's turn through a credential supplied in its environment.
</loci_canvas>`;
}
