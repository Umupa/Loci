import { transport } from "../../../platform/transport";

/** A term a mentor's lessons introduce: its other spellings, a one-line definition, and the lesson that teaches it. */
export type GlossaryTerm = { term: string; aliases?: string[]; definition: string; course?: string; lesson?: string };

/** Fired on `window` when a mentor's glossary changes. */
export const GLOSSARY_CHANGED_EVENT = "loci:glossary-changed";

const changed = (agentId: string) => {
  if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent(GLOSSARY_CHANGED_EVENT, { detail: { agentId } }));
};

export function loadGlossary(agentId: string): Promise<GlossaryTerm[]> {
  return transport.call<GlossaryTerm[]>("glossary_read", { agentId });
}

/** Adds terms, or replaces those already there under the same name (any case). */
export async function saveGlossaryTerms(agentId: string, terms: GlossaryTerm[]): Promise<{ saved: number; total: number }> {
  const result = await transport.call<{ saved: number; total: number }>("glossary_write", { agentId, terms });
  changed(agentId);
  return result;
}

export async function removeGlossaryTerms(agentId: string, terms: string[]): Promise<number> {
  const removed = await transport.call<number>("glossary_remove", { agentId, terms });
  changed(agentId);
  return removed;
}

/** Terms as a mentor writes them, checked before they are saved. */
export function parseGlossaryInput(value: unknown): GlossaryTerm[] {
  const list = Array.isArray(value) ? value : [value];
  if (!list.length) throw new Error("terms is a non-empty list of { term, definition, aliases?, course?, lesson? }");
  return list.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error(`Term ${index + 1} must be an object`);
    const raw = entry as Record<string, unknown>;
    if (typeof raw.term !== "string" || !raw.term.trim()) throw new Error(`Term ${index + 1} needs a term`);
    if (typeof raw.definition !== "string" || !raw.definition.trim()) throw new Error(`${raw.term}: needs a one-line definition`);
    if (raw.aliases !== undefined && (!Array.isArray(raw.aliases) || !raw.aliases.every((alias) => typeof alias === "string")))
      throw new Error(`${raw.term}: aliases is a list of strings`);
    for (const key of ["course", "lesson"] as const)
      if (raw[key] !== undefined && typeof raw[key] !== "string") throw new Error(`${raw.term}: ${key} is an id`);
    if (raw.lesson !== undefined && raw.course === undefined) throw new Error(`${raw.term}: name the lesson's course too`);
    return {
      term: raw.term.trim(), definition: raw.definition.trim(),
      ...(raw.aliases ? { aliases: raw.aliases as string[] } : {}),
      ...(raw.course ? { course: raw.course as string } : {}),
      ...(raw.lesson ? { lesson: raw.lesson as string } : {}),
    };
  });
}
