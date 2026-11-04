import { useEffect, useRef, useState, useMemo, useSyncExternalStore, type ReactNode } from "react";
import { Languages } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import { RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { agentLook, findAgent } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";
import { effectiveLearningLanguage, LEARNING_LANGUAGES } from "../model/learningLanguage";
import { looksForeign, sectionUnits, shownUnits, sourceUnits, type ShownUnit } from "../../learning/model/sourceTranslation";
import { useSourceTranslation } from "../../learning/model/sourceTranslationStore";
import type { AgentDocument } from "../../sessions/model/cards";

/*
 * A source read in the learner's language. The original is still what is
 * kept, cited and highlighted; the translation is shown in its place
 * ("Translated"), or unit by unit beneath it ("Both").
 */
export type TranslationView = "translated" | "original" | "both";

const VIEW_KEY = "loci.translationView";
const listeners = new Set<() => void>();

function loadView(): TranslationView {
  try {
    const value = localStorage.getItem(VIEW_KEY);
    return value === "original" || value === "both" ? value : "translated";
  } catch {
    return "translated";
  }
}

function saveView(view: TranslationView) {
  try { localStorage.setItem(VIEW_KEY, view); } catch { /* this window only */ }
  for (const listener of listeners) listener();
}

/** One choice for every source, remembered. */
export function useTranslationView(): [TranslationView, (view: TranslationView) => void] {
  const view = useSyncExternalStore((listener) => { listeners.add(listener); return () => { listeners.delete(listener); }; }, loadView, () => "translated" as const);
  return [view, saveView];
}

export type SourceTranslationState = {
  language: (typeof LEARNING_LANGUAGES)[number];
  units: ShownUnit[];
  translated: number;
  stale: number;
};

/**
 * What there is to read in the learner's language for the part of a source
 * on screen: nothing when they follow their own messages, when this is not a
 * Markdown source, or when it is already in their language and untranslated.
 */
export function useSourceTranslationState(document: AgentDocument, agentId: string | undefined, section: string | undefined): SourceTranslationState | undefined {
  const own = agentId ? findAgent(agentId)?.language : undefined;
  const chosen = agentId ? effectiveLearningLanguage(own) : "auto";
  const language = LEARNING_LANGUAGES.find((entry) => entry.id === chosen);
  const eligible = !!language && !!document.sourceUrl && !document.pdf;
  const translation = useSourceTranslation(eligible ? agentId : undefined, document.id, language?.id);
  const units = useMemo(() => eligible ? sectionUnits(sourceUnits(document.body), section) : [], [eligible, document.body, section]);
  return useMemo(() => {
    if (!eligible || !language || !translation) return undefined;
    const shown = shownUnits(units, translation);
    const translated = shown.filter((unit) => unit.translation).length;
    if (!translated && !looksForeign(document.body, language.id)) return undefined;
    return { language, units: shown, translated, stale: shown.filter((unit) => unit.stale).length };
  }, [eligible, language, translation, units, document.body]);
}

/** What is left to translate, and the request that asks the mentor for it. */
function translationAsk(state: SourceTranslationState, document: AgentDocument, agentId: string, section?: string) {
  const { language, units, translated, stale } = state;
  const missing = units.length - translated;
  const agent = findAgent(agentId);
  const look = agent ? agentLook(agent) : undefined;
  const mentor = look?.name ?? "your mentor";
  const ask = () => {
    const part = section ? `the section "${section}" of the source` : "the source";
    requestAddToChat(`Please translate ${part} "${document.title}" (${document.id}) into ${language.name} with documents.translate${stale ? ", including the parts that are out of date" : ""}.`, "plain",
      agent?.sessionId ? { targetSessionId: agent.sessionId } : undefined);
  };
  const todo = [missing ? `${missing} of ${units.length} parts untranslated` : "", stale ? `${stale} out of date` : ""].filter(Boolean).join(", ");
  return { missing, mentor, look, ask, todo };
}

/** The switch between the two languages, and what is still to translate, as a bar over the text. */
export function TranslationBar({ state, view, onView, document, agentId, section }: {
  state: SourceTranslationState;
  view: TranslationView;
  onView: (view: TranslationView) => void;
  document: AgentDocument;
  agentId: string;
  section?: string;
}) {
  const { language, translated, stale } = state;
  const { missing, mentor, ask, todo } = translationAsk(state, document, agentId, section);
  const views: [TranslationView, string][] = [["translated", language.label], ["original", "Original"], ["both", "Both"]];
  // Whose words these are is said on hover; only what is still to do shows.
  const provenance = `Translated by ${mentor}, not the original`;
  return <div data-translation-bar className="translation-bar">
    {translated ? <div role="radiogroup" aria-label="Read in" title={provenance} className="translation-bar__views">
      {views.map(([value, label]) => <button key={value} type="button" role="radio" aria-checked={view === value} onClick={() => onView(value)}>{label}</button>)}
    </div> : <span className="translation-bar__status">Not translated into {language.label} yet</span>}
    {missing || stale ? <button type="button" className="translation-bar__ask" title={todo} onClick={ask}>Ask {mentor} to translate</button> : null}
  </div>;
}

/**
 * The same switch as one icon in the reader's header: pale while nothing is
 * translated, with a dot while some is still to do, ink once there is a
 * translation. Its menu reads in the learner's language, the original or
 * both, and asks the mentor for the rest. ⌥T flips translation and original.
 */
export function TranslationButton({ state, view, onView, document, agentId, section }: {
  state: SourceTranslationState;
  view: TranslationView;
  onView: (view: TranslationView) => void;
  document: AgentDocument;
  agentId: string;
  section?: string;
}) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const { language, translated, stale } = state;
  const { missing, mentor, look, ask, todo } = translationAsk(state, document, agentId, section);
  const phase = !translated ? "none" : missing || stale ? "partial" : "done";
  const label = !translated ? `Translate into ${language.label}` : view === "original" ? "Reading the original" : `Reading in ${language.label}`;
  useEffect(() => {
    if (!translated) return;
    const flip = (event: KeyboardEvent) => {
      if (!event.altKey || event.metaKey || event.ctrlKey || event.shiftKey || event.code !== "KeyT" || isImeComposition(event)) return;
      const target = event.target;
      if (target instanceof Element && target.closest("input, textarea, select, [contenteditable='true']")) return;
      event.preventDefault();
      onView(view === "original" ? "translated" : "original");
    };
    window.addEventListener("keydown", flip);
    return () => window.removeEventListener("keydown", flip);
  }, [translated, view, onView]);
  // Each way of reading has a glyph: the learner's script, the source's, or both.
  const own = language.id === "zh-CN" ? "中" : "En";
  const source = language.id === "zh-CN" ? "Aa" : "文";
  const views: [TranslationView, string, ReactNode][] = [
    ["translated", language.label, own],
    ["original", "Original", source],
    ["both", "Both", <span key="both" className="translation-glyph__pair"><span>{source}</span><span>{own}</span></span>],
  ];
  return <>
    <button ref={trigger} type="button" data-translation-button data-phase={phase} data-tauri-drag-region="false"
      className={`${RESOURCE_ACTION} translation-button`} aria-label={label} title={translated ? `${label} · ⌥T` : label}
      aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((value) => !value)}>
      <Languages className="size-4" />
    </button>
    {open ? <Popover anchor={trigger} side="bottom" align="end" width={224} role="menu" aria-label="Translation" onDismiss={() => setOpen(false)} className="lesson-menu translation-menu p-1.5 font-sans">
      {translated ? views.map(([value, text, glyph]) => <button key={value} type="button" role="menuitemradio" aria-checked={view === value}
        title={value === "original" ? undefined : `Translated by ${mentor}, not the original`}
        onClick={() => { setOpen(false); onView(value); }} className="lesson-menu__item translation-menu__view">
        <span aria-hidden className="translation-glyph">{glyph}</span>
        <span className="lesson-menu__label">{text}</span>
      </button>) : null}
      {translated && (missing || stale) ? <div role="separator" className="lesson-menu__rule" /> : null}
      {missing || stale ? <button type="button" role="menuitem" title={todo} onClick={() => { setOpen(false); ask(); }} className="lesson-menu__item translation-menu__ask">
        {look ? <AgentAvatar name={look.avatar} color={look.color} className="size-[18px] shrink-0" /> : <Languages className="lesson-menu__icon" />}
        <span className="lesson-menu__label">{translated ? `Ask ${mentor} for the rest` : `Ask ${mentor} to translate`}</span>
      </button> : null}
    </Popover> : null}
  </>;
}

/** The translated text, or both texts unit by unit; untranslated parts stay in the original. */
export function TranslatedText({ units, view, sourceUrl }: { units: ShownUnit[]; view: Exclude<TranslationView, "original">; sourceUrl?: string }) {
  if (view === "both") return <div className="translation-both">
    {units.map((unit, index) => <section key={index} className="translation-pair">
      <div className="translation-pair__original" lang="und"><AgentMarkdown text={unit.text} wholeDocument sourceUrl={sourceUrl} /></div>
      {unit.translation ? <div className="translation-pair__translated">
        {unit.stale ? <p className="translation-stale">Out of date: the original changed since this was translated.</p> : null}
        <AgentMarkdown text={unit.translation} wholeDocument sourceUrl={sourceUrl} />
      </div> : null}
    </section>)}
  </div>;
  // Runs of translated and untranslated units, each rendered once.
  const runs: { translated: boolean; stale: boolean; text: string }[] = [];
  for (const unit of units) {
    const translated = !!unit.translation;
    const stale = !!unit.stale;
    const text = unit.translation ?? unit.text;
    const last = runs[runs.length - 1];
    if (last && last.translated === translated && last.stale === stale) last.text += `\n\n${text}`;
    else runs.push({ translated, stale, text });
  }
  return <div className="translation-text">
    {runs.map((run, index) => <div key={index} className={run.translated ? "translation-run" : "translation-run translation-run--original"} data-untranslated={run.translated ? undefined : ""}>
      {!run.translated ? <p className="translation-run__note">Not translated yet, shown in the original</p> : run.stale ? <p className="translation-stale">Out of date: the original changed since this was translated.</p> : null}
      <AgentMarkdown text={run.text} wholeDocument sourceUrl={sourceUrl} />
    </div>)}
  </div>;
}
