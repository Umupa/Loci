import { checkForUpdateNow } from "../../features/updates/model/updates";
import type { CommandContext } from "./context";
import { CommandError, type CommandDefinition } from "./registry";

/** Whether a newer release exists, without opening the prompt, for tests. */
export const updateCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "updates.check",
    summary: "Ask GitHub Releases whether a newer Loci is available: {available, version, current}.",
    fields: [],
    callers: ["external"],
    run: async () => {
      try {
        return await checkForUpdateNow();
      } catch (error) {
        throw new CommandError(`Could not check for updates: ${error instanceof Error ? error.message : String(error)}`);
      }
    },
  },
];
