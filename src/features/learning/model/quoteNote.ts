import { parseAppResourceUrl } from "../../../shared/lib/appResourceLinks";
import { learningSourceLabel } from "./learningContext";
import type { LearningSource } from "./types";

/*
 * A passage kept in a note: the words as a Markdown quote, a link back to
 * where they were read, and the reader's own note under it.
 */

// A link names the passage by its opening words: enough to find and flash it,
// short enough that an encoded CJK passage stays inside a link's length limit.
const LINK_QUOTE = 120;

/** The address a passage's link opens: its page, lines or section, and the words to flash there. */
export function quoteLink(source: LearningSource): string {
  if (source.kind === "web") return source.url;
  const base = `loci://source/${source.id}`;
  // A whole block's quote is its Markdown; the words a reader sees are its rendered opening (none for a picture).
  const block = "anchor" in source ? source.anchor?.block : undefined;
  const words = Array.from((block ? block.lead : source.quote)?.replace(/\s+/g, " ").trim() ?? "");
  const quote = words.length > LINK_QUOTE ? words.slice(0, LINK_QUOTE).join("").trimEnd() : words.join("");
  const lines = source.kind === "file" ? source.lines ?? source.anchor?.lines : undefined;
  const place = source.kind === "pdf" ? [`p${source.anchors[0]?.page ?? 1}`]
    : lines ? [`L${lines[0]}-${lines[1]}`]
    : source.kind === "document" && source.section ? [`section=${encodeURIComponent(source.section)}`] : [];
  // A place the link format cannot carry (a very long heading) falls back to
  // the bare link, which opens the registered passage where it was kept.
  for (const parts of [[...place, ...(quote ? [`quote=${encodeURIComponent(quote)}`] : [])], place]) {
    const href = parts.length ? `${base}#${parts.join("&")}` : base;
    if (parseAppResourceUrl(href)) return href;
  }
  return base;
}

/**
 * The Markdown a passage becomes in a note: the quote, then where it is from
 * as a link back (when it has a source), then `note`, what the reader wrote on it.
 */
export function quoteMarkdown(quote: string, source?: LearningSource, note = ""): string {
  const words = quote.replace(/\r\n?/g, "\n").trim();
  const lines = words ? words.split("\n").map((line) => line.trimEnd() ? `> ${line.trimEnd()}` : ">") : [];
  // Brackets in a title would close the link text early. A passage with no words
  // (a picture of a figure) is only its link.
  if (source) lines.push(...(lines.length ? [">"] : []), `> — [${learningSourceLabel(source).replace(/([[\]\\])/g, "\\$1")}](${quoteLink(source)})`);
  const own = note.replace(/\r\n?/g, "\n").trim();
  return `${lines.join("\n")}${own ? `\n\n${own}` : ""}`;
}
