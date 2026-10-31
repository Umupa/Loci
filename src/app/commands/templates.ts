import { AGENT_TEMPLATES } from "../../features/agents/templates";
import type { CommandContext } from "./context";
import type { CommandDefinition } from "./registry";

export const templateCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "templates.list",
    summary: "The mentor templates a new mentor can start from.",
    fields: [],
    callers: ["external"],
    run: async () => ({
      templates: AGENT_TEMPLATES.map(({ id, name, role, summary, avatar }) => ({ id, name, role, summary, avatar })),
    }),
  },
];
