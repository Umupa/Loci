/**
 * What the user has open beside an agent's conversation. The overview sets
 * it; each turn the agent is told, so "this lesson" needs no explaining.
 */
export type AgentReading =
  | { kind: "course"; courseId: string; title: string; lessonId?: string; lessonTitle?: string }
  | { kind: "document"; id: string; title: string }
  | { kind: "note"; id: string }
  | { kind: "canvas"; id: string }
  /** `commit`: code read as it was at that commit, not as it is on disk. */
  | { kind: "file"; path: string; commit?: string };

/**
 * Where in it the reader is: the headings above the visible paragraph, the
 * paragraph's start, the page or lines on screen, and the text selected there
 * (kept while focus moves to the composer). It makes "this" and "here" resolve.
 */
export type ReadingPlace = {
  section?: string[];
  paragraph?: string;
  page?: number;
  lines?: [number, number];
  selection?: { text: string; page?: number; lines?: [number, number] };
};

/** Budgets for the place, so it stays a few hundred tokens whatever is open. */
export const PLACE_LIMITS = { headings: 3, heading: 80, paragraph: 280, selection: 600, block: 1500 } as const;

const reading = new Map<string, AgentReading>();
const places = new Map<string, ReadingPlace>();

export function setAgentReading(agentId: string, next: AgentReading | undefined): void {
  const before = reading.get(agentId);
  // Another page: the old place and selection no longer mean anything.
  if (JSON.stringify(before ?? null) !== JSON.stringify(next ?? null)) places.delete(agentId);
  if (next) reading.set(agentId, next);
  else reading.delete(agentId);
}

export function agentReading(agentId: string): AgentReading | undefined {
  return reading.get(agentId);
}

/** The reader reports where it is; `selection: undefined` in the update clears a selection. */
export function setAgentReadingPlace(agentId: string, update: Partial<ReadingPlace>): void {
  const next: ReadingPlace = { ...places.get(agentId), ...update };
  for (const key of Object.keys(next) as (keyof ReadingPlace)[]) if (next[key] === undefined) delete next[key];
  if (Object.keys(next).length) places.set(agentId, next);
  else places.delete(agentId);
}

export function agentReadingPlace(agentId: string): ReadingPlace | undefined {
  return places.get(agentId);
}

/** At most `max` characters, cut at a word boundary with an ellipsis. */
export function clip(text: string, max: number): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (flat.length <= max) return flat;
  const cut = flat.slice(0, max - 1);
  const space = cut.lastIndexOf(" ");
  return `${space > max * 0.6 ? cut.slice(0, space) : cut}…`;
}

const same = (a: string, b: string) => a.replace(/\s+/g, " ").trim() === b.replace(/\s+/g, " ").trim();

/** The place within budget. A selection already attached to the message as a source is not repeated. */
export function budgetPlace(place: ReadingPlace, attached: readonly string[] = []): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (place.section?.length) out.section = place.section.slice(-PLACE_LIMITS.headings).map((heading) => clip(heading, PLACE_LIMITS.heading));
  if (place.page) out.page = place.page;
  if (place.lines) out.lines = place.lines;
  if (place.paragraph) out.paragraph = clip(place.paragraph, PLACE_LIMITS.paragraph);
  if (place.selection?.text) {
    const { text, ...where } = place.selection;
    if (attached.some((quote) => same(quote, text))) out.selection = "attached";
    else out.selection = Object.keys(where).length ? { ...where, text: clip(text, PLACE_LIMITS.selection) } : clip(text, PLACE_LIMITS.selection);
  }
  // Still too long (very long headings): the paragraph goes first, then the selection shrinks.
  if (JSON.stringify(out).length > PLACE_LIMITS.block) delete out.paragraph;
  const selection = out.selection as string | { text: string } | undefined;
  if (JSON.stringify(out).length > PLACE_LIMITS.block && selection && selection !== "attached") {
    const room = Math.max(80, PLACE_LIMITS.block - JSON.stringify({ ...out, selection: "" }).length - 40);
    out.selection = typeof selection === "string" ? clip(selection, room) : { ...selection, text: clip(selection.text, room) };
  }
  return out;
}

/** The context block for a turn, or nothing when the agent's main area is empty. */
export function readingContext(agentId: string, attached: readonly string[] = []): string | undefined {
  const current = reading.get(agentId);
  if (!current) return undefined;
  const place = places.get(agentId);
  const shown: Record<string, unknown> = { ...current };
  // How a mentor cites this page back, so its answer can link to the passage.
  if (current.kind === "document") shown.link = `loci://source/${current.id}`;
  const budgeted = place ? budgetPlace(place, attached) : {};
  if (Object.keys(budgeted).length) shown.place = budgeted;
  return `<reading_now>\n${JSON.stringify(shown)}\n</reading_now>`;
}
