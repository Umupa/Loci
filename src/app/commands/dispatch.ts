import type { CommandContext } from "./context";
import { COMMANDS } from "./index";
import { CommandError, validateInput, type CommandMeta } from "./registry";

/** Runs a command for a caller that may use it. */
export function runCommand(ctx: CommandContext, name: string, input: Record<string, unknown>, meta: CommandMeta): Promise<unknown> {
  const definition = COMMANDS.get(name);
  if (!definition || !definition.callers.includes(meta.caller))
    return Promise.reject(new CommandError(`Unknown command: ${name}`, "usage"));
  try {
    return definition.run(ctx, validateInput(definition, input), meta);
  } catch (error) {
    return Promise.reject(error);
  }
}

/** Whether a mentor's own `loci app` may call this command. */
export function isAgentCommand(name: string): boolean {
  return !!COMMANDS.get(name)?.callers.includes("agent");
}
