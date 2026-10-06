

/** First markdown heading, or the first non-empty prose line. */
export function planTitle(text: string): string {
  const heading = text.match(/^\s{0,3}#{1,6}\s+(.+)$/m);
  if (heading) return unwrapMarkdown(heading[1]);
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("```") || trimmed === "---") continue;
    return unwrapMarkdown(trimmed).slice(0, 80) || "Plan";
  }
  return "Plan";
}

function unwrapMarkdown(value: string): string {
  return value
    .replace(/!\[[^\]]*]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
    .replace(/[*_`]+/g, "")
    .trim();
}
