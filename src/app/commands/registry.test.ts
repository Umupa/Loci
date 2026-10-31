import { describe, expect, it } from "vitest";
import { CommandError, commandFailure, commandManifest, defineCommands, field, validateInput, type CommandDefinition } from "./registry";

const run = async () => null;
const command = (overrides: Partial<CommandDefinition<unknown>> = {}): CommandDefinition<unknown> => ({
  name: "things.make", summary: "Make a thing.", callers: ["external"], run,
  fields: [field("name", "string", "Its name", { required: true, positional: true }), field("count", "integer", "How many"), field("loud", "boolean", "Shout")],
  ...overrides,
});

describe("command definitions", () => {
  it("reject bad names, duplicates and ambiguous positionals", () => {
    expect(() => defineCommands([command({ name: "Bad" })])).toThrow(/Invalid command name/);
    expect(() => defineCommands([command(), command()])).toThrow(/Duplicate command/);
    expect(() => defineCommands([command({ callers: [] })])).toThrow(/no callers/);
    expect(() => defineCommands([command({ fields: [field("a", "string", "", { positional: true }), field("b", "string", "", { positional: true, required: true })] })])).toThrow(/follows an optional/);
    expect(() => defineCommands([command({ fields: [field("flag", "boolean", "", { positional: true })] })])).toThrow(/boolean/);
  });

  it("validate input against the fields", () => {
    const definition = command();
    expect(validateInput(definition, { name: "x", count: 2, loud: true })).toEqual({ name: "x", count: 2, loud: true });
    expect(validateInput(definition, { name: "x", count: null })).toEqual({ name: "x" });
    const usage = (input: Record<string, unknown>) => { try { validateInput(definition, input); } catch (error) { return commandFailure(error); } return null; };
    expect(usage({})).toEqual({ error: "name is required", code: "usage" });
    expect(usage({ name: " " })?.code).toBe("usage");
    expect(usage({ name: "x", count: 1.5 })?.error).toBe("count must be an integer");
    expect(usage({ name: "x", loud: "yes" })?.error).toBe("loud must be true or false");
    expect(usage({ name: "x", other: 1 })?.error).toBe("Unknown things.make fields: other");
  });

  it("describe themselves for the CLI", () => {
    const manifest = commandManifest(defineCommands([command({ destructive: true })]).values());
    expect(manifest.commands[0]).toMatchObject({ name: "things.make", destructive: true, callers: ["external"] });
    expect(manifest.commands[0].fields[0]).toEqual({ name: "name", type: "string", help: "Its name", required: true, positional: true });
  });

  it("report coded and uncoded failures", () => {
    expect(commandFailure(new CommandError("Gone", "not_found"))).toEqual({ error: "Gone", code: "not_found" });
    expect(commandFailure(new Error("Boom"))).toEqual({ error: "Boom", code: "failed" });
    expect(commandFailure("plain")).toEqual({ error: "plain", code: "failed" });
  });
});
