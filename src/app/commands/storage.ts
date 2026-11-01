import { agentLook } from "../../features/agents/model/agent";
import { setAgentWorkdir } from "../../features/agents/model/agentWorkdir";
import { checkLibrary, exportMentor, importMentor, migrateStorage, reindexMentors, searchLibrary, storageStatus } from "../../features/agents/model/mentorStore";
import type { CommandContext } from "./context";
import { mentorField, resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition } from "./registry";

const ownMentor = field("mentor", "string", "The mentor, by id or name (a mentor's own turn: itself)", { max: 200 });

function absolute(value: unknown, name: string): string {
  if (typeof value !== "string" || !(value.startsWith("/") || value.startsWith("~/") || /^[A-Za-z]:[\\/]/.test(value)))
    throw new CommandError(`${name} must be an absolute path`, "usage");
  return value;
}

/** Mentors' folders: where they are, the 0.3 migration, the index, export and import. */
export const storageCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "storage.status",
    summary: "Where mentors' folders are (the mentors root), whether 0.3 data has moved into them, and how many files of each kind each mentor has.",
    fields: [],
    callers: ["external"],
    run: () => storageStatus(),
  },
  {
    name: "storage.migrate",
    summary: "Move 0.3 data into mentors' folders (Loci does this at start). Never changes the old data; a backup is made first. --dry-run only reports.",
    fields: [
      field("dryRun", "boolean", "Report what would be written, and write nothing"),
      field("redo", "string", "Run one mentor again, by id (its files that exist are kept)", { max: 200 }),
    ],
    callers: ["external"],
    run: (_ctx, input) => migrateStorage({ dryRun: input.dryRun === true, ...(typeof input.redo === "string" ? { redo: input.redo } : {}) }),
  },
  {
    name: "storage.reindex",
    summary: "Re-read mentors' folders (one, or all) after changes Loci did not see.",
    fields: [field("mentor", "string", "Only this mentor, by id or name", { max: 200 })],
    callers: ["external"],
    run: async (ctx, input, meta) => reindexMentors(input.mentor === undefined ? undefined : resolveMentor(ctx, input.mentor, meta).id),
  },
  {
    name: "library.check",
    summary: "Files in the mentor's folder that Loci could not read (bad front-matter or YAML, a missing sourceUrl, a file too large), with the reason. Run it after editing files directly.",
    fields: [ownMentor],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      return { mentor: agent.id, problems: await checkLibrary(agent.id) };
    },
  },
  {
    name: "library.search",
    summary: "Full-text search of the mentor's sources, guides and notes (titles of courses and drawings too). Any language; three or more characters search the text.",
    fields: [
      field("query", "string", "What to look for", { required: true, positional: true, max: 200 }),
      ownMentor,
      field("limit", "integer", "At most this many hits (default 20)"),
    ],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = meta.caller === "agent" || input.mentor !== undefined ? resolveMentor(ctx, input.mentor, meta) : undefined;
      const limit = typeof input.limit === "number" ? input.limit : undefined;
      return { hits: await searchLibrary(String(input.query), agent?.id, limit) };
    },
  },
  {
    name: "mentors.export",
    summary: "Zip a mentor's folder (library, courses, notes, drawings, Soul, memory, progress and highlights) to a file another Loci can import. repos/ and lab/ stay out unless --with-repos.",
    fields: [
      mentorField(true),
      field("out", "string", "Absolute path of the .zip to write", { required: true, max: 4096 }),
      field("withRepos", "boolean", "Include repos/ and lab/"),
    ],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      return exportMentor(agent.id, absolute(input.out, "out"), input.withRepos === true);
    },
  },
  {
    name: "mentors.import",
    summary: "Import a mentor from an exported .zip (--path), or bring back a mentor folder where it is (--folder), such as one kept after a reset or removal.",
    fields: [
      field("path", "string", "Absolute path of the .zip", { max: 4096 }),
      field("folder", "string", "Absolute path of a mentor folder (it holds mentor.json or mentor.removed.json)", { max: 4096 }),
    ],
    callers: ["external"],
    run: async (_ctx, input) => {
      if ((input.path === undefined) === (input.folder === undefined)) throw new CommandError("Give --path or --folder", "usage");
      return importMentor(input.path !== undefined ? { path: absolute(input.path, "path") } : { folder: absolute(input.folder, "folder") });
    },
  },
  {
    name: "mentors.relocate",
    summary: "Point a mentor's working folder somewhere else (--workdir), or back at its own mentor folder (no --workdir). Nothing is moved; a running chat keeps its folder until it is reset.",
    fields: [mentorField(true), field("workdir", "string", "Absolute path of the folder to work in", { max: 4096 })],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const target = input.workdir !== undefined ? absolute(input.workdir, "workdir") : agent.folder;
      if (!target) throw new CommandError(`${agentLook(agent).name} has no mentor folder yet; give --workdir`, "usage");
      return { mentor: agent.id, workdir: await setAgentWorkdir(agent.id, target), folder: agent.folder };
    },
  },
];
