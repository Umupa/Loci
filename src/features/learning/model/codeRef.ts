/** A commit id as a lesson pins it: 7 to 40 hex digits. */
export function isCommit(text: string): boolean {
  return /^[0-9a-fA-F]{7,40}$/.test(text);
}

/**
 * A reference to code as lessons and mentors write it:
 * `repos/<repo>@<sha>:path/in/repo#L12-40` (pinned), or a plain path with
 * an optional `#L12-40`.
 */
export type CodeRef = { path: string; commit?: string; lines?: [number, number] };

/** `12` or `12-40` after `#L`, 1-based and inclusive. */
function lineRange(fragment: string): [number, number] | undefined {
  const match = /^L(\d+)(?:-L?(\d+))?$/.exec(fragment);
  if (!match) return undefined;
  const first = Number(match[1]);
  const last = match[2] ? Number(match[2]) : first;
  return first >= 1 && last >= first ? [first, last] : undefined;
}

export function parseCodeRef(text: string): CodeRef {
  let rest = text.trim();
  let lines: [number, number] | undefined;
  const hash = rest.lastIndexOf("#");
  if (hash > 0) {
    lines = lineRange(rest.slice(hash + 1));
    if (lines) rest = rest.slice(0, hash);
  }
  const at = rest.indexOf("@");
  if (at > 0) {
    const colon = rest.indexOf(":", at);
    const sha = colon > at ? rest.slice(at + 1, colon) : "";
    const inner = colon > at ? rest.slice(colon + 1).replace(/^\/+/, "") : "";
    if (inner && isCommit(sha)) {
      const repo = rest.slice(0, at).replace(/\/+$/, "");
      return { path: `${repo}/${inner}`, commit: sha.toLowerCase(), ...(lines ? { lines } : {}) };
    }
  }
  return { path: rest, ...(lines ? { lines } : {}) };
}

/** The pinned form, with the repository as the lesson file should name it. */
export function formatCodeRef(repo: string, commit: string, pathInRepo: string, lines?: [number, number]): string {
  return `${repo.replace(/\/+$/, "")}@${commit}:${pathInRepo}${lines ? `#L${lines[0]}-${lines[1]}` : ""}`;
}
