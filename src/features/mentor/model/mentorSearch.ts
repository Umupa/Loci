import { agentCanvasScope, agentLook, canvasScopeAgentId, type Agent } from "../../agents/model/agent";
import type { StoredDocument } from "../../agents/model/agentDocuments";
import type { Canvas } from "../../canvas/canvas";
import { courseItems, type CourseWithProgress } from "../../learning/model/course";
import type { Note } from "../../notes";
import type { MentorPage } from "./mentorPage";

export type MentorSearchKind = "mentor" | "course" | "lesson" | "source" | "note" | "canvas";

/** One thing ⌘K can open: a mentor, or a page in a mentor's reader. */
export type MentorSearchItem = {
  id: string;
  kind: MentorSearchKind;
  title: string;
  /** Where it lives: its mentor, and its course for a lesson. */
  context: string;
  /** The mentor that keeps it; none for a note no mentor owns. */
  agentId?: string;
  /** What the reader opens; none for a mentor itself. */
  page?: MentorPage;
};

export type MentorSearchSources = {
  agents: readonly Agent[];
  courses: readonly CourseWithProgress[];
  documents: ReadonlyMap<string, readonly StoredDocument[]>;
  notes: readonly Note[];
  canvases: readonly Canvas[];
};

/** Everything searchable, mentors first, each mentor's library after it. */
export function mentorSearchItems({ agents, courses, documents, notes, canvases }: MentorSearchSources): MentorSearchItem[] {
  const names = new Map(agents.map((agent) => [agent.id, agentLook(agent).name]));
  const items: MentorSearchItem[] = agents.map((agent) => ({ id: `mentor:${agent.id}`, kind: "mentor", title: names.get(agent.id)!, context: agentLook(agent).role ?? "Mentor", agentId: agent.id }));
  for (const course of courses) {
    const mentor = names.get(course.agentId);
    if (!mentor) continue;
    const detail = { courseId: course.id, agentId: course.agentId, title: course.title };
    items.push({ id: `course:${course.agentId}:${course.id}`, kind: "course", title: course.title, context: mentor, agentId: course.agentId, page: { kind: "course", course: detail } });
    for (const lesson of courseItems(course.data)) {
      items.push({ id: `lesson:${course.agentId}:${course.id}:${lesson.id}`, kind: "lesson", title: lesson.title, context: `${mentor} › ${course.title}`, agentId: course.agentId,
        page: { kind: "course", course: { ...detail, itemId: lesson.id } } });
    }
  }
  for (const [agentId, list] of documents) {
    const mentor = names.get(agentId);
    if (!mentor) continue;
    for (const document of list) items.push({ id: `source:${agentId}:${document.id}`, kind: "source", title: document.title, context: mentor, agentId,
      page: { kind: "document", document: { id: document.id, title: document.title, body: "", ...(document.subject ? { subject: document.subject } : {}) } } });
  }
  for (const note of notes) {
    const owner = note.agentId && names.has(note.agentId) ? note.agentId : undefined;
    items.push({ id: `note:${note.id}`, kind: "note", title: note.title || "Untitled", context: owner ? names.get(owner)! : "Notes", ...(owner ? { agentId: owner } : {}),
      page: { kind: "note", id: note.id } });
  }
  for (const canvas of canvases) {
    const owner = canvasScopeAgentId(canvas.cwd);
    if (!owner || !names.has(owner) || canvas.cwd !== agentCanvasScope(owner)) continue;
    items.push({ id: `canvas:${canvas.id}`, kind: "canvas", title: canvas.title, context: names.get(owner)!, agentId: owner, page: { kind: "canvas", id: canvas.id } });
  }
  return items;
}

const KIND_ORDER: Record<MentorSearchKind, number> = { mentor: 0, course: 1, lesson: 2, source: 3, note: 4, canvas: 5 };

function score(title: string, query: string): number | null {
  const text = title.toLocaleLowerCase();
  if (text === query) return 0;
  if (text.startsWith(query)) return 1;
  // The start of a later word: "jail" finds "Firecracker jailer".
  if (new RegExp(`(^|[\\s\\-_/.:(])${query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`).test(text)) return 2;
  if (text.includes(query)) return 3;
  return null;
}

/** Items whose title matches every word of the query, best first. */
export function searchMentorItems(items: readonly MentorSearchItem[], query: string, limit = 40): MentorSearchItem[] {
  const words = query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return items.filter((item) => item.kind === "mentor").slice(0, limit);
  const ranked: { item: MentorSearchItem; rank: number; index: number }[] = [];
  items.forEach((item, index) => {
    let rank = 0;
    for (const word of words) {
      const own = score(item.title, word);
      // A word may also match where the item lives, such as its mentor's name.
      const where = own === null && item.kind !== "mentor" ? score(item.context, word) : null;
      if (own === null && where === null) return;
      rank += own ?? 4 + (where ?? 0);
    }
    ranked.push({ item, rank, index });
  });
  ranked.sort((a, b) => a.rank - b.rank || KIND_ORDER[a.item.kind] - KIND_ORDER[b.item.kind] || a.index - b.index);
  return ranked.slice(0, limit).map((entry) => entry.item);
}
