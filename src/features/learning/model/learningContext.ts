import type { JsonValue, LearningMessageContext, LearningSource, WidgetContext } from "./types";
import { getLearningWidget, registerLearningSource, linkAnnotationDiscussion } from "./learningStore";

export function mergeLearningContext(current: LearningMessageContext, incoming: LearningMessageContext): LearningMessageContext {
  const sources = [...(current.sources ?? [])];
  for (const source of incoming.sources ?? []) {
    const index = sources.findIndex((entry) => entry.id === source.id);
    if (index < 0) sources.push(source);
    else sources[index] = source;
  }
  return { ...(sources.length ? { sources } : {}), ...(incoming.widgetContext ?? current.widgetContext ? { widgetContext: incoming.widgetContext ?? current.widgetContext } : {}) };
}

export function learningSourceLabel(source: LearningSource): string {
  if (source.kind === "pdf") return `${source.title} · p. ${source.anchors.map((anchor) => anchor.page).join(", ")}`;
  if (source.kind === "file" && source.lines) return `${source.title} · L${source.lines[0]}–${source.lines[1]}`;
  return source.title;
}

/** Serialize source and widget metadata in one format for every CLI. */
export function learningContextText(context: LearningMessageContext): string {
  if (!context.sources?.length && !context.widgetContext) return "";
  return `<loci_learning_context>\n${JSON.stringify(context, null, 2)}\n</loci_learning_context>`;
}

export function withLearningContext(text: string, context: LearningMessageContext): string {
  const contextText = learningContextText(context);
  return contextText ? `${text}\n\n${contextText}` : text;
}

/** Saved explanations can outlive their provider conversation. Load their current code only when sending. */
export async function hydrateLearningContext(context: LearningMessageContext): Promise<LearningMessageContext> {
  const snapshot = context.widgetContext;
  if (!snapshot) return context;
  const canonical = await getLearningWidget({ owner: snapshot.owner, id: snapshot.id });
  if (!canonical) throw new Error("This explanation no longer exists. Remove its context or reopen an existing explanation before sending.");
  return { ...context, widgetContext: { ...snapshot, id: canonical.id, title: canonical.title, revision: canonical.revision, html: canonical.html } };
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
function json(value: unknown, depth = 0): value is JsonValue {
  if (depth > 30) return false;
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) return value.every((entry) => json(entry, depth + 1));
  const object = record(value);
  return !!object && Object.values(object).every((entry) => json(entry, depth + 1));
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
  const widget = record(input.widgetContext);
  const owner = record(widget?.owner);
  const widgetContext: WidgetContext | undefined = widget && owner && (owner.kind === "agent" || owner.kind === "session") && typeof owner.id === "string" && typeof widget.id === "string" && typeof widget.title === "string" && Number.isInteger(widget.revision) && json(widget.state)
    ? { owner: { kind: owner.kind, id: owner.id }, id: widget.id, title: widget.title, revision: Number(widget.revision), state: widget.state, ...(typeof widget.selection === "string" ? { selection: widget.selection } : {}), ...(typeof widget.html === "string" ? { html: widget.html } : {}) } : undefined;
  return { ...(sources.length ? { sources } : {}), ...(widgetContext ? { widgetContext } : {}) };
}
