import { getLocale, t, useLocale } from "../../../shared/i18n/locale";
import { useEffect, useState, useSyncExternalStore } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { fileResourceUrl, parseAppResourceUrl, requestOpenAppResource } from "../../../shared/lib/appResourceLinks";
import { ChevronDown, ChevronUp, Eye, StickyNote } from "../../../shared/ui/icons";
import { LEARN_RECALL_EVENT, liftRecallCover, overruleLearnRecall, recallCovered } from "../bridge";
import type { LearnSource, MapNode, RecallVerdict } from "../model/learnMap";

/** Fired on `window` to start a learning session about a node of a map. */
export const LEARN_START_EVENT = "loci:learn-start";
export type LearnStart = { canvasId: string; nodeId: string; label: string; intent: "explore" | "revisit" };

const STATE_LABEL: Record<MapNode["state"], string> = {
  get ghost() { return t("Not learned yet"); }, get solid() { return t("Explained"); }, get anchored() { return t("Lasting"); }, get open() { return t("Open judgment"); }, get closed() { return t("Looked back"); },
};
const EVENT_LABEL: Record<string, string> = {
  said: "said", drew: "drew", get prior() { return t("already knew"); }, get did() { return t("used (the agent's statement)"); }, recall: "revisit", get reality() { return t("looked back"); },
};
const VERDICTS: readonly RecallVerdict[] = ["solid", "shaky", "gone"];

const date = (ms: number) => new Date(ms).toLocaleDateString(getLocale(), { year: "numeric", month: "short", day: "numeric" });
const button = "h-6 shrink-0 rounded px-2 text-[11px] text-content/75 hover:bg-content/10 hover:text-content disabled:opacity-40";

function openSource(source: LearnSource) {
  if ("url" in source) { void openUrl(source.url).catch(() => undefined); return; }
  const place = source.page !== undefined ? { page: source.page } : source.lines ? { lines: source.lines } : undefined;
  const resource = parseAppResourceUrl(fileResourceUrl(source.path, place));
  if (resource) requestOpenAppResource(resource);
}

function sourceLabel(source: LearnSource): string {
  if ("url" in source) return t("{0} · read {1}", source.url, source.accessedAt);
  return `${source.path}${source.page !== undefined ? `, p. ${source.page}` : source.lines ? t(", lines {0}–{1}", source.lines[0], source.lines[1]) : ""}`;
}

/** The strip under a learning map for the node the learner has selected. */
export function LearnInspector({ canvasId, node }: { canvasId: string; node: MapNode }) {
  useLocale();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setError(null); }, [node.id]);
  const start = (intent: LearnStart["intent"]) =>
    window.dispatchEvent(new CustomEvent<LearnStart>(LEARN_START_EVENT, { detail: { canvasId, nodeId: node.id, label: node.label, intent } }));
  const last = node.history[node.history.length - 1];
  const revisitable = node.kind === "concept" ? node.state !== "ghost" : node.state === "open";
  const when = !revisitable || node.dueAt === undefined ? null : node.due
    ? node.kind === "judgment" ? t("Time to look back") : t("Revisit due")
    : `${node.kind === "judgment" ? t("Look back") : t("Next revisit")} ${date(node.dueAt)}`;
  return (
    <div data-learn-inspector className="shrink-0 border-t border-stroke bg-background-base text-xs text-content">
      <div className="flex h-9 items-center gap-2 px-2">
        <span className={`size-2 shrink-0 rounded-full ${node.state === "ghost" ? "border border-dashed border-content/50" : node.state === "solid" || node.state === "open" ? "bg-content/60" : "bg-accent"}`} />
        {/* The name keeps the room: a pane beside a chat is narrow. */}
        <span className="min-w-0 flex-1 truncate font-medium" title={node.label}>{node.label || t("Untitled")}</span>
        <span className={`shrink-0 ${node.due ? "text-amber-400" : "text-content/50"}`} title={when ?? undefined}>{node.due ? when : STATE_LABEL[node.state]}</span>
        {node.kind === "concept" && node.state === "ghost" ? <button type="button" className={button} onClick={() => start("explore")}>{t("Explore")}</button> : null}
        {revisitable ? <button type="button" className={button} onClick={() => start("revisit")}>{node.kind === "judgment" ? t("Look back") : t("Revisit")}</button> : null}
        {node.noteId ? (
          <button type="button" className={`${button} flex items-center gap-1`} title={t("Open the note with your words")} onClick={() => requestOpenAppResource({ kind: "note", id: node.noteId! })}>
            <StickyNote className="size-3.5" />{t("Note")}</button>
        ) : null}
        <button type="button" aria-label={open ? t("Hide details") : t("Show details")} aria-expanded={open} title={open ? t("Hide details") : t("Show details")}
          className="grid size-6 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content" onClick={() => setOpen(!open)}>
          {open ? <ChevronDown className="size-3.5" /> : <ChevronUp className="size-3.5" />}
        </button>
      </div>
      {open ? (
        <div className="max-h-40 space-y-2 overflow-auto border-t border-stroke px-3 py-2 text-[11px] text-content/70">
          <p>{STATE_LABEL[node.state]}{when ? ` · ${when}` : ""}{node.unsourced ? t(" · recorded without a source") : ""}</p>
          {node.sources?.length ? (
            <div>
              <p className="mb-0.5 text-content/45">{t("Sources")}</p>
              {node.sources.map((source, index) => (
                <button key={index} type="button" className="block max-w-full truncate text-left text-sky-400/90 hover:underline" onClick={() => openSource(source)}>{sourceLabel(source)}</button>
              ))}
            </div>
          ) : null}
          <div>
            <p className="mb-0.5 text-content/45">{t("History")}</p>
            {node.history.length ? node.history.map((event, index) => (
              <p key={index}>{date(event.at)} · {EVENT_LABEL[event.type] ?? event.type}{event.verdict ? ` · ${event.verdict}` : ""}</p>
            )) : <p>{t("Nothing recorded yet.")}</p>}
          </div>
          {node.kind === "concept" && last?.type === "recall" && last.from ? (
            <div className="flex flex-wrap items-center gap-1">
              <span className="text-content/45">{t("Disagree with the last verdict?")}</span>
              {VERDICTS.map((verdict) => (
                <button key={verdict} type="button" disabled={verdict === last.verdict} className={button}
                  onClick={() => void overruleLearnRecall(canvasId, node.id, verdict).then(() => setError(null), (cause: unknown) => setError(cause instanceof Error ? cause.message : String(cause)))}>
                  {verdict}
                </button>
              ))}
            </div>
          ) : null}
          {error ? <p role="alert" className="text-red-400">{error}</p> : null}
        </div>
      ) : null}
    </div>
  );
}

function subscribeRecall(listener: () => void): () => void {
  window.addEventListener(LEARN_RECALL_EVENT, listener);
  return () => window.removeEventListener(LEARN_RECALL_EVENT, listener);
}

/** Hides the map while the learner explains a node from memory. Looking is allowed, and counted. */
export function RecallCover({ canvasId }: { canvasId: string }) {
  useLocale();
  const covered = useSyncExternalStore(subscribeRecall, () => recallCovered(canvasId), () => false);
  if (!covered) return null;
  return (
    <div data-learn-recall-cover role="status" className="absolute inset-0 z-10 grid place-items-center bg-background-base text-center text-content">
      <div className="max-w-xs space-y-3 px-6">
        <p className="text-sm font-medium">{t("Revisit in progress")}</p>
        <p className="text-xs text-content/55">{t("The map is covered so you can explain from memory. It comes back when you have answered.")}</p>
        <button type="button" className="mx-auto flex h-7 items-center gap-1.5 rounded px-2.5 text-xs text-content/60 hover:bg-content/10 hover:text-content"
          title={t("Looking is fine. The revisit then counts as shaky instead of solid.")} onClick={() => liftRecallCover(canvasId)}>
          <Eye className="size-3.5" />{t("Show the map")}</button>
      </div>
    </div>
  );
}
