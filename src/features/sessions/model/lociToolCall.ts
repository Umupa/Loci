import { builtinCliCall } from "./builtinCli";
import type { Block } from "./session";
import { shellWords } from "./shellWords";

export type LociToolCall = {
  action: string;
  label: string;
  command: string;
};

const ACTION_LABELS: Record<string, string> = {
  "models.list": "List models",
  "sessions.list": "List sessions",
  "sessions.read": "Read a session",
  "sessions.send": "Continue a session",
  "sessions.draft": "Save a draft",
  "sessions.start": "Start a session",
  "folders.list": "List folders",
  "folders.move": "Move a session",
  "notes.list": "List notes",
  "notes.read": "Read a note",
  "notes.write": "Write a note",
  "canvas.list": "List canvases",
  "canvas.get": "Get a canvas",
  "canvas.create": "Create a canvas",
  "canvas.rename": "Rename a canvas",
  "canvas.delete": "Delete a canvas",
  "canvas.read-data": "Read canvas scene data",
  "canvas.write-data": "Write canvas scene data",
};

/** Recognize the actual app CLI command, not a mention of it in prose/output. */
export function lociToolCall(block: Block): LociToolCall | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  // A shell preview retains the original command when the display title was
  // simplified. Never accept a shorter title in place of that command.
  const candidate =
    (block.tool?.preview?.kind === "shell"
      ? block.tool.preview.title
      : undefined) ??
    block.tool?.title ??
    block.text;
  const command = candidate?.trim().replace(/^Run(?:ning)?\s+command:\s*/i, "");
  if (!command) return undefined;
  const words = shellWords(command);
  if (!words || !/(?:^|[/\\])loci(?:\.exe)?$/i.test(words[0] ?? ""))
    return undefined;
  // Asking which canvas or learning tools exist; a call of one is named by
  // canvasToolCall or learnToolCall for what it does.
  const builtin = builtinCliCall(command);
  if (builtin?.tool === "help") {
    return {
      action: "--help",
      label: builtin.namespace === "learn" ? "View learning tools" : "View canvas tools",
      command,
    };
  }
  if (words[1] !== "app") return undefined;
  const action = words[2] ?? "--help";
  if (action === "--help" || action === "help" || action === "-h") {
    return words.length > 3
      ? undefined
      : { action: "--help", label: "View CLI commands", command };
  }
  if (!Object.prototype.hasOwnProperty.call(ACTION_LABELS, action))
    return undefined;
  for (let index = 3; index < words.length; index += 2) {
    if (
      !["--json", "--input", "--request-id"].includes(words[index]) ||
      !words[index + 1]
    )
      return undefined;
  }
  return { action, label: ACTION_LABELS[action], command };
}

/** A group of only Loci calls can be named for the app, not the shell. */
export function lociWorkSummary(
  steps: Block[],
  live: boolean,
): string | undefined {
  if (steps.some((block) => block.role === "system")) {
    return undefined;
  }
  const calls = steps.filter(
    (block) => block.role === "tool" || block.role === "approval",
  );
  if (calls.length === 0 || calls.some((block) => !lociToolCall(block))) {
    return undefined;
  }
  return live ? "Using Loci" : "Used Loci";
}
