import { annotationCommands } from "./annotations";
import { codeCommands } from "./code";
import type { CommandContext } from "./context";
import { fileCommands } from "./files";
import { libraryCommands } from "./library";
import { mentorCommands } from "./mentors";
import { pathCommands } from "./path";
import { readerCommands } from "./reader";
import { settingsCommands } from "./settings";
import { sidebarCommands } from "./sidebar";
import { storageCommands } from "./storage";
import { updateCommands } from "./updates";
import { defineCommands } from "./registry";
import { templateCommands } from "./templates";

/** Every command, by name. Add a command to one of these lists, then run `npm run gen:cli`. */
export const COMMANDS = defineCommands<CommandContext>([
  ...templateCommands,
  ...mentorCommands,
  ...readerCommands,
  ...codeCommands,
  ...sidebarCommands,
  ...fileCommands,
  ...settingsCommands,
  ...libraryCommands,
  ...pathCommands,
  ...annotationCommands,
  ...updateCommands,
  ...storageCommands,
]);
