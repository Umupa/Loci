// Seeds a scenario's local repositories into the mentor's own `repos/` so a
// sandbox run reads the three checkouts on this machine instead of cloning
// from the network. The source is `~/Loci/repos` (the shared 0.3 clone root)
// and is only read: a local clone shares its objects, and the runner checks
// that the source HEAD and working tree are unchanged afterwards.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

/** Where the local checkouts live; `LOCI_EVAL_REPOS` names another root. */
export const DEFAULT_REPOS_ROOT = process.env.LOCI_EVAL_REPOS ?? join(homedir(), "Loci/repos");

function git(dir, args) {
  return execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function headOf(dir) {
  try { return git(dir, ["rev-parse", "HEAD"]); } catch { return null; }
}

function statusOf(dir) {
  try { return git(dir, ["status", "--porcelain"]); } catch { return null; }
}

/** Every file under a folder, skipping `.git` (the clone's own bookkeeping). */
export function countFiles(root) {
  let count = 0;
  const visit = (dir, depth) => {
    if (depth > 12) return;
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (entry.name === ".git") continue;
      const path = join(dir, entry.name);
      if (entry.isDirectory()) visit(path, depth + 1);
      else if (entry.isFile()) count++;
    }
  };
  visit(root, 0);
  return count;
}

/** `--local` shares objects; a shallow source ignores it and copies instead. */
function localClone(source, destination) {
  execFileSync("git", ["clone", "--local", "--quiet", source, destination], { stdio: ["ignore", "pipe", "pipe"] });
}

/**
 * Clones each `owner/repo` under `folder/repos/owner/repo`. Returns what was
 * seeded, with the source and destination HEADs and a file count. A source
 * that changes while it is cloned is an error: these repositories are the
 * user's and must stay untouched.
 */
export function seedRepos({ folder, repos = [], sourceRoot = DEFAULT_REPOS_ROOT, clone = localClone }) {
  if (!Array.isArray(repos)) throw new Error("seed.repos must be a list of owner/repo names");
  const seeded = [];
  for (const repo of repos) {
    if (typeof repo !== "string" || !/^[^/\\]+\/[^/\\]+$/.test(repo)) throw new Error(`Not an owner/repo name: ${String(repo)}`);
    const source = resolve(sourceRoot, repo);
    if (!existsSync(join(source, ".git"))) throw new Error(`No local checkout at ${source} (clone ${repo} into ${sourceRoot} first)`);
    const destination = resolve(folder, "repos", repo);
    if (existsSync(destination)) {
      seeded.push({ repo, source, destination, head: headOf(destination), files: countFiles(destination), skipped: true });
      continue;
    }
    const before = { head: headOf(source), status: statusOf(source) };
    if (!before.head) throw new Error(`Cannot read HEAD of ${source}`);
    mkdirSync(dirname(destination), { recursive: true });
    clone(source, destination);
    const after = { head: headOf(source), status: statusOf(source) };
    if (after.head !== before.head || after.status !== before.status)
      throw new Error(`Seeding ${repo} changed its source checkout at ${source}; the shared repos must stay read-only`);
    const head = headOf(destination);
    if (!head) throw new Error(`Cloned ${source} but cannot read its HEAD at ${destination}`);
    seeded.push({ repo, source, destination, head, sourceHead: before.head, files: countFiles(destination), skipped: false });
  }
  return seeded;
}

/** Whether a path is a folder this evaluation may delete after a run. */
export function removableMentorFolder(folder, { home = homedir(), temp = undefined } = {}) {
  if (!folder) return false;
  const target = resolve(folder);
  const roots = [];
  if (temp) roots.push(resolve(temp));
  const dev = join(home, "Loci-Dev");
  roots.push(dev);
  try {
    for (const name of readdirSync(home)) if (name.startsWith("Loci-Dev-")) roots.push(join(home, name));
  } catch { /* an unreadable home leaves only the roots above */ }
  if (!roots.some((root) => target.startsWith(`${resolve(root)}/`) && target !== resolve(root))) return false;
  try { return statSync(target).isDirectory(); } catch { return false; }
}
