import { loadNewAgentAccess, saveNewAgentAccess } from "../../features/agents/model/agentAccess";
import { RUNTIME_MODES, type RuntimeMode } from "../../features/sessions/model/session";
import { loadCanvasMcpEnabled, saveCanvasMcpEnabled } from "../../features/settings/model/builtinMcp";
import { defaultSessionChoice, loadLastModelChoice, modelsFor, preferredModelId, saveLastModelChoice } from "../../features/sessions/model/models";
import type { CommandContext } from "./context";
import { providerId } from "./mentors";
import { CommandError, field, type CommandDefinition } from "./registry";

type Setting = { help: string; get(): unknown; set(value: string): void };

/** The settings a terminal may read and change: the ones tests and external mentors need. */
const SETTINGS: Record<string, Setting> = {
  defaultProvider: {
    help: "The provider new conversations start with",
    get: () => defaultSessionChoice().harness,
    // As choosing a default in Settings → Providers does: with that provider's preferred model.
    set: (value) => { const harness = providerId(value); saveLastModelChoice(harness, preferredModelId(harness)); },
  },
  defaultModel: {
    help: "The model new conversations start with, for the default provider",
    get: () => defaultSessionChoice().model,
    set: (value) => {
      const harness = loadLastModelChoice()?.harness ?? defaultSessionChoice().harness;
      if (!modelsFor(harness).some((model) => model.id === value)) throw new CommandError(`Unknown model for ${harness}; run \`loci models list\``, "usage");
      saveLastModelChoice(harness, value);
    },
  },
  defaultMentorAccess: {
    help: `The permissions a new mentor starts with: ${RUNTIME_MODES.join(", ")}`,
    get: () => loadNewAgentAccess(),
    // As Settings → Mentors → New mentors does.
    set: (value) => {
      if (!RUNTIME_MODES.includes(value as RuntimeMode)) throw new CommandError(`defaultMentorAccess is one of: ${RUNTIME_MODES.join(", ")}`, "usage");
      saveNewAgentAccess(value as RuntimeMode);
    },
  },
  canvasTools: {
    help: "Whether agents get the built-in Excalidraw tools (true or false)",
    get: () => loadCanvasMcpEnabled(),
    set: (value) => {
      if (value !== "true" && value !== "false") throw new CommandError("canvasTools is true or false", "usage");
      saveCanvasMcpEnabled(value === "true");
    },
  },
};

const settingsView = () => Object.fromEntries(Object.entries(SETTINGS).map(([key, setting]) => [key, setting.get()]));

export const settingsCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "settings.get",
    summary: `App settings a terminal may read: ${Object.keys(SETTINGS).join(", ")}.`,
    fields: [field("key", "string", "One setting; all when left out", { positional: true })],
    callers: ["external"],
    run: async (_ctx, input) => {
      if (input.key === undefined) return settingsView();
      const setting = SETTINGS[input.key as string];
      if (!setting) throw new CommandError(`Unknown setting. Settings: ${Object.keys(SETTINGS).join(", ")}`, "usage");
      return { [input.key as string]: setting.get() };
    },
  },
  {
    name: "settings.set",
    summary: "Change one of those settings, as Settings does.",
    fields: [
      field("key", "string", Object.entries(SETTINGS).map(([key, setting]) => `${key}: ${setting.help}`).join("; "), { required: true, positional: true }),
      field("value", "string", "Its new value", { required: true, positional: true }),
    ],
    callers: ["external"],
    run: async (_ctx, input) => {
      const setting = SETTINGS[input.key as string];
      if (!setting) throw new CommandError(`Unknown setting. Settings: ${Object.keys(SETTINGS).join(", ")}`, "usage");
      setting.set(input.value as string);
      return { ...settingsView(), saved: true };
    },
  },
];
