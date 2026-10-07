import { listProjectFiles, type ProjectFile } from "../../../platform/tauri/fs";
import { fuzzyMatch } from "../../../shared/lib/fuzzy";

const MAX_MATCHES = 200;
/**
 * A name match outranks a match that only the folder path produced. The bonus
 * matches the one notes get for a title hit, so both rank on one scale.
 */
const NAME_BONUS = 400;

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
  /** Matched characters of `file.relative`, for highlighting the whole path. */
  positions: number[];
  score: number;
};

/** Files whose name or project-relative path fuzzily matches, best first. */
export function findFiles(files: readonly ProjectFile[], query: string, limit = MAX_MATCHES): FileMatch[] {
  const needle = query.trim();
  if (!needle) return [];
  const ranked: FileMatch[] = [];
  for (const file of files) {
    const nameStart = file.relative.length - file.name.length;
    const byName = fuzzyMatch(needle, file.name);
    if (byName) {
      ranked.push({
        file,
        namePositions: byName.positions,
        positions: byName.positions.map((at) => at + nameStart),
        score: byName.score + NAME_BONUS,
      });
      continue;
    }
    const byPath = fuzzyMatch(needle, file.relative);
    if (!byPath) continue;
    ranked.push({
      file,
      namePositions: byPath.positions.flatMap((at) => (at >= nameStart ? [at - nameStart] : [])),
      positions: byPath.positions,
      score: byPath.score,
    });
  }
  ranked.sort((a, b) => b.score - a.score
    || a.file.relative.length - b.file.relative.length
    || a.file.relative.localeCompare(b.file.relative));
  return ranked.slice(0, limit);
}
