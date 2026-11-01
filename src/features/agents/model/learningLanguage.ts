import { useSyncExternalStore } from "react";

/*
 * The learning language: what the mentors write in (replies, course and lesson
 * titles, guides, notes, reports), whatever language their sources are in.
 * One choice for every mentor in Settings, which a mentor may override.
 * "auto" keeps the old behaviour: reply in the language the learner writes.
 */
export type LearningLanguage = "auto" | "zh-CN" | "en";

export const LEARNING_LANGUAGES: readonly { id: Exclude<LearningLanguage, "auto">; label: string; name: string }[] = [
  { id: "zh-CN", label: "简体中文", name: "Simplified Chinese" },
  { id: "en", label: "English", name: "English" },
];

const KEY = "loci.learningLanguage";
const listeners = new Set<() => void>();

export function isLearningLanguage(value: unknown): value is LearningLanguage {
  return value === "auto" || LEARNING_LANGUAGES.some((language) => language.id === value);
}

export function loadLearningLanguage(): LearningLanguage {
  try {
    const value = localStorage.getItem(KEY);
    return isLearningLanguage(value) ? value : "auto";
  } catch {
    return "auto";
  }
}

export function saveLearningLanguage(value: LearningLanguage) {
  try {
    if (value === "auto") localStorage.removeItem(KEY);
    else localStorage.setItem(KEY, value);
  } catch { /* kept for this window only */ }
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  // Another window changed it.
  const onStorage = (event: StorageEvent) => { if (event.key === KEY) listener(); };
  window.addEventListener("storage", onStorage);
  return () => { listeners.delete(listener); window.removeEventListener("storage", onStorage); };
}

export function useLearningLanguage(): [LearningLanguage, (value: LearningLanguage) => void] {
  return [useSyncExternalStore(subscribe, loadLearningLanguage, () => "auto" as const), saveLearningLanguage];
}

/** A mentor's own choice wins; otherwise the one in Settings. */
export function effectiveLearningLanguage(own: string | undefined): LearningLanguage {
  return isLearningLanguage(own) ? own : loadLearningLanguage();
}

export function learningLanguageLabel(value: LearningLanguage): string {
  return value === "auto" ? "Follow my messages" : LEARNING_LANGUAGES.find((language) => language.id === value)!.label;
}

/**
 * Sent with every turn, so a change applies at once and to mentors whose Soul
 * was written before there was a setting (and may still say "reply in the
 * language the learner writes in").
 */
export function languageContext(value: LearningLanguage): string | undefined {
  if (value === "auto") return undefined;
  const language = LEARNING_LANGUAGES.find((entry) => entry.id === value)!;
  return `<language>
The learner reads in ${language.name} (${language.id}). Write everything of yours in it: replies, course, chapter and lesson titles and summaries, guides, notes and reports, even when the sources or the learner's latest message are in another language. This setting comes before any language rule in your soul.
- Give a term's original beside it the first time it appears${language.id === "en" ? "" : ", e.g. 准入矩阵（Admission Matrix）"}, so the learner can find it in the source.
- Keep code, commands, paths, identifiers and anything quoted from a source exactly as written.
- Sources stay in their original language; never save a translation as a source.
</language>`;
}
