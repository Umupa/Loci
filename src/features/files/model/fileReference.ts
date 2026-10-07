/** Where in a file a selection sits, when the viewer can tell. */
export type SelectionPlace = { page: number } | { lines: [number, number] } | null;

/** A file as the agent will find it: relative to the project, in code ticks. */
export function fileReference(relativePath: string): string {
  return `\`${relativePath}\``;
}

function describePlace(place: SelectionPlace): string {
  if (!place) return "";
  if ("page" in place) return `, p. ${place.page}`;
  const [from, to] = place.lines;
  return from === to ? `, line ${from}` : `, lines ${from}–${to}`;
}

/**
 * Chat text for a passage taken from a file: the passage as a quote, then a
 * line saying where it came from. The blank line keeps the source line out of
 * the quote block.
 */
export function selectionReference(text: string, relativePath: string, place: SelectionPlace): string {
  const quote = text
    .replace(/\r\n?/g, "\n")
    .trim()
    .split("\n")
    .map((line) => (line ? `> ${line}` : ">"))
    .join("\n");
  return `${quote}\n\n— ${fileReference(relativePath)}${describePlace(place)}`;
}

/** 1-based line numbers covered by a selection in text that starts at offset 0. */
export function selectionLines(text: string, start: number, end: number): [number, number] {
  const lineAt = (offset: number) => {
    let line = 1;
    for (let i = text.indexOf("\n"); i !== -1 && i < offset; i = text.indexOf("\n", i + 1)) line += 1;
    return line;
  };
  const from = Math.min(start, end);
  // A selection that ends right after a newline does not reach the next line.
  const last = Math.max(from, Math.max(start, end) - 1);
  return [lineAt(from), lineAt(last)];
}
