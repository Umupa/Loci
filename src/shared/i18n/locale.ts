import { useSyncExternalStore } from "react";
import zhCN from "./zh-CN.json";

export type Locale = "en" | "zh-CN";
export type LanguagePreference = "system" | Locale;
const STORAGE_KEY = "loci.language";
const CHANGE_EVENT = "loci:language-change";

export function resolveLocale(preference: LanguagePreference, languages: readonly string[]): Locale {
  if (preference !== "system") return preference;
  // Use the first supported language in the user's ordered language preferences.
  for (const language of languages) {
    if (/^zh(?:-|$)/i.test(language)) return "zh-CN";
    if (/^en(?:-|$)/i.test(language)) return "en";
  }
  return "en";
}

export function loadLanguagePreference(): LanguagePreference {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "en" || stored === "zh-CN") return stored;
  } catch { /* Storage can be unavailable in private windows. */ }
  return "system";
}

let preference = loadLanguagePreference();
export function getLanguagePreference(): LanguagePreference { return preference; }
export function getLocale(): Locale {
  const languages = typeof navigator === "undefined" ? [] : navigator.languages?.length
    ? navigator.languages : [navigator.language];
  return resolveLocale(preference, languages);
}

function applyDocumentLanguage() {
  if (typeof document !== "undefined") document.documentElement.lang = getLocale();
}

export function setLanguagePreference(next: LanguagePreference) {
  preference = next;
  try { localStorage.setItem(STORAGE_KEY, next); } catch { /* Keep this window usable. */ }
  applyDocumentLanguage();
  if (typeof window !== "undefined") window.dispatchEvent(new Event(CHANGE_EVENT));
}

const listeners = new Set<() => void>();
function notifyLocale() {
  applyDocumentLanguage();
  for (const listener of listeners) listener();
}
function onLanguageStorage(event: StorageEvent) {
  if (event.key !== STORAGE_KEY && event.key !== null) return;
  preference = loadLanguagePreference();
  notifyLocale();
}

export function subscribeLocale(onChange: () => void) {
  if (typeof window === "undefined") return () => {};
  if (listeners.size === 0) {
    window.addEventListener(CHANGE_EVENT, notifyLocale);
    window.addEventListener("languagechange", notifyLocale);
    window.addEventListener("storage", onLanguageStorage);
  }
  listeners.add(onChange);
  return () => {
    listeners.delete(onChange);
    if (listeners.size === 0) {
      window.removeEventListener(CHANGE_EVENT, notifyLocale);
      window.removeEventListener("languagechange", notifyLocale);
      window.removeEventListener("storage", onLanguageStorage);
    }
  };
}

/** Subscribe at the rendering boundary, including memoized components. */
export function useLocale(): Locale {
  return useSyncExternalStore(subscribeLocale, getLocale, () => "en");
}

export function useLanguagePreference(): LanguagePreference {
  return useSyncExternalStore(subscribeLocale, getLanguagePreference, () => "system");
}

const messages: Readonly<Record<string, string>> = zhCN;
/** Only app-owned copy belongs here. Never pass user or provider-authored content. */
export function t(source: string, ...values: (string | number)[]): string {
  const message = getLocale() === "zh-CN" ? (messages[source] ?? source) : source;
  return message.replace(/\{(\d+)\}/g, (placeholder, index: string) =>
    values[Number(index)] === undefined ? placeholder : String(values[Number(index)]));
}

export function initLocale() {
  applyDocumentLanguage();
  return subscribeLocale(applyDocumentLanguage);
}
