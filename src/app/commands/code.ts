import { agentFolders, type Agent } from "../../features/agents/model/agent";
import { ensureAgentWorkdir, folderHolds } from "../../features/agents/model/agentWorkdir";
import { formatCodeRef, parseCodeRef } from "../../features/learning/model/codeRef";
import { loadCourse, loadCourseSummaries } from "../../features/learning/model/course";
import { statFiles } from "../../platform/tauri/fs";
import { codeDefinition, codePinStatus, codeReferences, codeSymbols, readCode, resolveCommit, type CodeQuery } from "../../platform/tauri/code";
import { joinPath } from "../../shared/lib/paths";
import type { CommandContext } from "./context";
import { mentorField, resolveMentor } from "./mentor";
import { lineSpan } from "./reader";
import { CommandError, field, type CommandDefinition } from "./registry";

const isAbsolute = (path: string) => path.startsWith("/") || /^[A-Za-z]:[\\/]/.test(path);

/** Lines an excerpt or a read gives back at most. */
const READ_LINES_MAX = 2_000;
const PIN_EXCERPT_MAX = 120;

/** The folders a mentor's code commands may read: its folder of files, its workdir and the folders it was given. */
async function codeRoots(agent: Agent): Promise<string[]> {
  const workdir = agent.workdir ?? await ensureAgentWorkdir(agent.id);
  return [...new Set([...(agent.folder ? [agent.folder] : []), ...agentFolders({ ...agent, workdir })])].filter((root) => root !== "~");
}

/**
 * A file (or repository folder) a code command names: the pin shorthand
 * `repos/<repo>@<sha>:path`, a path relative to the mentor's folder (or its
 * workdir, where the folder does not hold it), or an absolute path inside
 * them. Anything outside is refused.
 */
export async function codeFile(agent: Agent, text: string): Promise<{ file: string; commit?: string; lines?: [number, number] }> {
  const ref = parseCodeRef(text);
  const roots = await codeRoots(agent);
  let file: string;
  if (isAbsolute(ref.path)) file = ref.path.startsWith("/") ? joinPath("/", ref.path) : joinPath(ref.path.slice(0, 2), ref.path.slice(3));
  else {
    const options = roots.map((root) => joinPath(root, ref.path));
    const stats = await statFiles(options).catch(() => []);
    file = options.find((option) => stats.some((stat) => stat.path === option && stat.mtimeMs !== null)) ?? options[0];
  }
  if (!file || !roots.some((root) => folderHolds(root, file)))
    throw new CommandError("That file is outside the mentor's folder, its working folder and the folders it was given", "usage");
  return { file, ...(ref.commit ? { commit: ref.commit } : {}), ...(ref.lines ? { lines: ref.lines } : {}) };
}

/** A path as a lesson file names it: relative to the mentor's folder when inside it. */
function lessonPath(agent: Agent, path: string): string {
  const base = agent.folder ?? agent.workdir;
  if (base && folderHolds(base, path) && path !== base) return path.slice(base.replace(/\/+$/, "").length + 1);
  return path;
}

const numbered = (text: string, first: number) =>
  text.split("\n").map((line, index) => `${first + index}\t${line}`).join("\n");

function slice(text: string, lines?: [number, number], max = READ_LINES_MAX): { first: number; last: number; total: number; text: string } {
  const all = text.endsWith("\n") ? text.slice(0, -1).split("\n") : text.split("\n");
  const first = Math.min(lines?.[0] ?? 1, Math.max(all.length, 1));
  const last = Math.min(lines?.[1] ?? all.length, all.length, first + max - 1);
  return { first, last, total: all.length, text: all.slice(first - 1, last).join("\n") };
}

const failed = (cause: unknown) => new CommandError(cause instanceof Error ? cause.message : String(cause), "failed");

const file = field("file", "string", "A file: repos/<repo>@<sha>:path (pinned), a path in the mentor's folder, or an absolute path inside its folders", { required: true, positional: true, max: 4096 });
const at = field("at", "string", "Read at this commit (default: the pin in --file, else the working tree)", { max: 64 });
const line = field("line", "integer", "A line (1-based) holding the name");
const column = field("column", "integer", "The column (1-based character) of the name on that line; default 1");
const name = field("name", "string", "The name itself, instead of --line/--column", { max: 200 });

async function navQuery(ctx: CommandContext, input: Record<string, unknown>, meta: Parameters<CommandDefinition<CommandContext>["run"]>[2]): Promise<CodeQuery> {
  const agent = resolveMentor(ctx, input.mentor, meta);
  const target = await codeFile(agent, input.file as string);
  if (input.line === undefined && input.name === undefined) throw new CommandError("Give --line (and --column) or --name", "usage");
  if (input.line !== undefined && (input.line as number) < 1) throw new CommandError("line starts at 1", "usage");
  const commit = (input.at as string | undefined) ?? target.commit;
  return {
    file: target.file,
    ...(commit ? { commit } : {}),
    ...(input.line !== undefined ? { line: input.line as number, column: (input.column as number | undefined) ?? 1 } : {}),
    ...(input.name !== undefined ? { name: input.name as string } : {}),
  };
}

export const codeCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "code.symbols",
    summary: "The outline of a source file (Go, Rust, C, TypeScript, JavaScript, Python): each definition's name, kind, lines and container.",
    fields: [mentorField(), file, at],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const target = await codeFile(agent, input.file as string);
      const commit = (input.at as string | undefined) ?? target.commit;
      const found = await codeSymbols(target.file, commit).catch((cause) => { throw failed(cause); });
      if (!found.language) throw new CommandError("Loci reads symbols in Go, Rust, C, TypeScript, JavaScript and Python files", "usage");
      return { file: target.file, ...(commit ? { commit } : {}), language: found.language, symbols: found.symbols };
    },
  },
  {
    name: "code.definition",
    summary: "Where a name is defined in the file's repository (by name, best first: the project before vendored code, the same file and folder first).",
    fields: [mentorField(), file, line, column, name, at],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const query = await navQuery(ctx, input, meta);
      return codeDefinition(query).catch((cause) => { throw failed(cause); });
    },
  },
  {
    name: "code.references",
    summary: "Where a name is used in the file's repository, matched by name (not resolved like a compiler). --file may be the repository folder with --name.",
    fields: [mentorField(), file, line, column, name, at, field("limit", "integer", "At most this many places (default and maximum 500)")],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const query = await navQuery(ctx, input, meta);
      if (input.limit !== undefined) query.limit = Math.max(1, Math.min(500, input.limit as number));
      return codeReferences(query).catch((cause) => { throw failed(cause); });
    },
  },
  {
    name: "code.read",
    summary: "A source file's lines, numbered, at a commit (a pin or --at) or as it is now, to check what a code-tour lesson shows.",
    fields: [mentorField(), file, at, field("lines", "string", "Lines to show: 12 or 12-40 (default: the range in --file, else all, up to 2000)")],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const target = await codeFile(agent, input.file as string);
      const commit = (input.at as string | undefined) ?? target.commit;
      const lines = input.lines !== undefined ? lineSpan(input.lines as string) : target.lines;
      const read = await readCode(target.file, commit).catch((cause) => { throw failed(cause); });
      const part = slice(read.text, lines);
      return {
        file: target.file,
        ...(read.commit ? { commit: read.commit } : {}),
        ...(read.head ? { head: read.head } : {}),
        lines: [part.first, part.last], totalLines: part.total,
        text: numbered(part.text, part.first),
      };
    },
  },
  {
    name: "code.pin",
    summary: "Pin lines of a file in a git checkout to a commit (HEAD unless --at): gives the repos/<repo>@<sha>:path#L… string for a lesson's file, and the excerpt.",
    fields: [mentorField(), file, field("lines", "string", "The lines the lesson shows: 12 or 12-40 (default: the range in --file)"), at],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const target = await codeFile(agent, input.file as string);
      const lines = input.lines !== undefined ? lineSpan(input.lines as string) : target.lines;
      const rev = (input.at as string | undefined) ?? target.commit;
      const resolved = await resolveCommit(target.file, rev).catch((cause) => { throw failed(cause); });
      const read = await readCode(target.file, resolved.commit).catch((cause) => { throw failed(cause); });
      const part = slice(read.text, lines, PIN_EXCERPT_MAX);
      if (lines && lines[0] > part.total) throw new CommandError(`The file has ${part.total} lines at that commit`, "usage");
      const shown: [number, number] | undefined = lines ? [lines[0], Math.min(lines[1], part.total)] : undefined;
      return {
        ref: formatCodeRef(lessonPath(agent, resolved.repoRoot), resolved.commit, resolved.pathInRepo, shown),
        file: target.file, commit: resolved.commit, ...(shown ? { lines: shown } : {}),
        excerpt: numbered(part.text, part.first),
        ...(part.last - part.first + 1 < (shown ? shown[1] - shown[0] + 1 : part.total) ? { excerptTruncated: true } : {}),
      };
    },
  },
  {
    name: "code.pins",
    summary: "Every pinned code lesson of the mentor's courses and how it stands: current, moved (HEAD moved, file unchanged), changed (with where the lines are now), missing-commit, missing-file.",
    fields: [mentorField(), field("course", "string", "Only this course", { max: 200 })],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const ids = input.course !== undefined ? [input.course as string]
        : (await loadCourseSummaries()).filter((entry) => entry.agentId === agent.id).map((entry) => entry.id);
      const pins: Record<string, unknown>[] = [];
      for (const id of ids) {
        const course = await loadCourse(id, agent.id);
        if (!course) {
          if (input.course !== undefined) throw new CommandError(`No course ${id} for this mentor`, "not_found");
          continue;
        }
        if (course.data.engine !== "reading") continue;
        for (const lesson of course.data.chapters.flatMap((chapter) => chapter.lessons)) {
          if (!lesson.file || !lesson.commit) continue;
          const status = await codePinStatus(lesson.file, lesson.commit, lesson.lines).catch((cause: unknown) => ({ state: "error", error: String(cause) }));
          pins.push({ course: id, lesson: lesson.id, title: lesson.title, file: lessonPath(agent, lesson.file), pin: lesson.commit, ...(lesson.lines ? { lines: lesson.lines } : {}), ...status });
        }
      }
      return { pins, stale: pins.filter((pin) => pin.state !== "current" && pin.state !== "moved").length };
    },
  },
];
