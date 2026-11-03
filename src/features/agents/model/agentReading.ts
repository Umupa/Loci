/**
 * What the user has open beside an agent's conversation. The overview sets
 * it; each turn the agent is told, so "this lesson" needs no explaining.
 */
export type AgentReading =
  /** `compare`: a comparison lesson's parts, the same mechanism in several places. */
  | { kind: "course"; courseId: string; title: string; lessonId?: string; lessonTitle?: string; compare?: ReadingPart[] }
  | { kind: "document"; id: string; title: string }
  | { kind: "note"; id: string }
  /** `commit`: code read as it was at that commit, not as it is on disk. */
  | { kind: "file"; path: string; commit?: string };

/** One part of a comparison lesson: a file's lines (maybe at a commit) or a document's section. */
export type ReadingPart = { label: string; file?: string; lines?: [number, number]; commit?: string; document?: string; section?: string };

/**
 * Where in it the reader is: the headings above the visible paragraph, the
 * paragraph's start, the page or lines on screen, and the text selected there
 * (kept while focus moves to the composer). It makes "this" and "here" resolve.
 */
export type ReadingPlace = {
  /** In a comparison lesson: the label of the part at the top of the view. */
  part?: string;
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
/** Agents whose next turn goes without `<reading_now>`: the user dismissed the composer's reading tag. */
const skipped = new Set<string>();
const listeners = new Set<() => void>();
let version = 0;

function changed(): void {
  version += 1;
  for (const listener of listeners) listener();
}

/** For the composer's reading tag: told whenever any agent's page, place or skip changes. */
export function subscribeAgentReading(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

/** Bumped on every change, so a component can re-read the store. */
export function agentReadingVersion(): number {
  return version;
}

export function setAgentReading(agentId: string, next: AgentReading | undefined): void {
  const before = reading.get(agentId);
  if (JSON.stringify(before ?? null) === JSON.stringify(next ?? null)) return;
  // Another page: the old place and selection no longer mean anything, and a
  // dismissal was about the page the user saw then.
  places.delete(agentId);
  skipped.delete(agentId);
  if (next) reading.set(agentId, next);
  else reading.delete(agentId);
  changed();
}

export function agentReading(agentId: string): AgentReading | undefined {
  return reading.get(agentId);
}

/** The reader reports where it is; `selection: undefined` in the update clears a selection. */
export function setAgentReadingPlace(agentId: string, update: Partial<ReadingPlace>): void {
  const before = places.get(agentId);
  const next: ReadingPlace = { ...before, ...update };
  for (const key of Object.keys(next) as (keyof ReadingPlace)[]) if (next[key] === undefined) delete next[key];
  // The reader reports on every scroll pause; only a real move redraws the tag.
  if (JSON.stringify(before ?? {}) === JSON.stringify(next)) return;
  if (Object.keys(next).length) places.set(agentId, next);
  else places.delete(agentId);
  changed();
}

export function agentReadingPlace(agentId: string): ReadingPlace | undefined {
  return places.get(agentId);
}

/** Leave `<reading_now>` out of the agent's next turn only; or, with `false`, put it back. */
export function skipReadingOnce(agentId: string, skip = true): void {
  if (skip === skipped.has(agentId)) return;
  if (skip) skipped.add(agentId);
  else skipped.delete(agentId);
  changed();
}

export function readingSkipped(agentId: string): boolean {
  return skipped.has(agentId);
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
  if (place.part) out.part = clip(place.part, PLACE_LIMITS.heading);
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

/**
 * The context block for the turn being sent: nothing when the agent's main
 * area is empty or the user dismissed it for this turn. A dismissal lasts one
 * turn, so the next one carries the page again. `given`: the turn came from a
 * connected window, which sends its own reader, or null when it was dismissed.
 */
export function takeReadingContext(agentId: string, attached: readonly string[] = [], given?: SharedReading | null): string | undefined {
  // A connected window sent this turn: its reader and its dismissal count, not this window's.
  if (given !== undefined) return given ? readingContext(agentId, attached, given) : undefined;
  if (skipped.has(agentId)) {
    skipReadingOnce(agentId, false);
    return undefined;
  }
  return readingContext(agentId, attached);
}

/** What the composer's tag says is open: the page, and where in it the reader is. */
export type ReadingTag = {
  kind: AgentReading["kind"];
  title: string;
  /** The course a lesson belongs to, shown before the lesson's title. */
  parent?: string;
  page?: number;
  lines?: [number, number];
  /** How many lines are selected, when text is. */
  selected?: number;
};

export function readingTag(current: AgentReading, place: ReadingPlace | undefined, noteTitle?: string): ReadingTag {
  const where: Pick<ReadingTag, "page" | "lines" | "selected"> = {};
  if (place?.page) where.page = place.page;
  if (place?.lines) where.lines = place.lines;
  const selection = place?.selection;
  if (selection?.text.trim()) {
    where.selected = selection.lines ? selection.lines[1] - selection.lines[0] + 1 : selection.text.trim().split(/\n+/).length;
    // The selection is what "this" means, so its page or lines are the ones to show.
    if (selection.page) where.page = selection.page;
    if (selection.lines) where.lines = selection.lines;
  }
  if (current.kind === "course")
    return current.lessonTitle ? { kind: "course", parent: current.title, title: current.lessonTitle, ...where } : { kind: "course", title: current.title, ...where };
  if (current.kind === "document") return { kind: "document", title: current.title, ...where };
  if (current.kind === "note") return { kind: "note", title: noteTitle || "Note", ...where };
  const name = current.path.split(/[\\/]/).filter(Boolean).pop() ?? current.path;
  return { kind: "file", title: current.commit ? `${name} @ ${current.commit.slice(0, 7)}` : name, ...where };
}

/** The context block for a turn, or nothing when the agent's main area is empty. */
/** What a reader shows and where in it, as another window hands it to the one running the turn. */
export type SharedReading = { reading: AgentReading; place?: ReadingPlace };

/** This window's reader beside an agent, to send along with a message. */
export function sharedReading(agentId: string): SharedReading | undefined {
  const current = reading.get(agentId);
  if (!current) return undefined;
  const place = places.get(agentId);
  return place ? { reading: current, place } : { reading: current };
}

/** `given`: the reader of the window that sent the message, in place of this window's. */
export function readingContext(agentId: string, attached: readonly string[] = [], given?: SharedReading): string | undefined {
  const current = given ? given.reading : reading.get(agentId);
  if (!current) return undefined;
  const place = given ? given.place : places.get(agentId);
  const shown: Record<string, unknown> = { ...current };
  // How a mentor cites this page back, so its answer can link to the passage.
  if (current.kind === "document") shown.link = `loci://source/${current.id}`;
  const budgeted = place ? budgetPlace(place, attached) : {};
  if (Object.keys(budgeted).length) shown.place = budgeted;
  return `<reading_now>\n${JSON.stringify(shown)}\n</reading_now>`;
}
