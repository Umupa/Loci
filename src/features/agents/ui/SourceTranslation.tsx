import { useMemo, useSyncExternalStore } from "react";
import { Languages } from "../../../shared/ui/icons";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { agentLook, findAgent } from "../model/agent";
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

/** The switch between the two languages, and what is still to translate. */
export function TranslationBar({ state, view, onView, document, agentId, section }: {
  state: SourceTranslationState;
  view: TranslationView;
  onView: (view: TranslationView) => void;
  document: AgentDocument;
  agentId: string;
  section?: string;
}) {
  const { language, units, translated, stale } = state;
  const missing = units.length - translated;
  const agent = findAgent(agentId);
  const mentor = agent ? agentLook(agent).name : "your mentor";
  const ask = () => {
    const part = section ? `the section "${section}" of the source` : "the source";
    requestAddToChat(`Please translate ${part} "${document.title}" (${document.id}) into ${language.name} with documents.translate${stale ? ", including the parts that are out of date" : ""}.`, "plain",
      agent?.sessionId ? { targetSessionId: agent.sessionId } : undefined);
  };
  const views: [TranslationView, string][] = [["translated", language.label], ["original", "Original"], ["both", "Both"]];
  return <div data-translation-bar className="translation-bar">
    {translated ? <div role="radiogroup" aria-label="Read in" className="translation-bar__views">
      {views.map(([value, label]) => <button key={value} type="button" role="radio" aria-checked={view === value} onClick={() => onView(value)}>{label}</button>)}
    </div> : null}
    <span className="translation-bar__status">
      <Languages aria-hidden className="size-3.5 shrink-0" />
      {translated
        ? <>Translated by {mentor}, not the original{missing || stale ? <> · {missing ? `${missing} of ${units.length} parts untranslated` : ""}{missing && stale ? ", " : ""}{stale ? `${stale} out of date` : ""}</> : null}</>
        : <>Not translated into {language.label} yet</>}
    </span>
    {missing || stale ? <button type="button" className="translation-bar__ask" onClick={ask}>Ask {mentor} to translate</button> : null}
  </div>;
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
