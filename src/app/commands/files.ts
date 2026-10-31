import { agentFolders, type Agent } from "../../features/agents/model/agent";
import { ensureAgentWorkdir, folderHolds } from "../../features/agents/model/agentWorkdir";
import { basename, createPath, listDir, readTextFile, writeTextFile } from "../../platform/tauri/fs";
import { joinPath, parentPath } from "../../shared/lib/paths";
import type { CommandContext } from "./context";
import { mentorField, resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition } from "./registry";

const isAbsolute = (path: string) => path.startsWith("/") || /^[A-Za-z]:[\\/]/.test(path);

/**
 * A path in the mentor's files: relative to its working folder, or absolute
 * inside it or another folder it was given. Nothing outside them.
 */
export async function mentorPath(agent: Agent, path: string | undefined): Promise<string> {
  const workdir = agent.workdir ?? await ensureAgentWorkdir(agent.id);
  // `..` is resolved before the check, so it cannot climb out.
  const full = !path ? workdir
    : path.startsWith("/") ? joinPath("/", path)
    : isAbsolute(path) ? joinPath(path.slice(0, 2), path.slice(3))
    : joinPath(workdir, path);
  const roots = agentFolders({ ...agent, workdir });
  if (!roots.some((root) => root !== "~" && folderHolds(root, full)))
    throw new CommandError("That path is outside the mentor's working folder and the folders it was given", "usage");
  return full;
}

export const fileCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "files.list",
    summary: "What is in a folder of the mentor's files (its working folder when left out).",
    fields: [mentorField(), field("path", "string", "A folder, relative to the working folder", { positional: true, max: 4096 })],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const path = await mentorPath(agent, input.path as string | undefined);
      const entries = await listDir(path);
      return { path, entries: entries.map(({ name, path: entry, isDir }) => ({ name, path: entry, kind: isDir ? "folder" : "file" })) };
    },
  },
  {
    name: "files.read",
    summary: "One text file of the mentor's.",
    fields: [mentorField(), field("path", "string", "The file, relative to the working folder", { required: true, positional: true, max: 4096 })],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const path = await mentorPath(agent, input.path as string);
      return { path, text: await readTextFile(path) };
    },
  },
  {
    name: "files.write",
    summary: "Write a text file in the mentor's files, creating its folder; it replaces a file that is there.",
    fields: [
      mentorField(),
      field("path", "string", "The file, relative to the working folder", { required: true, positional: true, max: 4096 }),
      field("text", "string", "Its content (use --text-file)", { required: true, max: 250_000 }),
    ],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const path = await mentorPath(agent, input.path as string);
      if (!basename(path) || path === (agent.workdir ?? "")) throw new CommandError("Name a file", "usage");
      await ensureFolder(agent, parentPath(path));
      await writeTextFile(path, input.text as string);
      return { path, saved: true };
    },
  },
];

/** Creates the folders on the way to `folder`, inside the mentor's own. */
async function ensureFolder(agent: Agent, folder: string): Promise<void> {
  try {
    await listDir(folder);
    return;
  } catch {
    const parent = parentPath(folder);
    if (parent === folder) throw new CommandError(`Cannot create ${folder}`);
    await mentorPath(agent, parent);
    await ensureFolder(agent, parent);
    await createPath(parent, basename(folder), true);
  }
}
