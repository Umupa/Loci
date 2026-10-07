import { listProjectFiles, type ProjectFile } from "../../../platform/tauri/fs";
import { fuzzyMatch } from "../../../shared/lib/fuzzy";

const MAX_MATCHES = 200;
/** A name match always outranks a match that only the folder path produced. */
const NAME_BONUS = 1000;

const cache = new Map<string, Promise<ProjectFile[]>>();

/** Every file and folder of a project, walked once and kept until forgotten. */
export function loadProjectFiles(cwd: string): Promise<ProjectFile[]> {
  let files = cache.get(cwd);
  if (!files) {
    files = listProjectFiles(cwd);
    cache.set(cwd, files);
    files.catch(() => {
      if (cache.get(cwd) === files) cache.delete(cwd);
    });
  }
  return files;
}

/** Drop a project's listing after its folder changed on disk. */
export function forgetProjectFiles(cwd: string) {
  cache.delete(cwd);
}

export type FileMatch = {
  file: ProjectFile;
  /** Matched characters of `file.name`, for highlighting. */
  namePositions: number[];
};

/** Files whose name or project-relative path fuzzily matches, best first. */
export function findFiles(files: readonly ProjectFile[], query: string): FileMatch[] {
  const needle = query.trim();
  if (!needle) return [];
  const ranked: (FileMatch & { score: number })[] = [];
  for (const file of files) {
    const byName = fuzzyMatch(needle, file.name);
    if (byName) {
      ranked.push({ file, namePositions: byName.positions, score: byName.score + NAME_BONUS });
      continue;
    }
    const byPath = fuzzyMatch(needle, file.relative);
    if (!byPath) continue;
    const nameStart = file.relative.length - file.name.length;
    ranked.push({
      file,
      namePositions: byPath.positions.flatMap((at) => (at >= nameStart ? [at - nameStart] : [])),
      score: byPath.score,
    });
  }
  ranked.sort((a, b) => b.score - a.score
    || a.file.relative.length - b.file.relative.length
    || a.file.relative.localeCompare(b.file.relative));
  return ranked.slice(0, MAX_MATCHES).map(({ file, namePositions }) => ({ file, namePositions }));
}
