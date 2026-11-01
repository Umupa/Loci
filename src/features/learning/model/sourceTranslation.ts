import { fromMarkdown } from "mdast-util-from-markdown";
import type { Code, Heading, Nodes, RootContent } from "mdast";
import { sectionHeadingIndex } from "../../../shared/lib/markdown/markdownSection";

/*
 * Reading a source in the learner's language without giving up the source.
 *
 * The original stays as published: quotes, section links and highlights are
 * anchored on its words. A translation is kept beside it, unit by unit, where
 * a unit is a heading and the text up to the next heading (or the text before
 * the first one). Each translated unit names the hash of the original it was
 * made from, so a source that changes shows which parts are out of date, and
 * the two can be read side by side unit for unit.
 */

export type SourceUnit = {
  /** The heading's text; "" for what comes before the first heading. */
  heading: string;
  /** 0 for that opening text. */
  depth: number;
  text: string;
  hash: string;
  /** Fenced and indented code, which a translation keeps as it is. */
  code: string[];
};

export type TranslatedUnit = { source: string; heading: string; text: string };

export type SourceTranslation = {
  language: string;
  units: TranslatedUnit[];
};

/** What a reader shows for one unit of the original. */
export type ShownUnit = SourceUnit & {
  translation?: string;
  /** Made from an earlier version of this unit. */
  stale?: boolean;
};

const normalize = (text: string) => text.replace(/\s+/g, " ").trim();

/** FNV-1a, 64-bit: enough to tell versions of a section apart. */
export function unitHash(text: string): string {
  let hash = 0xcbf29ce484222325n;
  for (const char of normalize(text)) {
    hash ^= BigInt(char.codePointAt(0)!);
    hash = (hash * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return hash.toString(16).padStart(16, "0");
}

function plain(node: Nodes): string {
  if ("children" in node) return (node.children as Nodes[]).map(plain).join("");
  if (node.type === "image" || node.type === "imageReference") return node.alt ?? "";
  if (node.type === "html") return "";
  return "value" in node ? node.value : "";
}

function codeOf(nodes: RootContent[]): string[] {
  const found: string[] = [];
  const visit = (node: Nodes) => {
    if (node.type === "code") found.push((node as Code).value.replace(/\s+$/, ""));
    if ("children" in node) for (const child of node.children as Nodes[]) visit(child);
  };
  for (const node of nodes) visit(node);
  return found;
}

/** A Markdown document cut at every top-level heading. */
export function sourceUnits(body: string): SourceUnit[] {
  const tree = fromMarkdown(body);
  const units: SourceUnit[] = [];
  let start = 0;
  let open: { heading: string; depth: number; nodes: RootContent[] } = { heading: "", depth: 0, nodes: [] };
  const close = (end: number) => {
    const text = body.slice(start, end).trim();
    if (text || open.depth) units.push({ heading: open.heading, depth: open.depth, text, hash: unitHash(text), code: codeOf(open.nodes) });
  };
  for (const node of tree.children) {
    if (node.type === "heading") {
      const offset = node.position?.start.offset ?? 0;
      close(offset);
      start = offset;
      open = { heading: normalize(plain(node as Heading)), depth: (node as Heading).depth, nodes: [] };
    }
    open.nodes.push(node);
  }
  close(body.length);
  return units;
}

/**
 * The units a lesson's section covers: its heading and everything below it
 * until a heading of the same or a higher level, matched as the reader does.
 * No section, or one that is not there: the whole document.
 */
export function sectionUnits(units: SourceUnit[], section?: string): SourceUnit[] {
  if (!section?.trim()) return units;
  const headed = units.filter((unit) => unit.depth > 0);
  const found = headed[sectionHeadingIndex(headed.map((unit) => unit.heading), section)];
  if (!found) return units;
  const start = units.indexOf(found);
  const next = units.findIndex((unit, index) => index > start && unit.depth > 0 && unit.depth <= found.depth);
  return units.slice(start, next < 0 ? units.length : next);
}

const MARKER = /^<!-- loci:unit source="([0-9a-f]{16})" heading="([^"]*)" -->$/;

export function parseTranslation(language: string, text: string): SourceTranslation {
  const units: TranslatedUnit[] = [];
  let current: TranslatedUnit | undefined;
  const lines: string[] = [];
  const flush = () => { if (current) units.push({ ...current, text: lines.join("\n").trim() }); lines.length = 0; };
  const body = text.replace(/^---\n[\s\S]*?\n---\n/, "");
  for (const line of body.split("\n")) {
    const marker = MARKER.exec(line.trim());
    if (marker) {
      flush();
      let heading = marker[2];
      try { heading = decodeURIComponent(heading); } catch { /* kept as written */ }
      current = { source: marker[1], heading, text: "" };
    } else if (current) lines.push(line);
  }
  flush();
  return { language, units };
}

export function serializeTranslation(id: string, translation: SourceTranslation): string {
  const head = `---\ntranslationOf: ${id}\nlanguage: ${translation.language}\n---\n`;
  return head + translation.units.map((unit) =>
    `\n<!-- loci:unit source="${unit.source}" heading="${encodeURIComponent(unit.heading)}" -->\n${unit.text.trim()}\n`).join("");
}

/** Each unit of the original with its translation, current or out of date. */
export function shownUnits(units: SourceUnit[], translation: SourceTranslation | undefined): ShownUnit[] {
  const byHash = new Map(translation?.units.map((unit) => [unit.source, unit]) ?? []);
  const byHeading = new Map(translation?.units.map((unit) => [unit.heading, unit]) ?? []);
  return units.map((unit) => {
    const current = byHash.get(unit.hash);
    if (current) return { ...unit, translation: current.text };
    const earlier = unit.depth ? byHeading.get(unit.heading) : undefined;
    return earlier ? { ...unit, translation: earlier.text, stale: true } : unit;
  });
}

export class TranslationShapeError extends Error {}

/**
 * Check a translation of some units against them and fold it into what is
 * kept. It must keep their shape — the same headings at the same levels, and
 * code exactly as it was — so the two can be read side by side.
 */
export function mergeTranslation(
  original: SourceUnit[],
  translatedMarkdown: string,
  kept: SourceTranslation,
): SourceTranslation {
  const translated = sourceUnits(translatedMarkdown);
  const describe = (units: SourceUnit[]) => units.map((unit) => unit.depth ? `${"#".repeat(unit.depth)} ${unit.heading}` : "(text before the first heading)").join("\n");
  if (translated.length !== original.length || translated.some((unit, index) => unit.depth !== original[index].depth))
    throw new TranslationShapeError(`The translation must have the same headings, at the same levels, as the original. The original has:\n${describe(original)}\nThe translation has:\n${describe(translated)}`);
  original.forEach((unit, index) => {
    const code = translated[index].code;
    if (code.length !== unit.code.length || code.some((block, at) => block !== unit.code[at]))
      throw new TranslationShapeError(`Code must stay exactly as in the original; it differs under ${unit.depth ? `"${unit.heading}"` : "the opening text"}.`);
  });
  const replaced = new Set(original.map((unit) => unit.hash));
  const headings = new Set(original.filter((unit) => unit.depth).map((unit) => unit.heading));
  const fresh = original.map((unit, index) => ({ source: unit.hash, heading: unit.heading, text: translated[index].text }));
  // Out-of-date versions of the same headings give way to the new ones.
  const rest = kept.units.filter((unit) => !replaced.has(unit.source) && !headings.has(unit.heading));
  return { language: kept.language, units: [...rest, ...fresh] };
}

const CJK = /[㐀-鿿豈-﫿]/g;
const LATIN = /[A-Za-z]/g;

/**
 * Whether a text is written in a language other than this one, judged from
 * its letters: enough to offer a translation, never to refuse one.
 */
export function looksForeign(text: string, language: string): boolean {
  const sample = text.slice(0, 4000);
  const cjk = sample.match(CJK)?.length ?? 0;
  const latin = sample.match(LATIN)?.length ?? 0;
  if (cjk + latin < 40) return false;
  if (language === "zh-CN") return cjk / (cjk + latin / 4) < 0.3;
  if (language === "en") return cjk / (cjk + latin / 4) > 0.5;
  return false;
}
