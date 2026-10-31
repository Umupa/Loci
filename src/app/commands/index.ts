import type { CommandContext } from "./context";
import { fileCommands } from "./files";
import { libraryCommands } from "./library";
import { mentorCommands } from "./mentors";
import { readerCommands } from "./reader";
import { settingsCommands } from "./settings";
import { sidebarCommands } from "./sidebar";
import { defineCommands } from "./registry";
import { templateCommands } from "./templates";

/** Every command, by name. Add a command to one of these lists, then run `npm run gen:cli`. */
export const COMMANDS = defineCommands<CommandContext>([
  ...templateCommands,
  ...mentorCommands,
  ...readerCommands,
  ...sidebarCommands,
  ...fileCommands,
  ...settingsCommands,
  ...libraryCommands,
]);
