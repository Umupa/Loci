import type { LearningMessageContext, LearningSource } from "./types";
import { registerLearningSource, linkAnnotationDiscussion } from "./learningStore";

export function mergeLearningContext(current: LearningMessageContext, incoming: LearningMessageContext): LearningMessageContext {
  const sources = [...(current.sources ?? [])];
  for (const source of incoming.sources ?? []) {
    const index = sources.findIndex((entry) => entry.id === source.id);
    if (index < 0) sources.push(source);
    else sources[index] = source;
  }
  return sources.length ? { sources } : {};
}

export function learningSourceLabel(source: LearningSource): string {
  if (source.kind === "pdf") return `${source.title} · p. ${source.anchors.map((anchor) => anchor.page).join(", ")}`;
  if (source.kind === "file" && source.lines) return `${source.title} · L${source.lines[0]}–${source.lines[1]}`;
  return source.title;
}

/** Serialize source metadata in one format for every CLI. */
export function learningContextText(context: LearningMessageContext): string {
  if (!context.sources?.length) return "";
  return `<loci_learning_context>\n${JSON.stringify(context, null, 2)}\n</loci_learning_context>`;
}

export function withLearningContext(text: string, context: LearningMessageContext): string {
  const contextText = learningContextText(context);
  return contextText ? `${text}\n\n${contextText}` : text;
}

export async function registerSubmittedLearningContext(context: LearningMessageContext, sessionId: string, blockId: string, linkDiscussion = true) {
  for (const source of context.sources ?? []) {
    await registerLearningSource(source);
  }
  if (linkDiscussion) await linkLearningDiscussion(context, sessionId, blockId);
}
export async function linkLearningDiscussion(context: LearningMessageContext, sessionId: string, blockId: string) {
  for (const source of context.sources ?? []) {
    if (source.kind === "pdf" && source.annotationId) await linkAnnotationDiscussion(source.annotationId, sessionId, blockId);
  }
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
/** Validate persisted transcript metadata at the same boundary as other Block fields. */
export function sanitizeLearningContext(value: unknown): LearningMessageContext {
  const input = record(value);
  if (!input) return {};
  const sources = Array.isArray(input.sources) ? input.sources.flatMap((entry): LearningSource[] => {
    const source = record(entry);
    if (!source || typeof source.id !== "string" || !source.id || typeof source.title !== "string" || typeof source.quote !== "string") return [];
    const base = { id: source.id, title: source.title, quote: source.quote };
    if (source.kind === "web" && typeof source.url === "string") {
      try { if (!["https:", "http:"].includes(new URL(source.url).protocol)) return []; } catch { return []; }
      return [{ ...base, kind: "web", url: source.url }];
    }
    if (source.kind === "conversation" && typeof source.sessionId === "string" && typeof source.blockId === "string") return [{ ...base, kind: "conversation", sessionId: source.sessionId, blockId: source.blockId }];
    if (source.kind === "file" && typeof source.path === "string") {
      const lines = source.lines;
      return [{ ...base, kind: "file", path: source.path, ...(Array.isArray(lines) && lines.length === 2 && lines.every((line) => Number.isInteger(line) && line > 0) ? { lines: lines as [number, number] } : {}) }];
    }
    if (source.kind === "pdf" && typeof source.documentId === "string" && typeof source.path === "string" && Array.isArray(source.anchors)) {
      const anchors = source.anchors.flatMap((entry) => {
        const anchor = record(entry);
        if (!anchor || !Number.isInteger(anchor.page) || Number(anchor.page) < 1 || !Array.isArray(anchor.rects)) return [];
        const rects = anchor.rects.flatMap((entry) => {
          const rect = record(entry);
          if (!rect || ![rect.x, rect.y, rect.width, rect.height].every((number) => typeof number === "number" && Number.isFinite(number) && number >= 0 && number <= 1)) return [];
          return [{ x: Number(rect.x), y: Number(rect.y), width: Number(rect.width), height: Number(rect.height) }];
        });
        return [{ page: Number(anchor.page), rects }];
      });
      if (!anchors.length) return [];
      return [{ ...base, kind: "pdf", documentId: source.documentId, path: source.path, anchors, ...(typeof source.annotationId === "string" ? { annotationId: source.annotationId } : {}) }];
    }
    return [];
  }) : [];
  return sources.length ? { sources } : {};
}
