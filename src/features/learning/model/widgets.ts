import { createContext } from "react";
import { fencedBlocks } from "../../sessions/model/cards";
import type { StoredWidget, WidgetOwner, WidgetRef, WidgetSpec } from "./types";

export const WIDGET_FENCE = "loci-widget";
export type WidgetHost = { owner: WidgetOwner; sourceSessionId: string };
export const WidgetHostContext = createContext<WidgetHost | null>(null);

export type WidgetParseResult = { spec: WidgetSpec; error?: never } | { spec?: never; error: string };

/** A complete source file, with deliberately flat metadata rather than a UI schema. */
export function parseWidget(source: string): WidgetParseResult {
  const text = source.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
  const front = text.match(/^\s*---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
  if (!front) return { error: "A widget needs front matter with id and title." };
  const fields: Record<string, string> = {};
  for (const line of front[1].split("\n")) {
    if (!line.trim()) continue;
    const field = line.match(/^([A-Za-z]+)\s*:\s*(.*?)\s*$/);
    if (!field) return { error: "Widget metadata must use one field per line." };
    fields[field[1].toLowerCase()] = field[2].replace(/^(["'])(.*)\1$/, "$2");
  }
  const id = fields.id?.trim();
  if (!id || id.length > 80 || !/^[\p{L}\p{N}_-]+$/u.test(id)) return { error: "A widget needs a stable id of at most 80 letters, digits, hyphens or underscores." };
  const title = fields.title?.trim();
  if (!title || title.length > 200) return { error: "A widget needs a title of at most 200 characters." };
  const html = text.slice(front[0].length).trim();
  if (!html || !/<[A-Za-z!]/.test(html)) return { error: "The widget has no HTML content." };
  if (new TextEncoder().encode(html).length > 1024 * 1024) return { error: "The generated explanation exceeds the 1 MiB source limit." };
  let sourceIds: string[] = [];
  if (fields.sources) {
    try {
      const value: unknown = fields.sources.startsWith("[") ? JSON.parse(fields.sources) : fields.sources.split(",").map((id) => id.trim());
      if (!Array.isArray(value) || value.length > 64 || value.some((id) => typeof id !== "string" || !/^[\p{L}\p{N}_-]{1,128}$/u.test(id))) return { error: "Sources must be a list of at most 64 existing source ids." };
      sourceIds = [...new Set(value as string[])];
    } catch { return { error: "Sources must be a JSON list or comma-separated source ids." }; }
  }
  const subject = fields.subject?.trim();
  return { spec: { id, title, html, sourceIds, ...(subject ? { subject: subject.slice(0, 80) } : {}) } };
}

export function widgetsInText(text: string): WidgetSpec[] {
  const widgets = new Map<string, WidgetSpec>();
  for (const source of fencedBlocks(text, WIDGET_FENCE)) {
    const result = parseWidget(source);
    if (result.spec) widgets.set(result.spec.id, result.spec);
  }
  return [...widgets.values()];
}

export function widgetKey(ref: WidgetRef): string {
  return JSON.stringify([ref.owner.kind, ref.owner.id, ref.id]);
}

export const OPEN_WIDGET_EVENT = "loci:open-widget";
export type OpenWidgetDetail = { widget: WidgetRef; sourceSessionId: string; title: string };
export function openWidget(widget: WidgetRef, sourceSessionId: string, title: string) {
  window.dispatchEvent(new CustomEvent<OpenWidgetDetail>(OPEN_WIDGET_EVENT, { detail: { widget, sourceSessionId, title } }));
}

export function widgetRef(widget: StoredWidget): WidgetRef {
  return { owner: widget.owner, id: widget.id };
}
