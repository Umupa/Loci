// Reads a file at a commit from the repository that holds it, for checking a
// pinned code lesson's line range at the commit it was written against. Pure
// filesystem and git; the evaluation calls it through a cached wrapper.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";

/** The absolute path of `file` when it is relative to one of `roots`. */
export function absoluteInRoots(file, roots = []) {
  if (file.startsWith("/") || /^[A-Za-z]:[\\/]/.test(file)) return file;
  for (const root of roots) {
    const candidate = `${root.replace(/\/+$/, "")}/${file}`;
    if (existsSync(candidate)) return candidate;
  }
  return roots.length ? `${roots[0].replace(/\/+$/, "")}/${file}` : file;
}

/** The enclosing git working tree, or null when the file is outside one. */
export function repoRootOf(file) {
  let dir = dirname(resolve(file));
  for (;;) {
    if (existsSync(`${dir}/.git`)) return dir;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

/** The file's text at `commit`, or null when the clone does not hold it. */
export function pinnedText(file, commit, roots = []) {
  if (!file || !commit) return null;
  try {
    const path = absoluteInRoots(file, roots);
    const repo = repoRootOf(path);
    if (!repo) return null;
    const relative = path.slice(repo.length).replace(/^\/+/, "");
    return execFileSync("git", ["-C", repo, "show", `${commit}:${relative}`], { encoding: "utf8", maxBuffer: 8 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
  } catch {
    return null;
  }
}

/** `[first, last]` and the file's line count, as a lesson shows it. */
export function lineCount(text) {
  if (text == null) return null;
  return text.endsWith("\n") ? text.slice(0, -1).split("\n").length : text.split("\n").length;
}
