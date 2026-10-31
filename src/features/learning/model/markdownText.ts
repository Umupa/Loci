/**
 * Markdown as a reader shows it, roughly: the words without their marks, and
 * for each line the headings it falls under. Enough to anchor a quoted passage
 * where there is no rendered page, as on the command line.
 */
export type PlainMarkdown = { text: string; lineStarts: number[]; headings: string[][] };

function inline(line: string): string {
  return line
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/`([^`]*)`/g, "$1")
    .replace(/(\*\*|__)(.*?)\1/g, "$2")
    .replace(/(^|[^\w*])[*_]([^*_\n]+)[*_](?=[^\w*]|$)/g, "$1$2")
    .replace(/~~(.*?)~~/g, "$1");
}

export function plainMarkdown(markdown: string): PlainMarkdown {
  const lines = markdown.replace(/^﻿/, "").replace(/\r\n?/g, "\n").split("\n");
  let start = 0;
  if (/^---\s*$/.test(lines[0] ?? "")) {
    const close = lines.findIndex((line, index) => index > 0 && /^(---|\.\.\.)\s*$/.test(line));
    if (close > 0) start = close + 1;
  }
  const stack: { level: number; text: string }[] = [];
  const out: string[] = [];
  const lineStarts: number[] = [];
  const headings: string[][] = [];
  let length = 0;
  let fence: string | null = null;
  for (let index = start; index < lines.length; index++) {
    let line = lines[index];
    const marker = /^\s{0,3}(`{3,}|~{3,})/.exec(line)?.[1];
    if (marker && (!fence || (marker[0] === fence[0] && marker.length >= fence.length))) { fence = fence ? null : marker; continue; }
    if (!fence) {
      const heading = /^\s{0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$/.exec(line);
      if (heading) {
        const level = heading[1].length;
        while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
        line = inline(heading[2]);
        stack.push({ level, text: line.trim() });
      } else line = inline(line.replace(/^\s{0,3}(?:>\s?)+/, "").replace(/^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?/, "").replace(/^\s*\|/, "").replace(/\|\s*$/, "").replace(/\s*\|\s*/g, " "));
    }
    lineStarts.push(length);
    headings.push(stack.map((entry) => entry.text).slice(-6));
    out.push(line);
    length += line.length + 1;
  }
  return { text: out.join("\n"), lineStarts, headings };
}

/** The headings above an offset of `plainMarkdown(...).text`. */
export function headingsAtOffset(plain: PlainMarkdown, offset: number): string[] {
  let line = 0;
  while (line + 1 < plain.lineStarts.length && plain.lineStarts[line + 1] <= offset) line++;
  return plain.headings[line] ?? [];
}
