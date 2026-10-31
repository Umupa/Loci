/**
 * Loci's command layer. Every command the `loci` CLI offers is defined here
 * once: its name, its fields and the function it runs, which is the same
 * function the UI calls. The CLI learns the commands from a manifest that is
 * generated from these definitions (`npm run gen:cli`), so adding a command
 * means adding one definition.
 */

export type FieldType = "string" | "integer" | "boolean" | "json";

export type CommandField = {
  name: string;
  type: FieldType;
  help: string;
  required?: boolean;
  /** Taken from the command line in order, before the flags. */
  positional?: boolean;
  /** The longest string accepted. */
  max?: number;
};

/** Who is calling: a terminal outside Loci, or a mentor's own turn inside it. */
export type CallerKind = "external" | "agent";

export type CommandMeta = {
  requestId: string;
  caller: CallerKind;
  /** The mentor whose own turn made the call. */
  agentId?: string;
};

export type CommandErrorCode =
  | "usage"
  | "not_found"
  | "busy"
  | "failed"
  | "declined"
  | "needs_you"
  | "timeout";

/** A refusal with a stable code; the CLI turns the code into its exit status. */
export class CommandError extends Error {
  constructor(message: string, readonly code: CommandErrorCode = "failed") {
    super(message);
    this.name = "CommandError";
  }
}

export type CommandDefinition<C> = {
  /** `<noun>.<verb>`; the CLI spells it `loci <noun> <verb>`. */
  name: string;
  summary: string;
  fields: readonly CommandField[];
  callers: readonly CallerKind[];
  /** Removes something the user cannot get back. */
  destructive?: boolean;
  run(ctx: C, input: Record<string, unknown>, meta: CommandMeta): Promise<unknown>;
};

const NAME = /^[a-z][a-z-]*\.[a-z][a-z-]*$/;
const FIELD = /^[a-z][A-Za-z0-9]*$/;

export function field(
  name: string,
  type: FieldType,
  help: string,
  options: Pick<CommandField, "required" | "positional" | "max"> = {},
): CommandField {
  return { name, type, help, ...options };
}

/** Checks the definitions once, so a mistake fails the tests rather than a call. */
export function defineCommands<C>(definitions: readonly CommandDefinition<C>[]): ReadonlyMap<string, CommandDefinition<C>> {
  const map = new Map<string, CommandDefinition<C>>();
  for (const definition of definitions) {
    if (!NAME.test(definition.name)) throw new Error(`Invalid command name: ${definition.name}`);
    if (map.has(definition.name)) throw new Error(`Duplicate command: ${definition.name}`);
    if (!definition.callers.length) throw new Error(`${definition.name} has no callers`);
    const names = new Set<string>();
    let optionalPositional = false;
    for (const entry of definition.fields) {
      if (!FIELD.test(entry.name)) throw new Error(`Invalid field ${definition.name}.${entry.name}`);
      if (names.has(entry.name)) throw new Error(`Duplicate field ${definition.name}.${entry.name}`);
      names.add(entry.name);
      if (entry.positional) {
        if (entry.type === "boolean") throw new Error(`${definition.name}.${entry.name}: a positional field cannot be a boolean`);
        if (entry.required && optionalPositional) throw new Error(`${definition.name}.${entry.name}: a required positional field follows an optional one`);
        if (!entry.required) optionalPositional = true;
      }
    }
    map.set(definition.name, definition);
  }
  return map;
}

/** The input as the command expects it, or a usage error naming what is wrong. */
export function validateInput(definition: CommandDefinition<unknown>, input: Record<string, unknown>): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new CommandError("Input must be a JSON object", "usage");
  const known = new Map(definition.fields.map((entry) => [entry.name, entry]));
  const unknown = Object.keys(input).filter((key) => !known.has(key));
  if (unknown.length) throw new CommandError(`Unknown ${definition.name} fields: ${unknown.join(", ")}`, "usage");
  for (const entry of definition.fields) {
    const value = input[entry.name];
    if (value === undefined || value === null) {
      if (entry.required) throw new CommandError(`${entry.name} is required`, "usage");
      continue;
    }
    if (entry.type === "string") {
      if (typeof value !== "string") throw new CommandError(`${entry.name} must be a string`, "usage");
      if (entry.required && !value.trim()) throw new CommandError(`${entry.name} must not be empty`, "usage");
      if (value.length > (entry.max ?? 30_000)) throw new CommandError(`${entry.name} is too long`, "usage");
    } else if (entry.type === "integer") {
      if (!Number.isInteger(value)) throw new CommandError(`${entry.name} must be an integer`, "usage");
    } else if (entry.type === "boolean") {
      if (typeof value !== "boolean") throw new CommandError(`${entry.name} must be true or false`, "usage");
    }
  }
  return Object.fromEntries(Object.entries(input).filter(([, value]) => value !== undefined && value !== null));
}

export type CommandManifest = {
  version: 1;
  commands: {
    name: string;
    summary: string;
    callers: CallerKind[];
    destructive: boolean;
    fields: { name: string; type: FieldType; help: string; required: boolean; positional: boolean }[];
  }[];
};

/** What the CLI needs to parse arguments and print help without the app running. */
export function commandManifest(definitions: Iterable<CommandDefinition<unknown>>): CommandManifest {
  return {
    version: 1,
    commands: [...definitions]
      .sort((a, b) => a.name.localeCompare(b.name))
      .map((definition) => ({
        name: definition.name,
        summary: definition.summary,
        callers: [...definition.callers],
        destructive: !!definition.destructive,
        fields: definition.fields.map((entry) => ({
          name: entry.name,
          type: entry.type,
          help: entry.help,
          required: !!entry.required,
          positional: !!entry.positional,
        })),
      })),
  };
}

/** The message and code a failed command reports. */
export function commandFailure(error: unknown): { error: string; code: CommandErrorCode } {
  if (error instanceof CommandError) return { error: error.message, code: error.code };
  return { error: error instanceof Error ? error.message : String(error), code: "failed" };
}
